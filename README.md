# Technical Breakdown: Zora Coins + Uniswap V4 Integration


# Table of Contents: Zora Coins + Uniswap V4 Integration

 [1. Zora Coin Factory Deployment Pattern](#1-zora-coin-factory-deployment-pattern)
- **[Core Factory Call](#core-factory-call)**
- **[Pool Configuration Structure](#pool-configuration-structure)**

## [2. Uniswap V4 Pool Initialization](#2-uniswap-v4-pool-initialization)
- **[PoolKey Construction](#poolkey-construction)**
- **[Pool Initialization Call](#pool-initialization-call)**

## [3. Position Management & Liquidity](#3-position-management--liquidity)
- **[Automated Position Creation](#automated-position-creation)**
- **[Position Subscriber Interface](#position-subscriber-interface)**


## [4. Revenue Distribution Mechanism](#4-revenue-distribution-mechanism)
- **[Core Distribution Logic](#core-distribution-logic)**
- **[Fee Accrual Handling](#fee-accrual-handling)**

## [5. Advanced V4 Features Implementation](#5-advanced-v4-features-implementation)
- **[Custom Hook Integration](#custom-hook-integration)**
- **[Singleton Pool Manager Pattern](#singleton-pool-manager-pattern)**
- **[Protocol Fee Collection](#protocol-fee-collection)**

## [6. Reputation & Ranking System](#6-reputation--ranking-system)
- **[Reputation Metrics Structure](#reputation-metrics-structure)**
- **[Algorithmic Ranking Calculation](#algorithmic-ranking-calculation)**

## [7. Zero-Knowledge Proof Integration](#7-zero-knowledge-proof-integration)
- **[Inspiration Claim Structure](#inspiration-claim-structure)**
- **[zk-Proof Verification](#zk-proof-verification)**

## [8. Inspiration Graph & Network Effects](#8-inspiration-graph--network-effects)
- **[Graph Structure Implementation](#graph-structure-implementation)**
- **[Network Value Distribution](#network-value-distribution)**


## 1. Zora Coin Factory Deployment Pattern

### Core Factory Call
```solidity
(coinAddress, ) = zoraFactory.deploy{value: msg.value}(
    msg.sender,      // payoutRecipient - receives protocol fees
    owners,          // owners - array of addresses with coin control
    uri,            // metadata URI - IPFS/Arweave content reference
    name,           // coin name - human readable identifier
    symbol,         // coin symbol - ticker (e.g., "ZORA")
    abi.encode(poolConfig), // V4 pool configuration encoded as bytes
    platformReferrer,       // referrer for fee attribution
    address(this),  // postDeployHook - callback contract address
    abi.encode(contentId), // hook data - content identifier for routing
    salt           // CREATE2 salt for deterministic addresses
);
```

**Technical Analysis:**
- Uses CREATE2 deployment for predictable contract addresses
- `msg.value` forwarded for initial liquidity/bonding curve
- `abi.encode(poolConfig)` serializes V4 pool parameters into bytecode
- Hook pattern enables post-deployment initialization callbacks
- Salt ensures unique addresses per content piece

### Pool Configuration Structure
```solidity
struct PoolConfig {
    address pairedToken;        // Base token (WETH/USDC)
    uint24 fee;                // Pool fee tier (500/3000/10000)
    int24 tickSpacing;         // Price granularity
    uint160 initialSqrtPriceX96; // Starting price in Q64.96 format
}
```

---

## 2. Uniswap V4 Pool Initialization

### PoolKey Construction
```solidity
PoolKey memory poolKey = PoolKey({
    currency0: Currency.wrap(coinAddress < poolConfig.pairedToken ? coinAddress : poolConfig.pairedToken),
    currency1: Currency.wrap(coinAddress < poolConfig.pairedToken ? poolConfig.pairedToken : coinAddress),
    fee: poolConfig.fee,
    tickSpacing: poolConfig.tickSpacing,
    hooks: IHooks(proofOfInspirationHook)
});
```

**Technical Details:**
- **Currency Ordering**: Tokens sorted by address (currency0 < currency1) for deterministic pool identification
- **Currency.wrap()**: V4's type-safe currency wrapper preventing address confusion
- **Hook Integration**: Custom hook contract address embedded in PoolKey for automatic execution
- **Fee Tiers**: Standard Uniswap fee tiers (0.05%, 0.3%, 1%)
- **Tick Spacing**: Determines price precision (60 for 0.3% pools, 200 for 1% pools)

### Pool Initialization Call
```solidity
uniswapV4PoolManager.initialize(
    poolKey,
    poolConfig.initialSqrtPriceX96,
    abi.encode(contentId) // Hook initialization data
);
```

**Price Format Explanation:**
- `sqrtPriceX96`: Price stored as sqrt(price) × 2^96
- Q64.96 fixed-point format: 64 bits integer, 96 bits fractional
- Prevents overflow in price calculations during swaps

---

## 3. Position Management & Liquidity

### Automated Position Creation
```solidity
struct MintParams {
    PoolKey poolKey;
    int24 tickLower;        // Lower price bound
    int24 tickUpper;        // Upper price bound  
    uint256 liquidity;      // Liquidity amount
    uint128 amount0Max;     // Maximum token0 to spend
    uint128 amount1Max;     // Maximum token1 to spend
    address recipient;      // Position NFT recipient
    uint256 deadline;       // Transaction deadline
    bytes hookData;         // Custom hook data
}

(positionTokenId, , , ) = positionManager.mint(mintParams);
positionManager.subscribe(positionTokenId, address(this));
```

**Technical Implementation:**
- **Tick Boundaries**: Define price range for concentrated liquidity
- **Liquidity Calculation**: `L = sqrt(x * y)` where x,y are token amounts
- **Position NFT**: ERC-721 token representing liquidity position
- **Subscriber Pattern**: Contract receives notifications on position changes

### Position Subscriber Interface
```solidity
interface IPositionSubscriber {
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityDelta,    // Change in liquidity
        BalanceDelta feesAccrued  // Fees earned
    ) external;
    
    function notifyTransfer(
        uint256 tokenId,
        address previousOwner,
        address newOwner
    ) external;
}
```

---

## 4. Revenue Distribution Mechanism

### Core Distribution Logic
```solidity
function distributeRevenue(bytes32 claimId, uint256 amount) external nonReentrant {
    InspirationClaim storage claim = inspirationClaims[claimId];
    
    // Base revenue calculation
    uint256 originalShare = (amount * claim.revenueShareBps) / 10000;
    uint256 platformFee = (amount * platformFeeBps) / 10000;
    
    // zk-proof verification bonus
    if (claim.zkVerified) {
        uint256 bonus = (originalShare * 200) / 10000; // 2% bonus
        originalShare += bonus;
    }
    
    // Transfer to original creator
    pendingRevenue[claim.original] += originalShare;
    platformRevenue[msg.sender] += platformFee;
}
```

**Technical Components:**
- **Basis Points**: 10000 BPS = 100%, enables precise percentage calculations
- **Reentrancy Protection**: Prevents recursive calls during transfers
- **Bonus Mechanism**: Additional rewards for verified content relationships
- **Pending Revenue**: Accumulates payments before batch withdrawals

### Fee Accrual Handling
```solidity
function notifyModifyLiquidity(
    uint256 tokenId,
    int256 liquidityDelta,
    BalanceDelta feesAccrued
) external override {
    if (BalanceDelta.unwrap(feesAccrued) != 0) {
        _distributeLiquidityFees(contentId, feesAccrued);
    }
}

function _distributeLiquidityFees(bytes32 contentId, BalanceDelta feesAccrued) internal {
    uint256 feeAmount = uint256(uint128(BalanceDelta.unwrap(feesAccrued)));
    
    // Find inspiration claim for this content
    InspirationClaim storage claim = contentToClaim[contentId];
    
    if (claim.original != bytes32(0)) {
        uint256 shareAmount = (feeAmount * claim.revenueShareBps) / 10000;
        pendingRevenue[claim.original] += shareAmount;
    }
}
```

---

## 5. Advanced V4 Features Implementation

### Custom Hook Integration
```solidity
contract ProofOfInspirationHook is BaseHook {
    // Hook flags define which callback functions are implemented
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeModifyPosition: true,
            afterModifyPosition: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false
        });
    }
    
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Custom logic after each swap
        bytes32 contentId = abi.decode(hookData, (bytes32));
        _processSwapForContent(contentId, delta);
        return BaseHook.afterSwap.selector;
    }
}
```

### Singleton Pool Manager Pattern
```solidity
contract ZoraV4Integration {
    IUniswapV4PoolManager public immutable uniswapV4PoolManager;
    
    constructor(address _poolManager) {
        uniswapV4PoolManager = IUniswapV4PoolManager(_poolManager);
    }
    
    function createPool(PoolKey memory key, uint160 sqrtPriceX96) external {
        // All pools managed by single contract instance
        uniswapV4PoolManager.initialize(key, sqrtPriceX96, "");
    }
}
```

### Protocol Fee Collection
```solidity
function collectProtocolFees(PoolKey memory key) external returns (uint256, uint256) {
    // V4's improved fee collection mechanism
    uint256 amount0 = poolManager.collectProtocolFees(
        address(this), 
        key.currency0, 
        0  // Collect all available fees
    );
    uint256 amount1 = poolManager.collectProtocolFees(
        address(this), 
        key.currency1, 
        0
    );
    
    return (amount0, amount1);
}
```

---

## 6. Reputation & Ranking System

### Reputation Metrics Structure
```solidity
struct ReputationMetrics {
    uint256 collaboratorScore;      // Weighted collaboration quality
    uint256 totalInspirations;      // Number of derivative works
    uint256 successfulCollaborations; // Completed partnerships
    uint256 zkProofCount;          // Verified inspiration claims
    uint256 liquidityProvided;     // Total LP contributions
    uint256 tradingVolume;         // Generated trading activity
}

mapping(address => ReputationMetrics) public creatorReputation;
```

### Algorithmic Ranking Calculation
```solidity
function calculateRankingScore(bytes32 contentId) external view returns (uint256) {
    Content storage content = contents[contentId];
    ReputationMetrics storage reputation = creatorReputation[content.creator];
    
    // Base score from content metrics
    uint256 baseScore = content.totalLiquidity + content.tradingVolume;
    
    // Reputation multiplier (100% + reputation score as percentage)
    uint256 reputationMultiplier = 1000 + (reputation.collaboratorScore * 1000) / 1000;
    
    // Network effect bonus
    uint256 networkBonus = _calculateNetworkEffects(contentId);
    
    // zk-proof verification bonus
    uint256 zkBonus = reputation.zkProofCount * 5000; // 5k points per proof
    
    return (baseScore * reputationMultiplier / 1000) + networkBonus + zkBonus;
}

function _calculateNetworkEffects(bytes32 contentId) internal view returns (uint256) {
    bytes32[] storage inspirations = inspirationGraph[contentId];
    uint256 networkScore = 0;
    
    // Recursive scoring through inspiration chain
    for (uint i = 0; i < inspirations.length; i++) {
        networkScore += contents[inspirations[i]].tradingVolume / 10; // 10% of derivative volume
        networkScore += _calculateNetworkEffects(inspirations[i]) / 2; // Diminishing returns
    }
    
    return networkScore;
}
```

---

## 7. Zero-Knowledge Proof Integration

### Inspiration Claim Structure
```solidity
struct InspirationClaim {
    bytes32 derivative;       // Hash of derivative content
    bytes32 original;        // Hash of original content
    address claimant;        // Address making the claim
    uint256 revenueShareBps; // Revenue share percentage
    bool zkVerified;         // zk-proof verification status
    bytes32 proofHash;       // zk-SNARK proof hash
    uint256 timestamp;       // Claim timestamp
}

mapping(bytes32 => InspirationClaim) public inspirationClaims;
```

### zk-Proof Verification
```solidity
function verifyInspirationProof(
    bytes32 claimId,
    bytes calldata proof,
    uint256[] calldata publicInputs
) external {
    require(inspirationClaims[claimId].claimant == msg.sender, "Not claimant");
    
    // Verify zk-SNARK proof
    bool isValid = zkVerifier.verifyProof(proof, publicInputs);
    require(isValid, "Invalid proof");
    
    // Update claim status
    inspirationClaims[claimId].zkVerified = true;
    inspirationClaims[claimId].proofHash = keccak256(proof);
    
    // Update creator reputation
    creatorReputation[msg.sender].zkProofCount++;
    
    emit InspirationVerified(claimId, msg.sender);
}
```

---

## 8. Inspiration Graph & Network Effects

### Graph Structure Implementation
```solidity
mapping(bytes32 => bytes32[]) public inspirationGraph;    // content => inspired works
mapping(bytes32 => bytes32) public parentContent;         // content => parent content
mapping(bytes32 => uint256) public contentDepth;          // position in chain
mapping(bytes32 => uint256) public totalDerivatives;      // count of derivative works

function registerInspiration(
    bytes32 originalContentId,
    bytes32 derivativeContentId
) external {
    require(contents[originalContentId].creator != address(0), "Original not found");
    require(contents[derivativeContentId].creator == msg.sender, "Not derivative creator");
    
    // Update graph structure
    inspirationGraph[originalContentId].push(derivativeContentId);
    parentContent[derivativeContentId] = originalContentId;
    contentDepth[derivativeContentId] = contentDepth[originalContentId] + 1;
    totalDerivatives[originalContentId]++;
    
    // Propagate count up the chain
    bytes32 current = originalContentId;
    while (parentContent[current] != bytes32(0)) {
        current = parentContent[current];
        totalDerivatives[current]++;
    }
}
```

### Network Value Distribution
```solidity
function distributeNetworkValue(bytes32 contentId, uint256 value) internal {
    uint256 remaining = value;
    bytes32 current = contentId;
    uint256 depth = 0;
    
    // Distribute value up the inspiration chain
    while (current != bytes32(0) && depth < MAX_DEPTH) {
        uint256 sharePercentage = 100 - (depth * 20); // Diminishing: 100%, 80%, 60%, 40%, 20%
        if (sharePercentage > 0) {
            uint256 share = (remaining * sharePercentage) / 100;
            pendingRevenue[current] += share;
            remaining -= share;
        }
        
        current = parentContent[current];
        depth++;
    }
}
```


# Proof of Inspiration Protocol

A decentralized protocol for content provenance tracking and automated revenue distribution built on Uniswap V4 hooks architecture and Zora Protocol infrastructure.

## Technical Architecture

### Core Protocol Stack

```
┌─────────────────────────────────────────────────────────────┐
│                 Proof of Inspiration                       │
├─────────────────────────────────────────────────────────────┤
│  Content Graph   │  Revenue Engine  │  Reputation System   │
├─────────────────────────────────────────────────────────────┤
│          Uniswap V4 Hooks        │    Zora Protocol        │
├─────────────────────────────────────────────────────────────┤
│     Position Manager    │ Pool Manager │  Factory Contract  │
├─────────────────────────────────────────────────────────────┤
│                        Ethereum L2                         │
└─────────────────────────────────────────────────────────────┘
```

### Smart Contract Components

#### ProofOfInspiration.sol
Primary protocol contract implementing:
- Content registration and tokenization
- Inspiration claim validation
- Revenue distribution automation
- Reputation scoring algorithms

#### Integration Contracts
- **IZoraFactory**: ERC-20 token deployment interface
- **IUniswapV4PoolManager**: Pool creation and management
- **IPositionManager**: LP position handling with subscription hooks
- **IZkVerifier**: Zero-knowledge proof verification for inspiration claims

## Uniswap V4 Integration

### Hook-Based Revenue Distribution

```solidity
contract ProofOfInspiration is IPositionSubscriber {
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityDelta,
        BalanceDelta feeDelta
    ) external override {
        bytes32 contentId = positionToContentId[tokenId];
        if (contentId != bytes32(0) && feeDelta.amount0() > 0) {
            _distributeFeesToInspirationNetwork(contentId, feeDelta);
        }
    }
}
```

**Technical Flow:**
1. LP positions subscribe to fee notifications via `IPositionSubscriber`
2. When fees are collected, `notifyModifyLiquidity` triggers automatically  
3. Fee distribution cascades through inspiration graph using BFS traversal
4. Revenue shares calculated based on configurable basis points (max 5000 BPS = 50%)

### Pool Architecture

Each content piece deploys:
```solidity
struct V4PoolConfig {
    address pairedToken;      // WETH, USDC, or custom base token
    uint24 fee;              // Pool fee tier (500, 3000, 10000 BPS)
    int24 tickSpacing;       // Tick spacing for concentrated liquidity
    uint160 initialSqrtPriceX96; // Initial price in Q64.96 format
}
```

**Pool Initialization:**
```solidity
PoolKey memory poolKey = PoolKey({
    currency0: Currency.wrap(token0),
    currency1: Currency.wrap(token1), 
    fee: poolConfig.fee,
    tickSpacing: poolConfig.tickSpacing,
    hooks: IHooks(hookAddress)
});

PoolId poolId = poolManager.initialize(
    poolKey,
    poolConfig.initialSqrtPriceX96,
    hookData
);
```

### Position Management

```solidity
function _createLiquidityPosition(
    address coinAddress,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams
) internal returns (uint256 positionTokenId) {
    // Mint LP position
    (positionTokenId,,,) = positionManager.mint(mintParams);
    
    // Subscribe to fee notifications
    positionManager.subscribe(positionTokenId, address(this));
    
    return positionTokenId;
}
```

## Zora Protocol Integration

### Token Deployment Pipeline

```solidity
function _deployContentToken(
    string memory name,
    string memory symbol,
    string memory uri,
    address[] memory owners,
    bytes memory poolConfig,
    address platformReferrer,
    bytes32 salt
) internal returns (address coinAddress, uint256 tokenId) {
    (coinAddress, tokenId) = zoraFactory.deploy{value: msg.value}(
        msg.sender,          // payout recipient
        owners,              // token owners array
        uri,                 // metadata URI
        name,                // token name
        symbol,              // token symbol  
        poolConfig,          // encoded pool configuration
        platformReferrer,    // referrer for fees
        address(0),          // post-deploy hook
        "",                  // hook data
        salt                 // deterministic deployment salt
    );
}
```

### Metadata Standards

Content metadata follows Zora's URI specification:
```json
{
  "name": "Content Title",
  "description": "Content description", 
  "image": "ipfs://QmHash/image.jpg",
  "content_hash": "QmContentHash123",
  "creator": "0x...",
  "creation_timestamp": 1234567890,
  "inspiration_claims": [
    {
      "original_content_id": "0x...",
      "proof_type": "ZK_SIMILARITY_PROOF",
      "revenue_share_bps": 1000
    }
  ]
}
```

## Revenue Distribution Engine

### Multi-Layer Distribution

```solidity
function _distributeRevenue(bytes32 claimId, uint256 amount) internal {
    InspirationClaim memory claim = inspirationClaims[claimId];
    
    // Calculate platform fee
    uint256 platformFee = (amount * platformFeeBps) / 10000;
    uint256 remainingAmount = amount - platformFee;
    
    // Calculate inspiration share
    uint256 inspirationShare = (remainingAmount * claim.revenueShareBps) / 10000;
    uint256 derivativeShare = remainingAmount - inspirationShare;
    
    // Distribute to inspiration network
    _cascadeRevenue(claim.originalContentId, inspirationShare);
    
    // Track metrics
    totalRevenueGenerated[claim.originalContentId] += inspirationShare;
    
    emit RevenueDistributed(
        claim.original,
        getContentCreator(claim.originalContentId),
        inspirationShare,
        claim.originalContentId
    );
}
```

### Inspiration Graph Traversal

```solidity
function _cascadeRevenue(bytes32 contentId, uint256 amount) internal {
    ContentPiece memory content = contentPieces[contentId];
    address creator = content.creator;
    
    // Direct revenue to original creator
    pendingRevenue[content.coinAddress][creator] += amount;
    
    // Propagate to parent inspirations (recursive)
    bytes32[] memory parentInspirations = getParentInspirations(contentId);
    if (parentInspirations.length > 0) {
        uint256 parentShare = amount / 10; // 10% to parent level
        for (uint i = 0; i < parentInspirations.length; i++) {
            _cascadeRevenue(parentInspirations[i], parentShare / parentInspirations.length);
        }
    }
}
```

## Content Creation Flow

### Primary Content Creation

```solidity
function createContent(
    string memory name,
    string memory symbol,
    string memory uri,
    string memory contentHash,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams,
    address platformReferrer,
    bytes32 salt
) external payable returns (bytes32 contentId, address coinAddress, uint256 positionTokenId) {
    // Generate unique content ID
    contentId = keccak256(abi.encodePacked(
        msg.sender,
        contentHash,
        block.timestamp,
        salt
    ));
    
    // Deploy ERC-20 token via Zora
    address[] memory owners = new address[](1);
    owners[0] = msg.sender;
    
    (coinAddress,) = _deployContentToken(
        name,
        symbol,
        uri,
        owners,
        abi.encode(poolConfig),
        platformReferrer,
        salt
    );
    
    // Create Uniswap V4 pool and liquidity position
    _initializeV4Pool(coinAddress, poolConfig);
    positionTokenId = _createLiquidityPosition(coinAddress, poolConfig, mintParams);
    
    // Store content metadata
    contentPieces[contentId] = ContentPiece({
        creator: msg.sender,
        coinAddress: coinAddress,
        contentHash: contentHash,
        timestamp: block.timestamp,
        exists: true,
        totalDerivatives: 0,
        reputationScore: 0,
        inspirationClaims: new bytes32[](0),
        positionTokenId: positionTokenId
    });
    
    // Map position to content
    positionToContentId[positionTokenId] = contentId;
    
    emit ContentCreated(contentId, msg.sender, coinAddress, contentHash, block.timestamp, positionTokenId);
}
```

### Derivative Content Creation

```solidity
function createDerivativeWithInspiration(
    bytes32 originalContentId,
    string memory name,
    string memory symbol,
    string memory uri,
    string memory contentHash,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams,
    address platformReferrer,
    bytes32 salt,
    uint256 revenueShareBps,
    bytes32 zkProofHash,
    InspirationProofType proofType
) external payable returns (bytes32 derivativeContentId, address coinAddress, uint256 positionTokenId) {
    require(contentPieces[originalContentId].exists, "Original content does not exist");
    require(revenueShareBps <= MAX_REVENUE_SHARE_BPS, "Revenue share too high");
    
    // Create derivative content
    (derivativeContentId, coinAddress, positionTokenId) = createContent(
        name, symbol, uri, contentHash, poolConfig, mintParams, platformReferrer, salt
    );
    
    // Create inspiration claim
    bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));
    
    inspirationClaims[claimId] = InspirationClaim({
        derivative: coinAddress,
        original: contentPieces[originalContentId].coinAddress,
        revenueShareBps: revenueShareBps,
        zkProofHash: zkProofHash,
        zkVerified: _verifyZkProof(zkProofHash, proofType),
        disputed: false,
        timestamp: block.timestamp,
        proofType: proofType
    });
    
    // Update graph structures
    contentDerivatives[originalContentId].push(derivativeContentId);
    contentInspirations[derivativeContentId].push(originalContentId);
    contentPieces[originalContentId].totalDerivatives++;
    
    emit InspirationClaimed(claimId, originalContentId, derivativeContentId, msg.sender, revenueShareBps, proofType);
}
```

## Zero-Knowledge Proof Integration

### Proof Types

```solidity
enum InspirationProofType {
    DECLARED_ONLY,           // Creator declaration only
    COMMUNITY_VERIFIED,      // Community consensus
    ZK_SIMILARITY_PROOF,     // Cryptographic content similarity
    ZK_PROVENANCE_PROOF,     // Cryptographic provenance chain
    CROSS_PLATFORM_VERIFIED  // External platform verification
}
```

### ZK Verification Implementation

```solidity
function _verifyZkProof(
    bytes32 zkProofHash,
    InspirationProofType proofType
) internal view returns (bool) {
    if (proofType == InspirationProofType.ZK_SIMILARITY_PROOF ||
        proofType == InspirationProofType.ZK_PROVENANCE_PROOF) {
        return zkVerifier.verify(zkProofHash);
    }
    return true; // Non-ZK proof types automatically verified
}
```

## Data Structures

### Core Storage

```solidity
struct ContentPiece {
    address creator;
    address coinAddress;
    string contentHash;        // IPFS hash
    uint256 timestamp;
    bool exists;
    uint256 totalDerivatives;
    uint256 reputationScore;
    bytes32[] inspirationClaims;
    uint256 positionTokenId;   // Uniswap V4 position
}

struct InspirationClaim {
    address derivative;        // Derivative token address
    address original;         // Original token address  
    uint256 revenueShareBps;  // Revenue share (0-5000 BPS)
    bytes32 zkProofHash;      // ZK proof identifier
    bool zkVerified;          // Verification status
    bool disputed;            // Dispute flag
    uint256 timestamp;
    InspirationProofType proofType;
}
```

### State Mappings

```solidity
mapping(bytes32 => ContentPiece) public contentPieces;
mapping(bytes32 => InspirationClaim) public inspirationClaims;
mapping(bytes32 => bytes32[]) public contentDerivatives;
mapping(bytes32 => bytes32[]) public contentInspirations;
mapping(uint256 => bytes32) public positionToContentId;
mapping(address => mapping(address => uint256)) public pendingRevenue;
mapping(bytes32 => uint256) public totalRevenueGenerated;
```

## Reputation System

### Scoring Algorithm

```solidity
function calculateRankingScore(bytes32 contentId) public view returns (uint256) {
    ContentPiece memory content = contentPieces[contentId];
    
    uint256 baseScore = 1000;
    uint256 derivativeBonus = content.totalDerivatives * 100;
    uint256 revenueBonus = (totalRevenueGenerated[contentId] / 1e18) * 50;
    uint256 timeDecay = _calculateTimeDecay(content.timestamp);
    uint256 zkBonus = _calculateZkVerificationBonus(contentId);
    
    return (baseScore + derivativeBonus + revenueBonus + zkBonus) * timeDecay / 100;
}

function _calculateTimeDecay(uint256 timestamp) internal view returns (uint256) {
    uint256 age = block.timestamp - timestamp;
    uint256 daysSinceCreation = age / 86400; // seconds per day
    
    if (daysSinceCreation < 30) return 100;      // No decay first month
    if (daysSinceCreation < 90) return 95;       // 5% decay after 3 months
    if (daysSinceCreation < 180) return 90;      // 10% decay after 6 months
    return 85;                                   // 15% decay after 6 months
}
```

### Reputation Metrics

```solidity
struct ReputationMetrics {
    uint256 totalOriginalContent;
    uint256 totalDerivatives;
    uint256 totalInspirations;
    uint256 totalRevenue;
    uint256 collaboratorScore;
    uint256 fraudFlags;
    uint256 communityScore;
}

function getCreatorReputation(address creator) external view returns (ReputationMetrics memory) {
    return creatorReputation[creator];
}
```

## Administrative Functions

### Owner Controls

```solidity
function setZkVerifier(address _zkVerifier) external onlyOwner {
    zkVerifier = IZkVerifier(_zkVerifier);
}

function setPlatformFee(uint256 _platformFeeBps) external onlyOwner {
    require(_platformFeeBps <= 1000, "Platform fee too high"); // Max 10%
    platformFeeBps = _platformFeeBps;
}
```

### Dispute Mechanism

```solidity
function disputeInspiration(bytes32 claimId, string memory reason) external {
    InspirationClaim storage claim = inspirationClaims[claimId];
    require(claim.timestamp > 0, "Claim does not exist");
    
    // Mark as disputed
    claim.disputed = true;
    
    // Apply reputation penalty
    address derivativeCreator = getTokenCreator(claim.derivative);
    creatorReputation[derivativeCreator].fraudFlags++;
    
    emit InspirationDisputed(claimId, msg.sender, reason);
}
```

## Revenue Claiming

### Manual Revenue Withdrawal

```solidity
function claimRevenue(address tokenAddress) external {
    uint256 pending = pendingRevenue[tokenAddress][msg.sender];
    require(pending > 0, "No pending revenue");
    
    pendingRevenue[tokenAddress][msg.sender] = 0;
    
    IERC20(tokenAddress).transfer(msg.sender, pending);
    
    emit RevenueClaimed(msg.sender, tokenAddress, pending);
}
```

### Batch Revenue Claims

```solidity
function claimMultipleRevenues(address[] calldata tokenAddresses) external {
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
        uint256 pending = pendingRevenue[tokenAddresses[i]][msg.sender];
        if (pending > 0) {
            pendingRevenue[tokenAddresses[i]][msg.sender] = 0;
            IERC20(tokenAddresses[i]).transfer(msg.sender, pending);
            emit RevenueClaimed(msg.sender, tokenAddresses[i], pending);
        }
    }
}
```

## Query Functions

### Content Discovery

```solidity
function getInspirationGraph(bytes32 contentId) external view returns (
    bytes32[] memory derivatives,
    uint256 depth,
    uint256 totalRevenue
) {
    derivatives = contentDerivatives[contentId];
    depth = _calculateContentDepth(contentId);
    totalRevenue = totalRevenueGenerated[contentId];
}

function getV4PoolInfo(bytes32 contentId) external view returns (
    PoolKey memory poolKey,
    uint256 positionTokenId,
    uint160 sqrtPriceX96,
    int24 tick
) {
    ContentPiece memory content = contentPieces[contentId];
    positionTokenId = content.positionTokenId;
    
    // Construct pool key
    poolKey = _getPoolKey(content.coinAddress);
    
    // Get current pool state
    PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
    (sqrtPriceX96, tick,,) = poolManager.getSlot0(poolId);
}
```

## Testing Framework

### Mock Contract Implementation

```solidity
contract MockZoraFactory {
    uint256 public constant DEPLOYMENT_COST = 0.01 ether;
    
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes memory hookData,
        bytes32 salt
    ) external payable returns (address coinAddress, uint256 tokenId) {
        require(msg.value >= DEPLOYMENT_COST, "Insufficient deployment fee");
        
        MockERC20 token = new MockERC20(name, symbol);
        coinAddress = address(token);
        tokenId = 1;
        
        token.mint(owners[0], 1000000 * 10**18);
        return (coinAddress, tokenId);
    }
}
```

### Test Coverage

The test suite includes:
- Content creation and tokenization
- Inspiration claim validation
- Revenue distribution automation
- Dispute mechanism testing
- Reputation scoring verification
- Administrative function testing
- Edge case handling# Proof of Inspiration Protocol

A decentralized protocol for content provenance tracking and automated revenue distribution built on Uniswap V4 hooks architecture and Zora Protocol infrastructure.

# Technical Architecture

# Core Protocol Stack

```
┌─────────────────────────────────────────────────────────────┐
│                 Proof of Inspiration                       │
├─────────────────────────────────────────────────────────────┤
│  Content Graph   │  Revenue Engine  │  Reputation System   │
├─────────────────────────────────────────────────────────────┤
│          Uniswap V4 Hooks        │    Zora Protocol        │
├─────────────────────────────────────────────────────────────┤
│     Position Manager    │ Pool Manager │  Factory Contract  │
├─────────────────────────────────────────────────────────────┤
│                        Ethereum L2                         │
└─────────────────────────────────────────────────────────────┘
```

# Smart Contract Components

## ProofOfInspiration.sol
Primary protocol contract implementing:
- Content registration and tokenization
- Inspiration claim validation
- Revenue distribution automation
- Reputation scoring algorithms

## Integration Contracts
- **IZoraFactory**: ERC-20 token deployment interface
- **IUniswapV4PoolManager**: Pool creation and management
- **IPositionManager**: LP position handling with subscription hooks
- **IZkVerifier**: Zero-knowledge proof verification for inspiration claims

# Uniswap V4 Integration

## Hook-Based Revenue Distribution

```solidity
contract ProofOfInspiration is IPositionSubscriber {
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityDelta,
        BalanceDelta feeDelta
    ) external override {
        bytes32 contentId = positionToContentId[tokenId];
        if (contentId != bytes32(0) && feeDelta.amount0() > 0) {
            _distributeFeesToInspirationNetwork(contentId, feeDelta);
        }
    }
}
```

**Technical Flow:**
1. LP positions subscribe to fee notifications via `IPositionSubscriber`
2. When fees are collected, `notifyModifyLiquidity` triggers automatically  
3. Fee distribution cascades through inspiration graph using BFS traversal
4. Revenue shares calculated based on configurable basis points (max 5000 BPS = 50%)

## Pool Architecture

Each content piece deploys:
```solidity
struct V4PoolConfig {
    address pairedToken;      // WETH, USDC, or custom base token
    uint24 fee;              // Pool fee tier (500, 3000, 10000 BPS)
    int24 tickSpacing;       // Tick spacing for concentrated liquidity
    uint160 initialSqrtPriceX96; // Initial price in Q64.96 format
}
```

**Pool Initialization:**
```solidity
PoolKey memory poolKey = PoolKey({
    currency0: Currency.wrap(token0),
    currency1: Currency.wrap(token1), 
    fee: poolConfig.fee,
    tickSpacing: poolConfig.tickSpacing,
    hooks: IHooks(hookAddress)
});

PoolId poolId = poolManager.initialize(
    poolKey,
    poolConfig.initialSqrtPriceX96,
    hookData
);
```

## Position Management

```solidity
function _createLiquidityPosition(
    address coinAddress,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams
) internal returns (uint256 positionTokenId) {
    // Mint LP position
    (positionTokenId,,,) = positionManager.mint(mintParams);
    
    // Subscribe to fee notifications
    positionManager.subscribe(positionTokenId, address(this));
    
    return positionTokenId;
}
```

# Zora Protocol Integration

## Token Deployment Pipeline

```solidity
function _deployContentToken(
    string memory name,
    string memory symbol,
    string memory uri,
    address[] memory owners,
    bytes memory poolConfig,
    address platformReferrer,
    bytes32 salt
) internal returns (address coinAddress, uint256 tokenId) {
    (coinAddress, tokenId) = zoraFactory.deploy{value: msg.value}(
        msg.sender,          // payout recipient
        owners,              // token owners array
        uri,                 // metadata URI
        name,                // token name
        symbol,              // token symbol  
        poolConfig,          // encoded pool configuration
        platformReferrer,    // referrer for fees
        address(0),          // post-deploy hook
        "",                  // hook data
        salt                 // deterministic deployment salt
    );
}
```

## Metadata Standards

Content metadata follows Zora's URI specification:
```json
{
  "name": "Content Title",
  "description": "Content description", 
  "image": "ipfs://QmHash/image.jpg",
  "content_hash": "QmContentHash123",
  "creator": "0x...",
  "creation_timestamp": 1234567890,
  "inspiration_claims": [
    {
      "original_content_id": "0x...",
      "proof_type": "ZK_SIMILARITY_PROOF",
      "revenue_share_bps": 1000
    }
  ]
}
```

# Revenue Distribution Engine

## Multi-Layer Distribution

```solidity
function _distributeRevenue(bytes32 claimId, uint256 amount) internal {
    InspirationClaim memory claim = inspirationClaims[claimId];
    
    // Calculate platform fee
    uint256 platformFee = (amount * platformFeeBps) / 10000;
    uint256 remainingAmount = amount - platformFee;
    
    // Calculate inspiration share
    uint256 inspirationShare = (remainingAmount * claim.revenueShareBps) / 10000;
    uint256 derivativeShare = remainingAmount - inspirationShare;
    
    // Distribute to inspiration network
    _cascadeRevenue(claim.originalContentId, inspirationShare);
    
    // Track metrics
    totalRevenueGenerated[claim.originalContentId] += inspirationShare;
    
    emit RevenueDistributed(
        claim.original,
        getContentCreator(claim.originalContentId),
        inspirationShare,
        claim.originalContentId
    );
}
```

## Inspiration Graph Traversal

```solidity
function _cascadeRevenue(bytes32 contentId, uint256 amount) internal {
    ContentPiece memory content = contentPieces[contentId];
    address creator = content.creator;
    
    // Direct revenue to original creator
    pendingRevenue[content.coinAddress][creator] += amount;
    
    // Propagate to parent inspirations (recursive)
    bytes32[] memory parentInspirations = getParentInspirations(contentId);
    if (parentInspirations.length > 0) {
        uint256 parentShare = amount / 10; // 10% to parent level
        for (uint i = 0; i < parentInspirations.length; i++) {
            _cascadeRevenue(parentInspirations[i], parentShare / parentInspirations.length);
        }
    }
}
```

# Content Creation Flow

## Primary Content Creation

```solidity
function createContent(
    string memory name,
    string memory symbol,
    string memory uri,
    string memory contentHash,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams,
    address platformReferrer,
    bytes32 salt
) external payable returns (bytes32 contentId, address coinAddress, uint256 positionTokenId) {
    // Generate unique content ID
    contentId = keccak256(abi.encodePacked(
        msg.sender,
        contentHash,
        block.timestamp,
        salt
    ));
    
    // Deploy ERC-20 token via Zora
    address[] memory owners = new address[](1);
    owners[0] = msg.sender;
    
    (coinAddress,) = _deployContentToken(
        name,
        symbol,
        uri,
        owners,
        abi.encode(poolConfig),
        platformReferrer,
        salt
    );
    
    // Create Uniswap V4 pool and liquidity position
    _initializeV4Pool(coinAddress, poolConfig);
    positionTokenId = _createLiquidityPosition(coinAddress, poolConfig, mintParams);
    
    // Store content metadata
    contentPieces[contentId] = ContentPiece({
        creator: msg.sender,
        coinAddress: coinAddress,
        contentHash: contentHash,
        timestamp: block.timestamp,
        exists: true,
        totalDerivatives: 0,
        reputationScore: 0,
        inspirationClaims: new bytes32[](0),
        positionTokenId: positionTokenId
    });
    
    // Map position to content
    positionToContentId[positionTokenId] = contentId;
    
    emit ContentCreated(contentId, msg.sender, coinAddress, contentHash, block.timestamp, positionTokenId);
}
```

## Derivative Content Creation

```solidity
function createDerivativeWithInspiration(
    bytes32 originalContentId,
    string memory name,
    string memory symbol,
    string memory uri,
    string memory contentHash,
    V4PoolConfig memory poolConfig,
    IPositionManager.MintParams memory mintParams,
    address platformReferrer,
    bytes32 salt,
    uint256 revenueShareBps,
    bytes32 zkProofHash,
    InspirationProofType proofType
) external payable returns (bytes32 derivativeContentId, address coinAddress, uint256 positionTokenId) {
    require(contentPieces[originalContentId].exists, "Original content does not exist");
    require(revenueShareBps <= MAX_REVENUE_SHARE_BPS, "Revenue share too high");
    
    // Create derivative content
    (derivativeContentId, coinAddress, positionTokenId) = createContent(
        name, symbol, uri, contentHash, poolConfig, mintParams, platformReferrer, salt
    );
    
    // Create inspiration claim
    bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));
    
    inspirationClaims[claimId] = InspirationClaim({
        derivative: coinAddress,
        original: contentPieces[originalContentId].coinAddress,
        revenueShareBps: revenueShareBps,
        zkProofHash: zkProofHash,
        zkVerified: _verifyZkProof(zkProofHash, proofType),
        disputed: false,
        timestamp: block.timestamp,
        proofType: proofType
    });
    
    // Update graph structures
    contentDerivatives[originalContentId].push(derivativeContentId);
    contentInspirations[derivativeContentId].push(originalContentId);
    contentPieces[originalContentId].totalDerivatives++;
    
    emit InspirationClaimed(claimId, originalContentId, derivativeContentId, msg.sender, revenueShareBps, proofType);
}
```

# Zero-Knowledge Proof Integration

## Proof Types

```solidity
enum InspirationProofType {
    DECLARED_ONLY,           // Creator declaration only
    COMMUNITY_VERIFIED,      // Community consensus
    ZK_SIMILARITY_PROOF,     // Cryptographic content similarity
    ZK_PROVENANCE_PROOF,     // Cryptographic provenance chain
    CROSS_PLATFORM_VERIFIED  // External platform verification
}
```

## ZK Verification Implementation

```solidity
function _verifyZkProof(
    bytes32 zkProofHash,
    InspirationProofType proofType
) internal view returns (bool) {
    if (proofType == InspirationProofType.ZK_SIMILARITY_PROOF ||
        proofType == InspirationProofType.ZK_PROVENANCE_PROOF) {
        return zkVerifier.verify(zkProofHash);
    }
    return true; // Non-ZK proof types automatically verified
}
```

# Data Structures

## Core Storage

```solidity
struct ContentPiece {
    address creator;
    address coinAddress;
    string contentHash;        // IPFS hash
    uint256 timestamp;
    bool exists;
    uint256 totalDerivatives;
    uint256 reputationScore;
    bytes32[] inspirationClaims;
    uint256 positionTokenId;   // Uniswap V4 position
}

struct InspirationClaim {
    address derivative;        // Derivative token address
    address original;         // Original token address  
    uint256 revenueShareBps;  // Revenue share (0-5000 BPS)
    bytes32 zkProofHash;      // ZK proof identifier
    bool zkVerified;          // Verification status
    bool disputed;            // Dispute flag
    uint256 timestamp;
    InspirationProofType proofType;
}
```

## State Mappings

```solidity
mapping(bytes32 => ContentPiece) public contentPieces;
mapping(bytes32 => InspirationClaim) public inspirationClaims;
mapping(bytes32 => bytes32[]) public contentDerivatives;
mapping(bytes32 => bytes32[]) public contentInspirations;
mapping(uint256 => bytes32) public positionToContentId;
mapping(address => mapping(address => uint256)) public pendingRevenue;
mapping(bytes32 => uint256) public totalRevenueGenerated;
```

# Reputation System

## Scoring Algorithm

```solidity
function calculateRankingScore(bytes32 contentId) public view returns (uint256) {
    ContentPiece memory content = contentPieces[contentId];
    
    uint256 baseScore = 1000;
    uint256 derivativeBonus = content.totalDerivatives * 100;
    uint256 revenueBonus = (totalRevenueGenerated[contentId] / 1e18) * 50;
    uint256 timeDecay = _calculateTimeDecay(content.timestamp);
    uint256 zkBonus = _calculateZkVerificationBonus(contentId);
    
    return (baseScore + derivativeBonus + revenueBonus + zkBonus) * timeDecay / 100;
}

function _calculateTimeDecay(uint256 timestamp) internal view returns (uint256) {
    uint256 age = block.timestamp - timestamp;
    uint256 daysSinceCreation = age / 86400; // seconds per day
    
    if (daysSinceCreation < 30) return 100;      // No decay first month
    if (daysSinceCreation < 90) return 95;       // 5% decay after 3 months
    if (daysSinceCreation < 180) return 90;      // 10% decay after 6 months
    return 85;                                   // 15% decay after 6 months
}
```

## Reputation Metrics

```solidity
struct ReputationMetrics {
    uint256 totalOriginalContent;
    uint256 totalDerivatives;
    uint256 totalInspirations;
    uint256 totalRevenue;
    uint256 collaboratorScore;
    uint256 fraudFlags;
    uint256 communityScore;
}

function getCreatorReputation(address creator) external view returns (ReputationMetrics memory) {
    return creatorReputation[creator];
}
```

# Administrative Functions

## Owner Controls

```solidity
function setZkVerifier(address _zkVerifier) external onlyOwner {
    zkVerifier = IZkVerifier(_zkVerifier);
}

function setPlatformFee(uint256 _platformFeeBps) external onlyOwner {
    require(_platformFeeBps <= 1000, "Platform fee too high"); // Max 10%
    platformFeeBps = _platformFeeBps;
}
```

## Dispute Mechanism

```solidity
function disputeInspiration(bytes32 claimId, string memory reason) external {
    InspirationClaim storage claim = inspirationClaims[claimId];
    require(claim.timestamp > 0, "Claim does not exist");
    
    // Mark as disputed
    claim.disputed = true;
    
    // Apply reputation penalty
    address derivativeCreator = getTokenCreator(claim.derivative);
    creatorReputation[derivativeCreator].fraudFlags++;
    
    emit InspirationDisputed(claimId, msg.sender, reason);
}
```

# Revenue Claiming

## Manual Revenue Withdrawal

```solidity
function claimRevenue(address tokenAddress) external {
    uint256 pending = pendingRevenue[tokenAddress][msg.sender];
    require(pending > 0, "No pending revenue");
    
    pendingRevenue[tokenAddress][msg.sender] = 0;
    
    IERC20(tokenAddress).transfer(msg.sender, pending);
    
    emit RevenueClaimed(msg.sender, tokenAddress, pending);
}
```

## Batch Revenue Claims

```solidity
function claimMultipleRevenues(address[] calldata tokenAddresses) external {
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
        uint256 pending = pendingRevenue[tokenAddresses[i]][msg.sender];
        if (pending > 0) {
            pendingRevenue[tokenAddresses[i]][msg.sender] = 0;
            IERC20(tokenAddresses[i]).transfer(msg.sender, pending);
            emit RevenueClaimed(msg.sender, tokenAddresses[i], pending);
        }
    }
}
```

# Query Functions

## Content Discovery

```solidity
function getInspirationGraph(bytes32 contentId) external view returns (
    bytes32[] memory derivatives,
    uint256 depth,
    uint256 totalRevenue
) {
    derivatives = contentDerivatives[contentId];
    depth = _calculateContentDepth(contentId);
    totalRevenue = totalRevenueGenerated[contentId];
}

function getV4PoolInfo(bytes32 contentId) external view returns (
    PoolKey memory poolKey,
    uint256 positionTokenId,
    uint160 sqrtPriceX96,
    int24 tick
) {
    ContentPiece memory content = contentPieces[contentId];
    positionTokenId = content.positionTokenId;
    
    // Construct pool key
    poolKey = _getPoolKey(content.coinAddress);
    
    // Get current pool state
    PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
    (sqrtPriceX96, tick,,) = poolManager.getSlot0(poolId);
}
```

# Testing Framework

## Mock Contract Implementation

```solidity
contract MockZoraFactory {
    uint256 public constant DEPLOYMENT_COST = 0.01 ether;
    
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes memory hookData,
        bytes32 salt
    ) external payable returns (address coinAddress, uint256 tokenId) {
        require(msg.value >= DEPLOYMENT_COST, "Insufficient deployment fee");
        
        MockERC20 token = new MockERC20(name, symbol);
        coinAddress = address(token);
        tokenId = 1;
        
        token.mint(owners[0], 1000000 * 10**18);
        return (coinAddress, tokenId);
    }
}
```

# Test Coverage

The test suite includes:
- Content creation and tokenization
- Inspiration claim validation
- Revenue distribution automation
- Dispute mechanism testing
- Reputation scoring verification
- Administrative function testing
- Edge case handling

---
