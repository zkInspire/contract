import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
/**
 * @title ProofOfInspirationV4Hook
 * @dev Custom hook for automatic fee routing in V4
 */
interface IProofOfInspirationHook {
    /**
     * @notice Called after each swap to route fees to inspiration claims
     * @param key The pool key
     * @param params Swap parameters
     * @param delta The balance delta from the swap
     * @param hookData Custom data for inspiration routing
     */
    function afterSwap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4 selector);

    /**
     * @notice Called when liquidity is modified to handle fee distribution
     */
    function afterModifyLiquidity(
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4 selector);
}