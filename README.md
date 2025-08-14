### Ethereum’s Function-as-a-Service Layer (eFaaS)

a decentralized, verifiable, serverless runtime for Ethereum, allowing developers to run functions in zkWASM off-chain and prove results on-chain. This reduces L1 bloat, enables new capabilities, and unifies off-chain computation standards

it offers a standard interface for developers to deploy custom logic as Verifiable Functions that can be executed off-chain with cryptographic proof, all without consensus changes, hard forks, or the complexity of managing L2 infrastructure.


![Untitled Diagram drawio (1)](https://github.com/user-attachments/assets/a76e0ebf-96c4-487f-95b5-303b1ce4fe00) Fig. 1


# How Does It Work?
Middle-Nodes form a *semi-stateless network of ZK-WASM runtime machines, each middle-node can have its own set of desired Extensions, middle nodes maintain a routing table of their neighbours and their respective Extensions, upon receiving a transaction(userOperation) it gets added to a public mempool, a middle node would pick up a transaction, loads the specific WASM binary for the requested ExtensionID then executes the binary inside its zk-WASM runtime, generates the proof and then propagates the post-transaction(Post-operation), a middle node regardless of its extension-set would maintain a public mempool of all types of operaions and extensions. 


### Core Concepts : 
 #### * Middle-Client: new type of Ethereum node that sits between standard Execution clients and end-users
  * Maintains two mempools:
     1. Operation Mempool: unprocessed Operations
     2. PostOp Mempool: processed and validated Operations
  * Is a ZK-WASM runtime machine
  * Acts as a verifier of Extension outputs
  * Manages routing tables of peer Middle-Clients and their supported Extensions
  * Can enforce stake, fee, and reputation policies to prevent spam and maintain trust
  * Optionally participates in staking and slashing mechanisms to secure Operations economically
    
 #### * Extensions: a protocol-aware, customizable module that performs specialized computation/validation outside the EVM
  * Each Extension has a unique ExtensionID
  * Can be independently developed and deployed by any party
  * May require Middle-Clients to stake collateral, enabling slashing if the Extension produces invalid results
  * Makes Ethereum more modular, allowing new transaction types and processing logic without modifying consensus
  * Examples of Extension functionality: any type of private or public computation, a ERC-4337 bundler , a whole ethereum L2, 
  * could be written in any programming language as long as they're compilable and interpretable by WebAssembly Runtime
  * Extensions execute in private as opposed to EVM smart contract where everything executes in public.
  * Extensions do not change the blockchain state directly like smart contracts do, though they can call contracts and indirectly be responsible for a state change.
  * we require each middle-node to generate a zero-knowledge proof (ZKP) that it correctly executed the Extension.
  * All Extensions MUST be fully deterministic
  


 
we introduce two new (semi)transaction types. in regard to ERC-4337 we're calling them UserOperaions or simply Operations. 
 ### Operation Struct:
    type Operation struct {
      ExtensionID	string
      To       Address
      Gas      uint
      GasManagementData []byte
      Data     []byte
      Sig	     []byte
      BlockHash  []byte // block hash upon operation submission to pool //must be a finalized block
    }
 ### PostOperation Struct:
    type PostOp struct {
     OperationHash  string        // hash(Operation)
     ExtensionID   string
     Proof              Proof 
     Data               []byte
 
     ProcessedBlockHash []byte //block hash at the time of processing
    }

Middle RPC Nodes receive operations from users, they perform simple verifcation and reputaions management then the Operation would be submitted to the public mempool, middle nodes that have respective Extension to proccess that operation will pick it up, the operation would be processed and the post-prossessed operation will be sumbitted to another mempool called post-mempool.


so as shown on the diagram below the middle nodes manage and maintain two public mempools: Operation p2p Mempool and PostOp p2p mempool

![Untitled Diagram (5)](https://github.com/user-attachments/assets/a60fdd40-3b19-46e5-b893-c260a19d3ae0)





 # CHALLENGES

## Canonicality and Re-org Safety :
Before creating an Operation, the user's wallet queries an Execution node to get the hash of a recent, finalized block, it then gets included into the Operation.
After the Extension finishes its computation, it fetches the current block hash from the mainnet and includes it in the PostOp.
When a Middle Node receives and verifies the PostOp, it MUST performs a critical freshness check:

 1. It compares the ProcessedBlockHash against its own view of the blockchain.

 2. It enforces a rule: (RULE No. 1) the PostOp is only valid if its ProcessedBlockHash is very recent (for example, within the last 5-10 blocks).


If a re-org happens and the referenced block is orphaned (no longer part of the canonical chain), the Operation becomes instantly invalid. Middle Nodes can simply discard it because the previos state no longer exists. This prevents Extensions from processing operations based on a stale or reverted chain state.

the ProcessedBlockHash and RULE 1 also provide a defense against replay attacks, a malicious actor cannot take a valid PostOp from a week ago and submit it today, because the old ProcessedBlockHash would cause it to be immediately rejected as stale. 

* middle nodes CAN define a configurable PROCESS_WINDOW variable, it's an interval of slots in which an Operation is deemded valid.
  

## Incentive Mechanisms (TBD) :
middle nodes run Extenstions, since middle nodes work as provers and also verifiers in this architecture, middle nodes need to be paid fairly.

users also want their Operations processed for a predictable fee.
 
the gas fee can be paid by the user directly or be sponsered by another entity, all we need is an ERC4337 incentive flow and users commitment to a fee, this brings up a need for a singleton entrypoint-like contract we call it Consensus Contract. we'll be utilizing this contract to distribute rewards and gas, stake/slash incentive system etc.

### Consensus Contract : 
 there would be a singleton Consensus Contract, this contract :
  
* keeps track of submitter in each slot(epoch) -> noodes run a deterministic leader election algorithm (like the XOR check), consensus contract manages the compensation of middle nodes
* Fee and Reward Distribution
* stake/slash management
* Proof Validation
* Dispute Resolution

  
## Proof Formats and Trust Minimization : 
 the proof system must:

* generate efficient proofs and propagete them 

* Enable Middle Nodes to validate proofs deterministically.

* Avoid reliance on central trust.

* Be general enough to handle: ZK proofs (snarks/starks) and other cryptographic attestations (Merkle proofs, signatures).

* Allow efficient verification without heavy resource demands.

* Allow Middle nodes to send validity proof packets to other nodes and receives proof responses. (this is to maintain a vaild reputation system and prevent middle nodes from altering an extension functionality)

   #### standard Proof object: 
      type Proof struct {
      ExtensionID   string            // erc4337
      Inputs        map[string][]byte // Public inputs
      Output        []byte            // Post-processed result data (e.g., calldata)
      ProofData     []byte            // The proof itself (binary blob)
      Metadata      map[string]string // Optional metadata (versioning, etc.) 
      }
    


* Verifiability of Extensions Work: (nodes cross-verifying one another’s proofs)

   a peer challenge-response protocol (distributed attestation) 

  ### validity proof packets :

 We’ll define two main packet types:
 
   #### ProofVerificationRequest
  
      type ProofVerificationRequest struct {
        RequestID     string        // Unique ID for deduplication
        SenderNodeID  string        // Node issuing the request
        OperationID   string        // Hash of the original Operation
        PostOp        PostOp        // Full PostOp struct incl. Proof
        Timestamp     int64         // Unix timestamp
        Metadata      map[string]string // Optional context
        RequestHash  []byte
      }

   #### ProofVerificationResponse
      type ProofVerificationResponse struct {
      RequestID     string        // Echoed from the request
      ResponderNodeID string      // Who verified
      Verdict       VerificationVerdict // Enum: VALID / INVALID / ERROR
      Signature     []byte        // Signature over {RequestID, Verdict}
      Diagnostics   map[string]string // Optional error details
      Timestamp     int64
      }

  middle nodes use this information in order to manage the Reputation System.
   #### ProofVerificationReceipt (no sure if this one is needed)


### Proof System Flow:

1. Middle Node (A) produces a PostOp with attached Proof.

2. Before submitting on-chain, (A) broadcasts a ProofVerificationRequest to neighbors.

3. Neighboring nodes (Middle Nodes B, C, D) with the relevant Extensions re-verify the Proof.

4. Each neighbor returns a ProofVerificationResponse

* This creates a decentralized consensus over proof validity.
* This is the basis of middle nodes reputation system.

Nodes SHOULD rate limit verification requests per peer.

  ### Validity Attack protection : 
   how can we guarantee that: 1. The Extension logic is exactly the same logic other nodes expect for that ExtensionID? 2. The output and proof are produced by an approved implementation, not a malicious or buggy variant?

   we'll be using a ZK-wasm with a single, universal Verification Key and a Extension Registry Smart Contract
   
This ensures all proofs are generated only with that circuit. Every Middle Node can deterministically verify them and that there is no ambiguity about what code was executed.
## Extension Registry Smart Contract 
	
 ##### There MUST be a Registry Smart Contract that maintains the below mapping : 
    ExtensionID → {[]wasm_bytecode, metadataURI, isUniversal, verifierMetadata}

Middle nodes MUST only accept Operations referencing a known ExtensionID
Middle Nodes MUST check : (TBD)

#### Extension Registry Flow : 
two parties involved : Extension dev and Registry Smart Contract

1. Developer Prepares the Extension, the extension should be compilable WebAssembly
2. serializee .wasm to a canonical blob.
      * what do i mean by canonical blob ?
        A byte-serialized representation of a build artifact that every Middle Node can hash to the same value. we use WASM
        we MIGHT define a VerifierBinary struct in our design :

	developers have 2 Chooses over their Proof System design :
		1. Universal mode: Runtime uses a single global VK
   		2. Custom mode:  custom VK -> Having a VK per Extension stored in the on-chain Registry Contract. Nodes retrieve the VK and cache it locally.

       VerificationMode { Universal, Custom }
   
   		struct verifierMetadata {
   		 VerificationMode mode;      // Universal or Custom VK
  		  bytes zkSystem;              // e.g., "Groth16", "Plonk", "STARK"
   		  bytes verificationKey;       // Empty if using universal VK
   		  string verifierURI;           // Optional off-chain verifier metadata
			}

   		struct Extension {
		    	address developer;           // Owner / registrant
   			bytes32 extensionID;         // keccak256(wasmBinary)
   			 bytes wasm_bytecode;              // Hash of full WASM binary
    			verifierMetadata verifier;       // Verification metadata
    			string metadataURI;          // Human-readable info (docs, schema)
    			uint256 registeredAt;        // Block timestamp
			}
   
* To ensure all nodes get the same wasm_bytecode, WASM builds must be fully reproducible. A deterministic WASM toolchain and Pre-deployment CI pipeline that publishes a Merkleized build manifest is needed!




4. ExtensionID: it should be a unique string 

5. calling the registerExtension function of Registry Contract
   
   	    function registerExtension(
   		address developer;
   		string calldata extensionId,
   		bytes []wasm_bytecode
   		bytes calldata metadataURI
		bytes calldata verifierMetadata,
		uint256 registeredAt;        // Block timestamp
   		) external;

******* After this point *********

Any node or user can query the registry on-chain to get the canonical wasm bytecode.

### Middle Node Adding an Extension (Middle Node Onboarding)
  Imagine you are operating a Middle Node and want to add a new Extension to your already working set of Extensions (Fig. 1)
 1. query the on-chain registry -> GET ExtensionMetadata(extensionID)
 2. acquire the Extension code and compile it to .wasm
 3. Store Extension Locally
 4. Store Extension Metadata Locally :
 
        json {
        "ExtensionID": "erc4337-bundler-v1",
        "VerifierMetadata": {...},
    	"Metadata": {...},
        "Extension Dir": "/extensions/..."
        }
    
  5. modify the MiddleNode config file to register your extension, or run the register command (TBD)

### Operation Execution Flow and proof of honest Extension : 

  When a node and one of its extensions need to process a transaction(operation), we follows this process:

   1.The node starts with a known initial state (e.g., a hash of the current Operation, Extension Network-Wide state, Ethereum L1 state). (State TBD)

   2.Execute Program: middle node runs the WASM Extension and calls some functions, which take the initial state and some inputs, and produces a new state.
* Loads the specific WASM binary for the requested ExtensionID.
* Executes the binary inside its zk-WASM runtime.
* The runtime executes the code and automatically outputs the final ZKP and PostOp.



   3.local verification of Extension proof
  
  * The PostOp.Proof is verified against the single, universal Verification Key of the zk-WASM runtime. The public inputs for this verification must now include the wasm_bytecode_hash that was executed
   
   4.Network Verification
  
   The middle node then broadcasts its claimed PostOp along with the ZKP to the network.
   Other nodes act as verifiers. They do not re-run the program. They simply run the highly efficient ZKP verification algorithm using the Verification Key (VK), the initial state, the new state, and the proof.
  
*If the proof is valid, the network accepts the new state as legitimate.

*If a malicious node were to tamper with the Extension code or fake the result, it would be unable to produce a valid proof, and the network would reject its update
   



#### Runtime Verification Flow : what happens when your middle node receives a PostOP
 1. verify the proof by running ZKP verification algorithm
 2. if verified : sumbit to the PostOp pool
 3. re-run the Operation if : you recieved 2 or more PostOps of the same Operation to check the state trace.
(TBD)

  
(work in process) : 1. Define gossip strategies for distributing verification requests 2. build reputation scoring algorithms.

## Reputation System :
 reputation needs to be locally managed in two main scopes: 1. Extension Reputation 2. Middle-Node(peer) Reputation

### Data Models  
#### Extension Reputation
    type ExtensionReputation struct {
    //ValidProofRate
	// ValidProofCount / (ValidProofCount+InvalidProofCount) MUST BE > 0.8, too sensitive to initial failures, two defaults: prior_valid_proofs and prior_invalid_proofs
	// Score = (ValidProofCount + prior_valid_proofs) / (ValidProofCount + InvalidProofCount + prior_valid_proofs + prior_invalid_proofs)

	ValidProofCount   int // Number of valid proofs submitted
	InvalidProofCount int // Number of invalid proofs submitted

	// OperationAcceptanceRate
	//if OperationAcceptanceRate < 0.6, then the extension is considered unreliable and socket connection is closed
	OperationAcceptanceCount int // Number of Operations accepted by the extension
	OperationRejectionCount  int // Number of Operations rejected by the extension

	// latency is relative to the specific ExtensionID node decides this on local registration,
	// if latency > OperationExecutionLatency, then the extension is considered unreliable and therefore throttled.
	OperationExecutionLatency int // Time taken to process an Operation into PostOp

	Staked          bool
	StakeBalance    uint64 // Amount of stake held by the node or extension
	NegativeSlashes int    // Number of times the node or extension was penalized for malicious behavior

	LastActiveTimestamp time.Time // Last time the node or extension was active

	Blacklisted      bool
	BlacklistedUntil time.Time // If blacklisted, the time until which it is blacklisted

    }
    
#### Middle-Node Reputation
    type MiddleNodeReputation struct {
 	ValidProofCount   int // Number of valid proofs submitted to p2p mempool my the peer
	InvalidProofCount int // Number of invalid proofs submitted to p2p mempool my the peer

	// OperationAcceptanceRate
	//if OperationAcceptanceRate < 0.6, then the peer is considered unreliable and socket connection is closed
	OperationAcceptanceCount int // Number of Operations accepted by the peer
	OperationRejectionCount  int // Number of Operations rejected by the peer

	ProofVerificationLatency time.Duration // Time taken to verify a proof //middle node only
	AvailabilityScore        float64       // % uptime responding to requests // middle node only // > 0.8 okay, < 0.8 throttled, < 0.5 banned

	// DisputeOutcomeScore > 0.8 okay // DisputeOutcomeScore < 0.8 throttled , // DisputeOutcomeScore < 0.5 banned
	DisputeOutcomeScore float64 // % of times a node was challenged and proved correct vs incorrect

	staked          bool
	StakeBalance    uint64 // Amount of stake held by the node or extension
	NegativeSlashes int    // Number of times the node or extension was penalized for malicious behavior

	PeerEndorsements []string // List of peer endorsements or challenges

	LastActiveTimestamp time.Time // Last time the node or extension was active

	Blacklisted      bool
	BlacklistedUntil time.Time // If blacklisted, the time until which it is blacklisted
    }
### ReputationScore formula + Design on-chain dispute resolution -> TBD 


## Final Bridge to L1; Consensus over Submission
  who gets to submit the final tx to the mainnet mempool?
  in each slot(12s) there would be only one submitter and only that one is eligible for compensation, (leader selection)
  The leader submits the PostOp (or a batch of them) directly to the Consensus Contract. The contract then verifies the on-chain portion of the proof (if any) and uses the PostOp.Data to perform calls to other contracts. 
	
 ### the leader selection mechanism
  TBD

 ### fee and payment flow
 
  
## Specifications: 
  ### P2P stack: 
  we will utilize the ethereum execution client p2p stack, devp2p and Kademlia tables to manage our decentralized network of middle nodes.
  RLPx, DiscV5 and ENR are completely utilized.
   node MUST broadcast a Capability Advertisement Packet upon peer connection so they can advertise SupportedExtensions, SupportedProofTypes , MaxProofSize , FeeSchedule

# Roadmap 
## Phase 0 – Concept Finalization (Design & Research)
Goal: Define the full architecture, state model, and security assumptions.

#### Tasks:
* Finalize architecture: Middle Nodes, Extensions, staking/slashing mechanism, dual mempool behavior
* Decide state management:
(a) Temporary state in Middle Layer only

(b) Commit via blobs

(c) Long-term vision with direct settlement on execution layer

* Extension registry model: how they’re registered, discovered, and upgraded

* Finalize proof format: zk-WASM → proof schema → on-chain verifier

* Define Operation & PostOp transaction structure

* Design P2P network behavior for Middle Layer

* Write full specs (could be a proto-EIP or whitepaper)

 *** Deliverable: 
 Middle Layer Spec v1 + Updated diagrams

## Phase 1 – Prototype & Local Testnet
Goal: Minimal Middle Client and Extension execution working locally

#### Tasks:
* Build a lightweight Middle Client (Go)

* Implement basic Operation processing (no zk yet, just execute Extension logic)

* Simple Extension runtime (e.g., WASM runtime, single Extension)

* Basic registry contract (stores Extension IDs)

* Mock PostOp generation and verification flow

* Start with centralized sequencer for test simplicity

  *** Deliverable:

Middle Client MVP

One working Extension (e.g., ERC-4337 Bundler)


## Phase 2 – zk-WASM Integration & Proof-Based Execution
Goal: Replace trusted execution with zk-proofs

#### Tasks:
*  Integrate a zk-WASM runtime (zkWASM)

*  Generate proof for Extension execution

*  Deploy Consensus contract on Ethereum to validate PostOps

* Add staking + slashing logic (Consensus Contract)

* Start building gossip protocol for Middle Layer P2P

**** Deliverable:

zk-enabled Middle Client

PostOp verified on L1


## Phase 3 – Decentralized Middle Layer Network
Goal: Multiple nodes, decentralized Operations & PostOps, incentivization

#### Tasks:
* Implement dual mempool (Operation Pool + PostOp Pool)

* Fully decentralized gossip network for Middle Clients

* Robust staking, reward distribution, and slashing

* Support multiple Extensions running in parallel

* Optional blob-based data availability

**** Deliverable:

Public Middle Layer Testnet

At least 3–4 Extensions running

Metrics: latency, throughput, verification costs

## Phase 4 – L2 as Extension & Composability
Goal: Prove Middle Layer can unify fragmented scaling solutions

#### Tasks:
* Wrap an existing zkRollup or bridge logic as an Extension

* Demonstrate cross-L2 interoperability

* Compose Extensions (one Extension calling another)

* Document modular deployment process for developers

**** Deliverable:

Demo: L2 interaction via Middle Client


## Phase 5 – Direct Settlement on L1 (No Registry/Consensus Contracts)
Goal: Native transaction type on Ethereum Execution Layer

 Approach:
* Define a new transaction type with embedded middlenode proof data(MiddleOpTx)

* Consensus layer changes not needed if verifier logic is handled in Execution layer

*  Modify Ethereum execution client to:

Parse MiddleOpTx

Verify proof directly

Apply resulting state changes natively

* Remove external registry and staking contracts (nodes rely on protocol-native staking)

* This effectively merges Middle Layer into Ethereum’s protocol → L1.5 becomes part of L1


NOTICE : 
reducing txn congestion on base layer in not the direct intent of this design but it can be utilized to also act as an L2 rollup 

TAGS: 
Layer 1.5





