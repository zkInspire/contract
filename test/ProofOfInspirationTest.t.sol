// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ProofOfInspiration.sol";
import "./MockERC20.sol";
import "./MockPositionManager.sol";
import "./MockUniswapV4PoolManager.sol";
import "./MockZkVerifier.sol";
import "./MockZoraFactory.sol";

contract ProofOfInspirationTest is Test {
    ProofOfInspiration public proofOfInspiration;
    MockZoraFactory public zoraFactory;
    MockUniswapV4PoolManager public poolManager;
    MockPositionManager public positionManager;
    MockZkVerifier public zkVerifier;

    address public hook = address(0x1234);
    address public owner = address(0x5678);
    address public creator1 = address(0x1111);
    address public creator2 = address(0x2222);
    address public pairedToken = address(0x3333);

    // Test data
    string constant CONTENT_NAME = "Test Content";
    string constant CONTENT_SYMBOL = "TEST";
    string constant CONTENT_URI = "ipfs://test-content";
    string constant CONTENT_HASH = "QmTestHash123";

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
        ProofOfInspiration.InspirationProofType proofType
    );

    event RevenueDistributed(
        address indexed coin, address indexed creator, uint256 amount, bytes32 indexed sourceContentId
    );

    function setUp() public {
        // Deploy mock contracts
        zoraFactory = new MockZoraFactory();
        poolManager = new MockUniswapV4PoolManager();
        positionManager = new MockPositionManager();
        zkVerifier = new MockZkVerifier();

        // Deploy main contract
        proofOfInspiration = new ProofOfInspiration(
            address(zoraFactory), address(poolManager), address(positionManager), hook, address(zkVerifier), owner
        );

        // Setup test accounts with ETH
        vm.deal(creator1, 10 ether);
        vm.deal(creator2, 10 ether);
        vm.deal(owner, 10 ether);
    }

    function getTestPoolConfig() internal view returns (ProofOfInspiration.V4PoolConfig memory) {
        return ProofOfInspiration.V4PoolConfig({
            pairedToken: pairedToken,
            fee: 3000,
            tickSpacing: 60,
            initialSqrtPriceX96: 79228162514264337593543950336
        });
    }

    function getTestMintParams() internal view returns (IPositionManager.MintParams memory) {
        return IPositionManager.MintParams({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 3000,
            tickLower: -60,
            tickUpper: 60,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 900,
            amount1Min: 900,
            recipient: address(0),
            deadline: block.timestamp + 1 hours,
            salt: bytes32(0)
        });
    }

    function testCreateContent() public {
        vm.startPrank(creator1);

        ProofOfInspiration.V4PoolConfig memory poolConfig = getTestPoolConfig();
        IPositionManager.MintParams memory mintParams = getTestMintParams();

        // Expect event emission
        vm.expectEmit(true, true, true, false);
        emit ContentCreated(
            bytes32(0), // We don't know the exact contentId beforehand
            creator1,
            address(0), // We don't know the coin address beforehand
            CONTENT_HASH,
            block.timestamp,
            0
        );

        (bytes32 contentId, address coinAddress, uint256 positionTokenId) = proofOfInspiration.createContent{
            value: 0.01 ether
        }(CONTENT_NAME, CONTENT_SYMBOL, CONTENT_URI, CONTENT_HASH, poolConfig, mintParams, address(0), bytes32(0));

        vm.stopPrank();

        // Verify content was created
        (
            address creator,
            address storedCoinAddress,
            string memory contentHash,
            uint256 timestamp,
            bool exists,
            uint256 totalDerivatives,
            uint256 reputationScore,
            ,
            uint256 storedPositionTokenId
        ) = proofOfInspiration.contentPieces(contentId);

        assertEq(creator, creator1);
        assertEq(storedCoinAddress, coinAddress);
        assertEq(contentHash, CONTENT_HASH);
        assertTrue(exists);
        assertEq(totalDerivatives, 0);
        assertEq(reputationScore, 0);
        assertEq(storedPositionTokenId, positionTokenId);

        // Verify position mapping
        assertEq(proofOfInspiration.positionToContentId(positionTokenId), contentId);
    }

    function testCreateDerivativeWithInspiration() public {
        // First create original content
        vm.startPrank(creator1);

        (bytes32 originalContentId, address originalCoinAddress,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );

        vm.stopPrank();

        // Create derivative content
        vm.startPrank(creator2);

        string memory derivativeName = "Derivative Content";
        string memory derivativeSymbol = "DERIV";
        string memory derivativeHash = "QmDerivativeHash456";
        uint256 revenueShareBps = 1000; // 10%
        bytes32 zkProofHash = keccak256("test-proof");

        // Set up zk proof verification
        zkVerifier.setProofVerification(zkProofHash, true);

        vm.expectEmit(true, true, true, false);
        emit InspirationClaimed(
            bytes32(0), // claimId
            originalContentId,
            bytes32(0), // derivativeContentId
            creator2,
            revenueShareBps,
            ProofOfInspiration.InspirationProofType.ZK_SIMILARITY_PROOF
        );

        (bytes32 derivativeContentId, address derivativeCoinAddress,) = proofOfInspiration
            .createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            derivativeName,
            derivativeSymbol,
            CONTENT_URI,
            derivativeHash,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            revenueShareBps,
            zkProofHash,
            ProofOfInspiration.InspirationProofType.ZK_SIMILARITY_PROOF
        );

        vm.stopPrank();

        // Verify inspiration claim
        bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));

        (
            address derivative,
            address original,
            uint256 storedRevenueShareBps,
            bytes32 storedZkProofHash,
            bool zkVerified,
            bool disputed,
            uint256 timestamp,
            ProofOfInspiration.InspirationProofType proofType
        ) = proofOfInspiration.inspirationClaims(claimId);

        assertEq(derivative, derivativeCoinAddress);
        assertEq(original, originalCoinAddress);
        assertEq(storedRevenueShareBps, revenueShareBps);
        assertEq(storedZkProofHash, zkProofHash);
        assertTrue(zkVerified);
        assertFalse(disputed);
        assertEq(uint256(proofType), uint256(ProofOfInspiration.InspirationProofType.ZK_SIMILARITY_PROOF));

        // Verify graph structure
        (bytes32[] memory derivatives, uint256 depth, uint256 totalRevenue) =
            proofOfInspiration.getInspirationGraph(originalContentId);

        assertEq(derivatives.length, 1);
        assertEq(derivatives[0], derivativeContentId);
        assertEq(depth, 0); // Original content has depth 0
        assertEq(totalRevenue, 0); // No revenue distributed yet

        // Check derivative depth
        (,, uint256 derivativeDepth) = proofOfInspiration.getInspirationGraph(derivativeContentId);
        assertEq(derivativeDepth, 1); // Derivative has depth 1
    }

    function testRevenueDistribution() public {
        // Create original and derivative content
        vm.startPrank(creator1);
        (bytes32 originalContentId, address originalCoinAddress,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        (bytes32 derivativeContentId, address derivativeCoinAddress,) = proofOfInspiration
            .createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000, // 10% revenue share
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );
        vm.stopPrank();

        // Distribute revenue
        bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));
        uint256 revenueAmount = 10000;

        // Mint tokens to derivative coin for distribution
        MockERC20(derivativeCoinAddress).mint(derivativeCoinAddress, revenueAmount);

        vm.startPrank(derivativeCoinAddress);
        MockERC20(derivativeCoinAddress).approve(address(proofOfInspiration), revenueAmount);

        vm.expectEmit(true, true, true, false);
        emit RevenueDistributed(
            originalCoinAddress,
            creator1,
            1000, // 10% of 10000
            originalContentId
        );

        proofOfInspiration.distributeRevenue(claimId, revenueAmount);
        vm.stopPrank();

        // Check pending revenue
        uint256 pendingRevenue = proofOfInspiration.pendingRevenue(originalCoinAddress, creator1);
        assertEq(pendingRevenue, 1000);

        // Check total revenue generated
        uint256 totalRevenue = proofOfInspiration.totalRevenueGenerated(originalContentId);
        assertEq(totalRevenue, 1000);
    }

    function testClaimRevenue() public {
        // Setup revenue distribution first
        testRevenueDistribution();

        // Get the coin address from the original content
        vm.startPrank(creator1);
        (bytes32 originalContentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );

        (, address originalCoinAddress,,,,,,,) = proofOfInspiration.contentPieces(originalContentId);

        // Mint tokens to the contract for payout
        MockERC20(originalCoinAddress).mint(address(proofOfInspiration), 1000);

        uint256 balanceBefore = MockERC20(originalCoinAddress).balanceOf(creator1);

        proofOfInspiration.claimRevenue(originalCoinAddress);

        uint256 balanceAfter = MockERC20(originalCoinAddress).balanceOf(creator1);
        assertEq(balanceAfter - balanceBefore, 1000);

        // Check that pending revenue is cleared
        uint256 pendingRevenue = proofOfInspiration.pendingRevenue(originalCoinAddress, creator1);
        assertEq(pendingRevenue, 0);

        vm.stopPrank();
    }

    function testLiquidityFeeDistribution() public {
        // Create original and derivative content
        vm.startPrank(creator1);
        (bytes32 originalContentId,, uint256 positionTokenId) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        (bytes32 derivativeContentId,,) = proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000, // 10% revenue share
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );
        vm.stopPrank();

        // Simulate fee collection
        int256 feeAmount = 5000;
        positionManager.simulateFeeCollection(positionTokenId, feeAmount);

        // Check that revenue was distributed
        (, address derivativeCoinAddress,,,,,,,) = proofOfInspiration.contentPieces(derivativeContentId);
        uint256 pendingRevenue = proofOfInspiration.pendingRevenue(derivativeCoinAddress, creator1);
        assertEq(pendingRevenue, 500); // 10% of 5000
    }

    function testDisputeInspiration() public {
        // Create original and derivative content
        vm.startPrank(creator1);
        (bytes32 originalContentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        (bytes32 derivativeContentId,,) = proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000,
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );
        vm.stopPrank();

        // Dispute the claim
        bytes32 claimId = keccak256(abi.encodePacked(originalContentId, derivativeContentId));

        vm.startPrank(creator1);
        proofOfInspiration.disputeInspiration(claimId, "Plagiarism");
        vm.stopPrank();

        // Verify claim is disputed
        (,,,, bool zkVerified, bool disputed,,) = proofOfInspiration.inspirationClaims(claimId);
        assertTrue(disputed);

        // Check reputation penalty
        ProofOfInspiration.ReputationMetrics memory reputation = proofOfInspiration.getCreatorReputation(creator2);
        assertEq(reputation.fraudFlags, 1);
    }

    function testCalculateRankingScore() public {
        // Create content
        vm.startPrank(creator1);
        (bytes32 contentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        // Calculate initial ranking score
        uint256 initialScore = proofOfInspiration.calculateRankingScore(contentId);
        assertEq(initialScore, 1000); // Base score

        // Create derivative to increase score
        vm.startPrank(creator2);
        proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            contentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000,
            keccak256("test-proof"),
            ProofOfInspiration.InspirationProofType.ZK_SIMILARITY_PROOF
        );
        vm.stopPrank();

        // Set up zk proof verification
        zkVerifier.setProofVerification(keccak256("test-proof"), true);

        // Calculate new ranking score
        uint256 newScore = proofOfInspiration.calculateRankingScore(contentId);
        assertTrue(newScore > initialScore);
    }

    function testFailCreateDerivativeWithInvalidOriginal() public {
        vm.startPrank(creator1);

        vm.expectRevert("Original content does not exist");
        proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            bytes32("invalid"),
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000,
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );

        vm.stopPrank();
    }

    function testFailCreateDerivativeWithExcessiveRevenueShare() public {
        // Create original content first
        vm.startPrank(creator1);
        (bytes32 originalContentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(creator2);

        vm.expectRevert("Revenue share too high");
        proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            6000, // 60% - exceeds MAX_REVENUE_SHARE_BPS (50%)
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );

        vm.stopPrank();
    }

    function testFailClaimRevenueWithNoPendingRevenue() public {
        vm.startPrank(creator1);

        vm.expectRevert("No pending revenue");
        proofOfInspiration.claimRevenue(address(0x1234));

        vm.stopPrank();
    }

    function testOwnerFunctions() public {
        // Test setZkVerifier
        address newZkVerifier = address(0x9999);

        vm.startPrank(owner);
        proofOfInspiration.setZkVerifier(newZkVerifier);
        assertEq(proofOfInspiration.zkVerifier(), newZkVerifier);
        vm.stopPrank();

        // Test setPlatformFee
        vm.startPrank(owner);
        proofOfInspiration.setPlatformFee(500); // 5%
        assertEq(proofOfInspiration.platformFeeBps(), 500);
        vm.stopPrank();

        // Test fail cases for non-owner
        vm.startPrank(creator1);
        vm.expectRevert();
        proofOfInspiration.setZkVerifier(address(0x8888));

        vm.expectRevert();
        proofOfInspiration.setPlatformFee(300);
        vm.stopPrank();
    }

    function testFailSetExcessivePlatformFee() public {
        vm.startPrank(owner);

        vm.expectRevert("Platform fee too high");
        proofOfInspiration.setPlatformFee(1100); // 11% - exceeds max 10%

        vm.stopPrank();
    }

    function testGetV4PoolInfo() public {
        vm.startPrank(creator1);
        (bytes32 contentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        (PoolKey memory poolKey, uint256 positionTokenId, uint160 sqrtPriceX96, int24 tick) =
            proofOfInspiration.getV4PoolInfo(contentId);

        assertEq(poolKey.fee, 3000);
        assertEq(poolKey.tickSpacing, 60);
        assertGt(positionTokenId, 0);
        assertGt(sqrtPriceX96, 0);
        assertEq(tick, 0);
    }

    function testReputationMetrics() public {
        // Create content to trigger reputation updates
        vm.startPrank(creator1);
        (bytes32 originalContentId,,) = proofOfInspiration.createContent{value: 0.01 ether}(
            CONTENT_NAME,
            CONTENT_SYMBOL,
            CONTENT_URI,
            CONTENT_HASH,
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        proofOfInspiration.createDerivativeWithInspiration{value: 0.01 ether}(
            originalContentId,
            "Derivative",
            "DERIV",
            CONTENT_URI,
            "QmDerivativeHash",
            getTestPoolConfig(),
            getTestMintParams(),
            address(0),
            bytes32(0),
            1000,
            bytes32(0),
            ProofOfInspiration.InspirationProofType.DECLARED_ONLY
        );
        vm.stopPrank();

        // Check reputation metrics
        ProofOfInspiration.ReputationMetrics memory creator1Rep = proofOfInspiration.getCreatorReputation(creator1);
        ProofOfInspiration.ReputationMetrics memory creator2Rep = proofOfInspiration.getCreatorReputation(creator2);

        // Creator1 should have inspiration score
        assertEq(creator1Rep.totalInspirations, 1);
        assertEq(creator1Rep.collaboratorScore, 15); // INSPIRED_OTHERS bonus

        // Creator2 should have derivative score
        assertEq(creator2Rep.totalDerivatives, 1);
        assertEq(creator2Rep.collaboratorScore, 10); // DERIVATIVE_CREATED bonus
    }
}
