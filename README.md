# Technical Breakdown: Zora Coins + Uniswap V4 Integration

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

