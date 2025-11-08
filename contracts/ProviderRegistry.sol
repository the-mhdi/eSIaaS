// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*
 *  ProviderRegistry.sol
 *
 *  - Manages global provider registration & staking.
 *  - Keeps basic provider metadata.
 *  - Allows an authorized ServiceRegistry contract to increment/decrement provider's service count and call slash.
 *
 *  Designed as an independent contract so ServiceRegistry can be upgraded or replaced.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ProviderRegistry is Ownable, ReentrancyGuard {
    IERC20 public immutable token;
    address public serviceRegistry;       // authorized ServiceRegistry contract that can notify joins/leaves & request slashes
    address public treasury;              // receives slashed funds portion

    uint256 public constant MIN_NETWORK_STAKE = 1_000 * 1e18; // example default, can be replaced per-deployment

    struct Provider {
        uint256 stakedAmount;
        bool active;
        uint256 registeredAt;
        uint256 lastHeartbeat;
        uint256 totalServicesJoined;
    }

    mapping(address => Provider) public providers;

    // Events
    event ProviderRegistered(address indexed provider, uint256 amount);
    event StakeIncreased(address indexed provider, uint256 amount);
    event StakeWithdrawn(address indexed provider, uint256 amount);
    event ServiceCountIncremented(address indexed provider, uint256 newCount);
    event ServiceCountDecremented(address indexed provider, uint256 newCount);
    event ProviderSlashed(address indexed provider, uint256 amountSlashed, address indexed toDeveloper, uint256 toTreasury);

    modifier onlyServiceRegistry() {
        require(msg.sender == serviceRegistry, "ProviderRegistry: caller not ServiceRegistry");
        _;
    }

    constructor(IERC20 _token, address _treasury) {
        require(address(_token) != address(0), "zero token");
        require(_treasury != address(0), "zero treasury");
        token = _token;
        treasury = _treasury;
    }

    /// @notice Owner sets the ServiceRegistry address (only once or can be changed by owner).
    function setServiceRegistry(address _svc) external onlyOwner {
        require(_svc != address(0), "zero address");
        serviceRegistry = _svc;
    }

    /// @notice Owner can change treasury (where slashed funds go).
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero address");
        treasury = _treasury;
    }

    /* ========== PROVIDER LIFECYCLE ========== */

    /// @notice Register as a provider on the network by staking tokens. Must approve token transfer first.
    function registerProvider(uint256 amount) external nonReentrant {
        require(!providers[msg.sender].active, "already registered");
        require(amount >= MIN_NETWORK_STAKE, "stake < min");

        // transfer stake to this contract
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        providers[msg.sender] = Provider({
            stakedAmount: amount,
            active: true,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp,
            totalServicesJoined: 0
        });

        emit ProviderRegistered(msg.sender, amount);
    }

    /// @notice Increase existing provider's stake (must be registered)
    function increaseStake(uint256 amount) external nonReentrant {
        Provider storage p = providers[msg.sender];
        require(p.active, "not registered");
        require(amount > 0, "amount 0");
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        p.stakedAmount += amount;
        emit StakeIncreased(msg.sender, amount);
    }

    /// @notice Withdraw stake. Only allowed when not currently serving any services.
    function withdrawStake(uint256 amount) external nonReentrant {
        Provider storage p = providers[msg.sender];
        require(p.active, "not registered");
        require(amount > 0 && amount <= p.stakedAmount, "invalid amount");
        require(p.totalServicesJoined == 0, "cannot withdraw while serving");

        p.stakedAmount -= amount;
        // if all stake removed, mark inactive (optional)
        if (p.stakedAmount == 0) {
            p.active = false;
        }

        require(token.transfer(msg.sender, amount), "transfer failed");
        emit StakeWithdrawn(msg.sender, amount);
    }

    /// @notice Called by ServiceRegistry to increment provider's service count when provider joins a service.
    function notifyServiceJoined(address providerAddr) external onlyServiceRegistry {
        Provider storage p = providers[providerAddr];
        require(p.active, "provider not registered");
        p.totalServicesJoined += 1;
        emit ServiceCountIncremented(providerAddr, p.totalServicesJoined);
    }

    /// @notice Called by ServiceRegistry to decrement provider's service count when provider leaves a service.
    function notifyServiceLeft(address providerAddr) external onlyServiceRegistry {
        Provider storage p = providers[providerAddr];
        require(p.totalServicesJoined > 0, "no services joined");
        p.totalServicesJoined -= 1;
        emit ServiceCountDecremented(providerAddr, p.totalServicesJoined);
    }

    /// @notice Update provider heartbeat (optional). ServiceRegistry or provider can call to mark liveness.
    function heartbeat() external {
        Provider storage p = providers[msg.sender];
        require(p.active, "not registered");
        p.lastHeartbeat = block.timestamp;
    }

    /* ========== SLASHING ========== */

    /// @notice Slash a provider's global stake. Only callable by ServiceRegistry.
    /// @param providerAddr the provider to slash
    /// @param amount the amount to slash (will be bounded by current stake)
    /// @param developerRecipient address to receive part of the slashed funds (service developer)
    function slash(address providerAddr, uint256 amount, address developerRecipient) external onlyServiceRegistry nonReentrant {
        Provider storage p = providers[providerAddr];
        require(p.active || p.stakedAmount > 0, "provider no stake");

        uint256 slashAmount = amount;
        if (slashAmount > p.stakedAmount) slashAmount = p.stakedAmount;
        require(slashAmount > 0, "nothing to slash");

        p.stakedAmount -= slashAmount;
        // If stake drops to zero, mark inactive
        if (p.stakedAmount == 0) {
            p.active = false;
        }

        // Distribution policy: half to developer, half to treasury. (Can be adjusted.)
        uint256 toDev = slashAmount / 2;
        uint256 toTreasury = slashAmount - toDev;

        if (toDev > 0 && developerRecipient != address(0)) {
            require(token.transfer(developerRecipient, toDev), "transfer to dev failed");
        } else if (toDev > 0) {
            // if no dev address, send dev share to treasury
            toTreasury += toDev;
            toDev = 0;
        }

        if (toTreasury > 0) {
            require(token.transfer(treasury, toTreasury), "transfer to treasury failed");
        }

        emit ProviderSlashed(providerAddr, slashAmount, developerRecipient, toTreasury);
    }

    /* ========== VIEWS ========== */

    function isRegistered(address addr) external view returns (bool) {
        return providers[addr].active;
    }

    function getStake(address addr) external view returns (uint256) {
        return providers[addr].stakedAmount;
    }

    function getServiceCount(address addr) external view returns (uint256) {
        return providers[addr].totalServicesJoined;
    }

    function getLastHeartbeat(address addr) external view returns (uint256) {
        return providers[addr].lastHeartbeat;
    }
}
