// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
/**
 * @title IPoolManager - Core interface for V4 liquidity operations
 */

interface IPoolManager {
    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt; // V4's new salt parameter for position separation
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
}
