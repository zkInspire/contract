// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Uniswap V4 core types
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

// Interface imports
import "./interfaces/IUniswapV4PoolManager.sol";

// Main contract import (assuming it's in the same directory)
import "./ProofOfInspiration.sol";

/**
 * @title InspirationRevenueRouter
 * @dev Handles automatic revenue routing from Uniswap V4 hooks to inspiration claims
 */
contract InspirationRevenueRouter is ReentrancyGuard {
    ProofOfInspiration public immutable proofOfInspiration;
    IUniswapV4PoolManager public immutable poolManager;

    mapping(address => bytes32) public coinToContentId; // Zora coin => content ID
    mapping(PoolId => bytes32) public poolToContentId; // V4 pool => content ID
    mapping(address => uint256) public lastFeeCollection; // Track last fee collection timestamp

    event FeesCollected(address indexed coin, uint256 amount, uint256 timestamp);
    event RevenueRouted(bytes32 indexed claimId, uint256 amount);
    event V4FeesCollected(PoolId indexed poolId, uint256 amount0, uint256 amount1);

    constructor(address _proofOfInspiration, address _poolManager) {
        proofOfInspiration = ProofOfInspiration(_proofOfInspiration);
        poolManager = IUniswapV4PoolManager(_poolManager);
    }

    /**
     * @dev Register a coin with its content ID for revenue routing
     */
    function registerCoin(address coin, bytes32 contentId) external {
        require(msg.sender == address(proofOfInspiration), "Unauthorized");
        coinToContentId[coin] = contentId;
    }

    /**
     * @dev Register a V4 pool with its content ID
     */
    function registerPool(PoolId poolId, bytes32 contentId) external {
        require(msg.sender == address(proofOfInspiration), "Unauthorized");
        poolToContentId[poolId] = contentId;
    }

    /**
     * @dev Collect protocol fees from V4 pool and route to inspiration claims
     */
    function collectAndRouteV4Fees(PoolKey memory poolKey, Currency currency0, Currency currency1) external {
        PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
        bytes32 contentId = poolToContentId[poolId];
        require(contentId != bytes32(0), "Pool not registered");

        // Collect protocol fees
        uint256 amount0 = poolManager.collectProtocolFees(address(this), currency0, 0);
        uint256 amount1 = poolManager.collectProtocolFees(address(this), currency1, 0);

        emit V4FeesCollected(poolId, amount0, amount1);

        // Route fees to inspiration claims would be handled by the main contract
        // through the position subscriber mechanism
    }
}
