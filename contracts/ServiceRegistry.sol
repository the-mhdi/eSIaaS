// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*
 *  ServiceRegistry.sol
 *
 *  - Manages services (formerly "jobs"): creation, funding (escrow), provider joins, proofs, payment claims, slashing requests.
 *  - Uses ProviderRegistry to check provider stake & to notify join/leave and to perform slashes.
 *
 *  Payment model: per-proof immediate claim (simple, avoids iterating over providers). You can evolve to epoch settlement later.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IProviderRegistry {
    function isRegistered(address addr) external view returns (bool);
    function getStake(address addr) external view returns (uint256);
    function notifyServiceJoined(address providerAddr) external;
    function notifyServiceLeft(address providerAddr) external;
    function slash(address providerAddr, uint256 amount, address developerRecipient) external;
    function getServiceCount(address addr) external view returns (uint256);
}

contract ServiceRegistry is ReentrancyGuard, Ownable {
    IERC20 public immutable token;
    IProviderRegistry public providerRegistry;

    uint256 public nextServiceId = 1;

    struct ProviderService {
        uint256 joinedAt;
        uint256 lastProofAt;
        uint256 paid;
        bool slashed;
        bool active;
    }

    struct Service {
        address developer;
        bytes32 containerHash;
        uint256 requiredStake;        // min stake required to join (checked against ProviderRegistry)
        uint256 replicasRequested;   //replication factor == how many providers do you want? 
        uint256 paymentPerProof;
        uint256 escrow;               // remaining escrow
        uint256 createdAt;
        uint256 duration;
        uint256 maxOfflineInterval;   // seconds provider allowed without proof
        bool active;
        // provider mapping
        mapping(address => ProviderService) providers;
        uint256 totalProviders;
    }

    mapping(uint256 => Service) private services;

    // Events
    event ServiceCreated(uint256 indexed serviceId, address indexed developer, bytes32 containerHash, uint256 replicas);
    event ServiceFunded(uint256 indexed serviceId, uint256 amount, uint256 escrow);
    event ProviderJoinedService(uint256 indexed serviceId, address indexed provider);
    event ProviderLeftService(uint256 indexed serviceId, address indexed provider);
    event ProofSubmitted(uint256 indexed serviceId, address indexed provider, bytes attestation);
    event PaymentClaimed(uint256 indexed serviceId, address indexed provider, uint256 amount);
    event ProviderSlashed(uint256 indexed serviceId, address indexed provider, uint256 amount);
    event ServiceClosed(uint256 indexed serviceId, uint256 refunded);

    modifier onlyActiveService(uint256 serviceId) {
        require(services[serviceId].active, "service not active");
        _;
    }

    constructor(IERC20 _token, address _providerRegistry) {
        require(address(_token) != address(0), "zero token");
        require(_providerRegistry != address(0), "zero provider registry");
        token = _token;
        providerRegistry = IProviderRegistry(_providerRegistry);
    }

    /// @notice owner can update providerRegistry if needed
    function setProviderRegistry(address _new) external onlyOwner {
        require(_new != address(0), "zero addr");
        providerRegistry = IProviderRegistry(_new);
    }

    /* ========== SERVICE CREATION & FUNDING ========== */

    /// @notice Developer creates a service and funds escrow in the same call (must approve tokens).
    function createService(
        bytes32 containerHash,
        uint256 requiredStake,
        uint256 replicasRequested,
        uint256 paymentPerProof,
        uint256 totalEscrow,
        uint256 duration,
        uint256 maxOfflineInterval
    ) external nonReentrant returns (uint256 serviceId) {
        require(totalEscrow >= paymentPerProof, "escrow < payment per proof");
        require(duration > 0, "duration 0");
        require(maxOfflineInterval > 0, "maxOfflineInterval 0");

        // transfer escrow
        require(token.transferFrom(msg.sender, address(this), totalEscrow), "transferFrom failed");

        serviceId = nextServiceId++;
        Service storage s = services[serviceId];
        s.developer = msg.sender;
        s.containerHash = containerHash;
        s.requiredStake = requiredStake;
        s.replicasRequested = replicasRequested;
        s.paymentPerProof = paymentPerProof;
        s.escrow = totalEscrow;
        s.createdAt = block.timestamp;
        s.duration = duration;
        s.maxOfflineInterval = maxOfflineInterval;
        s.active = true;
        s.totalProviders = 0;

        emit ServiceCreated(serviceId, msg.sender, containerHash, replicasRequested);
        emit ServiceFunded(serviceId, totalEscrow, s.escrow);
    }

    /// @notice Developer can top-up escrow for a service (approve + transfer).
    function fundService(uint256 serviceId, uint256 amount) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        require(msg.sender == s.developer, "only developer");
        require(amount > 0, "amount 0");
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        s.escrow += amount;
        emit ServiceFunded(serviceId, amount, s.escrow);
    }

    /* ========== PROVIDER JOIN / LEAVE ========== */

    /// @notice Provider joins a service. Their global stake is checked in ProviderRegistry (stake is NOT moved).
    function joinService(uint256 serviceId) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        require(block.timestamp <= s.createdAt + s.duration, "service expired");
        ProviderService storage ps = s.providers[msg.sender];
        require(!ps.active, "already joined");

        // check provider registration & stake
        require(providerRegistry.isRegistered(msg.sender), "provider not registered");
        uint256 staked = providerRegistry.getStake(msg.sender);
        require(staked >= s.requiredStake, "provider stake below required");

        // mark local join
        ps.joinedAt = block.timestamp;
        ps.active = true;
        ps.lastProofAt = 0;
        ps.paid = 0;
        ps.slashed = false;

        s.totalProviders += 1;
        // notify provider registry to increment global service count
        providerRegistry.notifyServiceJoined(msg.sender);

        emit ProviderJoinedService(serviceId, msg.sender);
    }

    /// @notice Provider voluntarily leaves a service (before or after service ends). Allows providerRegistry to decrement service count.
    function leaveService(uint256 serviceId) external nonReentrant {
        Service storage s = services[serviceId];
        ProviderService storage ps = s.providers[msg.sender];
        require(ps.active, "not a member");

        ps.active = false;
        s.totalProviders -= 1;
        providerRegistry.notifyServiceLeft(msg.sender);
        emit ProviderLeftService(serviceId, msg.sender);
    }

    /* ========== PROOFS & PAYMENT ========== */

    /// @notice Provider submits an attestation/proof (emitted so off-chain verifiers can validate).
    function submitProof(uint256 serviceId, bytes calldata attestation) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        ProviderService storage ps = s.providers[msg.sender];
        require(ps.active && !ps.slashed, "not active or slashed");

        ps.lastProofAt = block.timestamp;
        emit ProofSubmitted(serviceId, msg.sender, attestation);
    }

    /// @notice Provider claims payment for most recent proof.
    function claimPayment(uint256 serviceId) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        ProviderService storage ps = s.providers[msg.sender];
        require(ps.active && !ps.slashed, "not active or slashed");
        require(ps.lastProofAt != 0, "no proof submitted");

        uint256 pay = s.paymentPerProof;
        require(s.escrow >= pay, "insufficient escrow");

        s.escrow -= pay;
        ps.paid += pay;

        require(token.transfer(msg.sender, pay), "transfer failed");
        emit PaymentClaimed(serviceId, msg.sender, pay);
    }

    /* ========== SLASHING FLOW ========== */

    /// @notice Request a slash for a provider in a service. Allowed caller: service developer or contract owner (owner can be a verifier orchestrator).
    /// The actual stake deduction happens in ProviderRegistry (which holds stakes).
    /// distribution handled by ProviderRegistry.slash (we pass the developer as recipient).
    function slashProvider(uint256 serviceId, address providerAddr, uint256 amount) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        require(msg.sender == s.developer || msg.sender == owner(), "not authorized to slash");
        ProviderService storage ps = s.providers[providerAddr];
        require(ps.active, "provider not active for service");

        // mark provider as slashed in this service
        ps.slashed = true;
        ps.active = false;
        s.totalProviders -= 1;

        // notify providerRegistry about leaving the service (decrement service count)
        providerRegistry.notifyServiceLeft(providerAddr);

        // instruct ProviderRegistry to slash global stake; pass developer as recipient
        providerRegistry.slash(providerAddr, amount, s.developer);

        emit ProviderSlashed(serviceId, providerAddr, amount);
    }

    /* ========== SERVICE LIFECYCLE ========== */

    /// @notice Developer can close a service early and reclaim remaining escrow.
    function closeService(uint256 serviceId) external nonReentrant onlyActiveService(serviceId) {
        Service storage s = services[serviceId];
        require(msg.sender == s.developer, "only developer");
        s.active = false;

        uint256 rem = s.escrow;
        s.escrow = 0;

        if (rem > 0) {
            require(token.transfer(s.developer, rem), "refund failed");
        }

        emit ServiceClosed(serviceId, rem);
    }

    /* ========== HELPERS & VIEWS ========== */

    function getServiceBasic(uint256 serviceId) external view returns (
        address developer,
        bytes32 containerHash,
        uint256 requiredStake,
        uint256 replicasRequested,
        uint256 paymentPerProof,
        uint256 escrow,
        uint256 createdAt,
        uint256 duration,
        uint256 maxOfflineInterval,
        bool active,
        uint256 totalProviders
    ) {
        Service storage s = services[serviceId];
        return (
            s.developer,
            s.containerHash,
            s.requiredStake,
            s.replicasRequested,
            s.paymentPerProof,
            s.escrow,
            s.createdAt,
            s.duration,
            s.maxOfflineInterval,
            s.active,
            s.totalProviders
        );
    }

    function getProviderServiceInfo(uint256 serviceId, address providerAddr) external view returns (
        uint256 joinedAt,
        uint256 lastProofAt,
        uint256 paid,
        bool slashed,
        bool active
    ) {
        Service storage s = services[serviceId];
        ProviderService storage ps = s.providers[providerAddr];
        return (ps.joinedAt, ps.lastProofAt, ps.paid, ps.slashed, ps.active);
    }
}
