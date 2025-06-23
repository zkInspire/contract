// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "./IPoolManager.sol";

/**
 * @title IUniswapV4PoolManager
 * @dev Interface for interacting with Uniswap V4's singleton PoolManager
 */
interface IUniswapV4PoolManager {
    /**
     * @notice Initialize a new pool
     * @param key The pool key (tokens, fee, tickSpacing, hooks)
     * @param sqrtPriceX96 The initial sqrt price of the pool
     * @param hookData Optional data to pass to hooks
     */
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        returns (int24 tick);

    /**
     * @notice Get pool state
     */
    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    /**
     * @notice Modify liquidity for a position
     * @param key The pool key
     * @param params Liquidity modification parameters
     * @param hookData Optional hook data
     */
    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);

    /**
     * @notice Perform a swap
     * @param key The pool key
     * @param params Swap parameters
     * @param hookData Optional hook data
     */
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);

    /**
     * @notice Unlock the pool manager for flash accounting
     * @param data Encoded function call to execute while unlocked
     */
    function unlock(bytes calldata data) external returns (bytes memory result);

    /**
     * @notice Take tokens from the pool manager
     * @param currency The currency to take
     * @param to The recipient
     * @param amount The amount to take
     */
    function take(Currency currency, address to, uint256 amount) external;

    /**
     * @notice Settle tokens with the pool manager
     * @param currency The currency to settle
     */
    function settle(Currency currency) external returns (uint256 paid);

    /**
     * @notice Mint tokens to an address (for fee collection)
     * @param to The recipient
     * @param currency The currency
     * @param amount The amount to mint
     */
    function mint(address to, Currency currency, uint256 amount) external;

    /**
     * @notice Burn tokens from an address
     * @param from The address to burn from
     * @param currency The currency
     * @param amount The amount to burn
     */
    function burn(address from, Currency currency, uint256 amount) external;

    /**
     * @notice Get protocol fees for a pool
     */
    function protocolFeesAccrued(Currency currency) external view returns (uint256 amount);

    /**
     * @notice Collect protocol fees
     * @param recipient The fee recipient
     * @param currency The currency to collect
     * @param amount The amount to collect (0 for all)
     */
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected);
}
