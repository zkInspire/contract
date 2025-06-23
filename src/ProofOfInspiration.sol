// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./interfaces/IZoraFactory.sol";
import "./interfaces/IUniswapV4PoolManager.sol";

import "./interfaces/IPositionManager.sol";
import "./interfaces/IPositionSubscriber.sol";
import {IProofOfInspirationHook} from "./interfaces/IProofOfInspirationHook.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/**
 * @title ProofOfInspiration
 * @dev Core contract managing inspiration relationships, zk-proofs, and revenue sharing
 * @notice Upgraded to work with Uniswap V4's singleton PoolManager architecture
 */
contract ProofOfInspiration is Ownable, ReentrancyGuard, IPositionSubscriber {
    
    // Structs
    struct ContentPiece {
        address creator;
        address coinAddress;
        string contentHash; // IPFS hash or content fingerprint
        uint256 timestamp;
        bool exists;
        uint256 totalDerivatives;
        uint256 reputationScore;
        PoolKey poolKey; // V4 pool key for this content's coin
        uint256 positionTokenId; // V4 position NFT ID
    }
  
struct V4PoolConfig {
    address pairedToken;        // Token to pair with (e.g., WETH)
    uint24 fee;                // Pool fee tier
    int24 tickSpacing;         // Tick spacing for the pool
    uint160 initialSqrtPriceX96; // Initial price
}

    
    struct InspirationClaim {
        address derivative;      // Derivative content coin address
        address original;       // Original content coin address
        uint256 revenueShareBps; // Basis points (100 = 1%)
        bytes32 zkProofHash;    // Hash of zk-proof (if provided)
        bool zkVerified;        // Whether zk-proof was successfully verified
        bool disputed;          // Whether the claim is under dispute
        uint256 timestamp;
        InspirationProofType proofType;
    }
    
    struct ReputationMetrics {
        uint256 collaboratorScore;
        uint256 totalInspirations;
        uint256 totalDerivatives;
        uint256 fraudFlags;
        uint256 successfulCollaborations;
    }
    
    enum InspirationProofType {
        DECLARED_ONLY,
        ZK_SIMILARITY_PROOF,
        CONTENT_FINGERPRINT,
        COMMUNITY_VERIFIED
    }
    
    // State Variables
    IZoraFactory public immutable zoraFactory;
    IUniswapV4PoolManager public immutable uniswapV4PoolManager;
    IPositionManager public immutable positionManager;
    address public immutable proofOfInspirationHook;
    
    mapping(bytes32 => ContentPiece) public contentPieces; // contentId => ContentPiece
    mapping(bytes32 => InspirationClaim) public inspirationClaims; // claimId => InspirationClaim
    mapping(address => ReputationMetrics) public creatorReputations;
    mapping(address => bytes32[]) public creatorContent; // creator => contentIds
    mapping(bytes32 => bytes32[]) public contentDerivatives; // contentId => derivative contentIds
    
    // Graph structure for inspiration chains
    mapping(bytes32 => bytes32[]) public inspirationGraph; // contentId => inspired contentIds
    mapping(bytes32 => uint256) public contentDepth; // How deep in inspiration chain
    
    // Revenue tracking
    mapping(address => mapping(address => uint256)) public pendingRevenue; // coin => creator => amount
    mapping(bytes32 => uint256) public totalRevenueGenerated; // contentId => total revenue
    
    // V4 specific mappings
    mapping(uint256 => bytes32) public positionToContentId; // position NFT ID => content ID
    mapping(address => PoolKey) public coinToPoolKey; // coin address => pool key
    
    // zk-Proof verification
    mapping(bytes32 => bool) public verifiedProofs;
    address public zkVerifier; // Address of zk-proof verifier contract
    
    // Platform settings
    uint256 public constant MAX_REVENUE_SHARE_BPS = 5000; // Max 50% revenue share
    uint256 public platformFeeBps = 250; // 2.5% platform fee
    uint256 public constant REPUTATION_DECAY_TIME = 365 days;
    
    // Events
    event ContentCreated(
        bytes32 indexed contentId,
        address indexed creator,
        address indexed coinAddress,
        string contentHash,
        uint256 timestamp,
        uint256 positionTokenId
    );
    
    event InspirationClaimed(
        bytes32 indexed claimId,
        bytes32 indexed originalContentId,
        bytes32 indexed derivativeContentId,
        address claimer,
        uint256 revenueShareBps,
        InspirationProofType proofType
    );
    
    event ZkProofVerified(
        bytes32 indexed claimId,
        bytes32 zkProofHash,
        bool verified
    );
    
    event RevenueDistributed(
        address indexed coin,
        address indexed creator,
        uint256 amount,
        bytes32 indexed sourceContentId
    );
    
    event InspirationDisputed(
        bytes32 indexed claimId,
        address indexed disputer,
        string reason
    );
    
    event ReputationUpdated(
        address indexed creator,
        uint256 newCollaboratorScore,
        string updateReason
    );

    event V4PositionCreated(
        bytes32 indexed contentId,
        uint256 indexed positionTokenId,
        PoolKey poolKey
    );

    constructor(
        address _zoraFactory,
        address _uniswapV4PoolManager,
        address _positionManager,
        address _proofOfInspirationHook,
        address _zkVerifier,
        address initialOwner
    ) Ownable(initialOwner) {
        zoraFactory = IZoraFactory(_zoraFactory);
        uniswapV4PoolManager = IUniswapV4PoolManager(_uniswapV4PoolManager);
        positionManager = IPositionManager(_positionManager);
        proofOfInspirationHook = _proofOfInspirationHook;
        zkVerifier = _zkVerifier;
    }
    
    /**
     * @dev Create new content and mint as Zora Coin with V4 liquidity
     */
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
        contentId = keccak256(abi.encodePacked(msg.sender, contentHash, block.timestamp));
        
        // Deploy Zora Coin
        address[] memory owners = new address[](1);
        owners[0] = msg.sender;
        
        (coinAddress, ) = zoraFactory.deploy{value: msg.value}(
            msg.sender,      // payoutRecipient
            owners,          // owners
            uri,            // metadata URI
            name,           // coin name
            symbol,         // coin symbol
            abi.encode(poolConfig), // pool configuration for V4
            platformReferrer, // platform referrer
            address(this),  // postDeployHook
            abi.encode(contentId), // hook data
            salt           // deterministic salt
        );
        
        // Create V4 pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(coinAddress < poolConfig.pairedToken ? coinAddress : poolConfig.pairedToken),
            currency1: Currency.wrap(coinAddress < poolConfig.pairedToken ? poolConfig.pairedToken : coinAddress),
            fee: poolConfig.fee,
            tickSpacing: poolConfig.tickSpacing,
            hooks: IHooks(proofOfInspirationHook)
        });
        
        // Initialize pool if needed
        try uniswapV4PoolManager.initialize(
            poolKey,
            poolConfig.initialSqrtPriceX96,
            abi.encode(contentId) // Pass contentId to hook
        ) {} catch {
            // Pool might already exist
        }
        
        // Create initial liquidity position
        mintParams.currency0 = poolKey.currency0;
        mintParams.currency1 = poolKey.currency1;
        mintParams.fee = poolConfig.fee;
        mintParams.recipient = msg.sender;
        
        (positionTokenId, , , ) = positionManager.mint(mintParams);
        
        // Subscribe to position notifications for fee collection
        positionManager.subscribe(positionTokenId, address(this));
        
        // Store content piece with V4 data
        contentPieces[contentId] = ContentPiece({
            creator: msg.sender,
            coinAddress: coinAddress,
            contentHash: contentHash,
            timestamp: block.timestamp,
            exists: true,
            totalDerivatives: 0,
            reputationScore: 0,
            poolKey: poolKey,
            positionTokenId: positionTokenId
        });
        
        // Store mappings
        creatorContent[msg.sender].push(contentId);
        positionToContentId[positionTokenId] = contentId;
        coinToPoolKey[coinAddress] = poolKey;
        
        emit ContentCreated(contentId, msg.sender, coinAddress, contentHash, block.timestamp, positionTokenId);
        emit V4PositionCreated(contentId, positionTokenId, poolKey);
    }
    
    /**
     * @dev Create derivative content with inspiration claim
     */
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
        (derivativeContentId, coinAddress, positionTokenId) = this.createContent(
            name, symbol, uri, contentHash, poolConfig, mintParams, platformReferrer, salt
        );
        
        // Create inspiration claim
        bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));
        
        inspirationClaims[claimId] = InspirationClaim({
            derivative: coinAddress,
            original: contentPieces[originalContentId].coinAddress,
            revenueShareBps: revenueShareBps,
            zkProofHash: zkProofHash,
            zkVerified: false,
            disputed: false,
            timestamp: block.timestamp,
            proofType: proofType
        });
        
        // Update graph structure
        inspirationGraph[originalContentId].push(derivativeContentId);
        contentDerivatives[originalContentId].push(derivativeContentId);
        contentPieces[originalContentId].totalDerivatives++;
        
        // Set depth in inspiration chain
        contentDepth[derivativeContentId] = contentDepth[originalContentId] + 1;
        
        // Verify zk-proof if provided
        if (zkProofHash != bytes32(0) && proofType == InspirationProofType.ZK_SIMILARITY_PROOF) {
            _verifyZkProof(claimId, zkProofHash);
        }
        
        // Update reputation
        _updateCreatorReputation(msg.sender, "DERIVATIVE_CREATED");
        _updateCreatorReputation(contentPieces[originalContentId].creator, "INSPIRED_OTHERS");
        
        emit InspirationClaimed(
            claimId,
            originalContentId,
            derivativeContentId,
            msg.sender,
            revenueShareBps,
            proofType
        );
    }

    /**
     * @dev IPositionSubscriber implementation - called when position liquidity changes
     */
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityDelta,
        BalanceDelta feesAccrued
    ) external override {
        require(msg.sender == address(positionManager), "Only position manager");
        
        bytes32 contentId = positionToContentId[tokenId];
        if (contentId == bytes32(0)) return; // Not our position
        
        // Handle fee collection and distribution
        if (BalanceDelta.unwrap(feesAccrued) != 0) {
            _distributeLiquidityFees(contentId, feesAccrued);
        }
    }

    /**
     * @dev IPositionSubscriber implementation - called when position ownership changes
     */
    function notifyTransfer(
        uint256 tokenId,
        address previousOwner,
        address newOwner
    ) external override {
        require(msg.sender == address(positionManager), "Only position manager");
        
        bytes32 contentId = positionToContentId[tokenId];
        if (contentId == bytes32(0)) return; // Not our position
        
        // Update content ownership if position is transferred
        if (contentPieces[contentId].creator == previousOwner) {
            contentPieces[contentId].creator = newOwner;
        }
    }

    /**
     * @dev Handle fee distribution from V4 liquidity positions
     */
    function _distributeLiquidityFees(bytes32 contentId, BalanceDelta feesAccrued) internal {
        ContentPiece memory content = contentPieces[contentId];
        
        // Check if this content has derivative claims
        bytes32[] memory derivatives = contentDerivatives[contentId];
        
        for (uint i = 0; i < derivatives.length; i++) {
            bytes32 claimId = keccak256(abi.encodePacked(contentId, derivatives[i]));
            InspirationClaim memory claim = inspirationClaims[claimId];
            
            if (claim.derivative != address(0) && !claim.disputed) {
                // Calculate revenue share from fees - handle both positive and negative deltas
                int256 feesDelta = BalanceDelta.unwrap(feesAccrued);
                if (feesDelta > 0) {
                    uint256 feeAmount = uint256(feesDelta);
                    uint256 shareAmount = (feeAmount * claim.revenueShareBps) / 10000;
                    
                    // Apply zk-proof bonus
                    if (claim.zkVerified) {
                        uint256 bonus = (shareAmount * 200) / 10000; // 2% bonus
                        shareAmount += bonus;
                    }
                    
                    // Add to pending revenue
                    pendingRevenue[claim.derivative][content.creator] += shareAmount;
                    totalRevenueGenerated[contentId] += shareAmount;
                    
                    emit RevenueDistributed(claim.derivative, content.creator, shareAmount, contentId);
                }
            }
        }
    }
    
    /**
     * @dev Verify zk-proof for inspiration claim
     */
    function _verifyZkProof(bytes32 claimId, bytes32 zkProofHash) internal {
        if (zkVerifier != address(0)) {
            bool verified = _callZkVerifier(zkProofHash);
            
            inspirationClaims[claimId].zkVerified = verified;
            verifiedProofs[zkProofHash] = verified;
            
            emit ZkProofVerified(claimId, zkProofHash, verified);
            
            if (verified) {
                address claimer = contentPieces[_getContentIdFromClaim(claimId)].creator;
                _updateCreatorReputation(claimer, "ZK_PROOF_VERIFIED");
            }
        }
    }
    
    /**
     * @dev Simplified zk verifier call (replace with actual implementation)
     */
    function _callZkVerifier(bytes32 proofHash) internal pure returns (bool) {
        return proofHash != bytes32(0);
    }
    
    /**
     * @dev Distribute revenue from derivative sales to original creators
     */
    function distributeRevenue(
        bytes32 claimId,
        uint256 amount
    ) external nonReentrant {
        InspirationClaim memory claim = inspirationClaims[claimId];
        require(claim.derivative != address(0), "Invalid claim");
        require(!claim.disputed, "Claim is disputed");
        require(msg.sender == claim.derivative, "Only derivative coin can distribute");
        
        // Calculate revenue split
        uint256 originalShare = (amount * claim.revenueShareBps) / 10000;
        uint256 platformFee = (amount * platformFeeBps) / 10000;
        uint256 derivativeShare = amount - originalShare - platformFee;
        
        // Apply zk-proof bonus
        if (claim.zkVerified) {
            uint256 bonus = (originalShare * 200) / 10000; // 2% bonus for verified proofs
            originalShare += bonus;
            derivativeShare -= bonus;
        }
        
        // Transfer revenue
        IERC20(claim.derivative).transferFrom(msg.sender, address(this), amount);
        
        // Update pending revenue
        bytes32 originalContentId = _getOriginalContentId(claimId);
        address originalCreator = contentPieces[originalContentId].creator;
        
        pendingRevenue[claim.original][originalCreator] += originalShare;
        totalRevenueGenerated[originalContentId] += originalShare;
        
        emit RevenueDistributed(claim.original, originalCreator, originalShare, originalContentId);
    }
    
    /**
     * @dev Claim pending revenue
     */
    function claimRevenue(address coinAddress) external nonReentrant {
        uint256 amount = pendingRevenue[coinAddress][msg.sender];
        require(amount > 0, "No pending revenue");
        
        pendingRevenue[coinAddress][msg.sender] = 0;
        IERC20(coinAddress).transfer(msg.sender, amount);
    }
    
    /**
     * @dev Collect fees from V4 position
     */
    function collectPositionFees(bytes32 contentId) external nonReentrant {
        ContentPiece memory content = contentPieces[contentId];
        require(content.exists, "Content does not exist");
        require(content.creator == msg.sender, "Not content creator");
        
        // Collect fees from the position
        positionManager.collect(
            content.positionTokenId,
            msg.sender,
            type(uint128).max,
            type(uint128).max
        );
    }
    
    /**
     * @dev Dispute an inspiration claim
     */
    function disputeInspiration(
        bytes32 claimId,
        string memory reason
    ) external {
        InspirationClaim storage claim = inspirationClaims[claimId];
        require(claim.derivative != address(0), "Invalid claim");
        
        bytes32 originalContentId = _getOriginalContentId(claimId);
        require(
            msg.sender == contentPieces[originalContentId].creator ||
            msg.sender == owner(),
            "Not authorized to dispute"
        );
        
        claim.disputed = true;
        
        // Penalize reputation for disputed claims
        bytes32 derivativeContentId = _getContentIdFromClaim(claimId);
        address claimer = contentPieces[derivativeContentId].creator;
        _updateCreatorReputation(claimer, "CLAIM_DISPUTED");
        
        emit InspirationDisputed(claimId, msg.sender, reason);
    }
    
    /**
     * @dev Calculate algorithmic ranking score
     */
    function calculateRankingScore(bytes32 contentId) external view returns (uint256) {
        ContentPiece memory content = contentPieces[contentId];
        require(content.exists, "Content does not exist");
        
        ReputationMetrics memory reputation = creatorReputations[content.creator];
        
        uint256 baseScore = 1000; // Base score
        uint256 inspirationBonus = 0;
        uint256 zkProofMultiplier = 1000; // 1.0x in basis points
        uint256 reputationMultiplier = 1000; // 1.0x in basis points
        uint256 graphBonus = 0;
        uint256 fraudPenalty = 0;
        
        // Check if this content has inspiration claims
        bytes32[] memory derivatives = contentDerivatives[contentId];
        for (uint i = 0; i < derivatives.length; i++) {
            bytes32 claimId = keccak256(abi.encodePacked(contentId, derivatives[i]));
            InspirationClaim memory claim = inspirationClaims[claimId];
            
            if (claim.derivative != address(0)) {
                inspirationBonus += 200; // +0.2 per inspiration
                
                if (claim.zkVerified) {
                    zkProofMultiplier += 300; // +0.3 for zk-proof
                }
            }
        }
        
        // Reputation multiplier (1.0x to 2.0x)
        reputationMultiplier = 1000 + (reputation.collaboratorScore * 1000) / 1000;
        if (reputationMultiplier > 2000) reputationMultiplier = 2000;
        
        // Graph participation bonus
        graphBonus = content.totalDerivatives * 100; // +0.1 per derivative
        if (graphBonus > 500) graphBonus = 500; // Cap at +0.5
        
        // Fraud penalty
        fraudPenalty = reputation.fraudFlags * 700; // -0.7 per fraud flag
        
        // Final calculation: (B + I + Z) * R + G - F
        uint256 score = ((baseScore + inspirationBonus + zkProofMultiplier) * reputationMultiplier) / 1000;
        score += graphBonus;
        score = score > fraudPenalty ? score - fraudPenalty : 0;
        
        return score;
    }
    
    /**
     * @dev Update creator reputation based on actions
     */
    function _updateCreatorReputation(address creator, string memory reason) internal {
        ReputationMetrics storage reputation = creatorReputations[creator];
        
        bytes32 reasonHash = keccak256(abi.encodePacked(reason));
        
        if (reasonHash == keccak256("DERIVATIVE_CREATED")) {
            reputation.totalDerivatives++;
            reputation.collaboratorScore += 10;
        } else if (reasonHash == keccak256("INSPIRED_OTHERS")) {
            reputation.totalInspirations++;
            reputation.collaboratorScore += 15;
        } else if (reasonHash == keccak256("ZK_PROOF_VERIFIED")) {
            reputation.successfulCollaborations++;
            reputation.collaboratorScore += 25;
        } else if (reasonHash == keccak256("CLAIM_DISPUTED")) {
            reputation.fraudFlags++;
            reputation.collaboratorScore = reputation.collaboratorScore > 50 ? 
                reputation.collaboratorScore - 50 : 0;
        }
        
        emit ReputationUpdated(creator, reputation.collaboratorScore, reason);
    }
    
    /**
     * @dev Get inspiration graph for a content piece
     */
    function getInspirationGraph(bytes32 contentId) external view returns (
        bytes32[] memory derivatives,
        uint256 depth,
        uint256 totalRevenue
    ) {
        derivatives = contentDerivatives[contentId];
        depth = contentDepth[contentId];
        totalRevenue = totalRevenueGenerated[contentId];
    }
    
    /**
     * @dev Get creator's reputation metrics
     */
    function getCreatorReputation(address creator) external view returns (ReputationMetrics memory) {
        return creatorReputations[creator];
    }
    
    /**
     * @dev Get V4 pool information for a content piece
     */
    function getV4PoolInfo(bytes32 contentId) external view returns (
        PoolKey memory poolKey,
        uint256 positionTokenId,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        ContentPiece memory content = contentPieces[contentId];
        require(content.exists, "Content does not exist");
        
        poolKey = content.poolKey;
        positionTokenId = content.positionTokenId;
        
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        (sqrtPriceX96, tick, , ) = uniswapV4PoolManager.getSlot0(poolId);
    }
    
    // Helper functions
    function _getContentIdFromClaim(bytes32 claimId) internal view returns (bytes32) {
        // Implementation depends on how claimId is constructed
        return bytes32(0); // Placeholder
    }
    
    function _getOriginalContentId(bytes32 claimId) internal view returns (bytes32) {
        // Implementation depends on how claimId is constructed
        return bytes32(0); // Placeholder
    }
    
    // Admin functions
    function setZkVerifier(address _zkVerifier) external onlyOwner {
        zkVerifier = _zkVerifier;
    }
    
    function setPlatformFee(uint256 _platformFeeBps) external onlyOwner {
        require(_platformFeeBps <= 1000, "Platform fee too high"); // Max 10%
        platformFeeBps = _platformFeeBps;
    }
}