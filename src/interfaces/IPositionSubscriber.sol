import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @title IPositionSubscriber
 * @dev Interface for contracts that want to receive position notifications
 */
interface IPositionSubscriber {
    /**
     * @notice Called when position liquidity changes
     * @param tokenId The position token ID
     * @param liquidityDelta The change in liquidity
     * @param feesAccrued Any fees accrued during the change
     */
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityDelta,
        BalanceDelta feesAccrued
    ) external;

    /**
     * @notice Called when position ownership changes
     * @param tokenId The position token ID
     * @param previousOwner Previous owner address
     * @param newOwner New owner address
     */
    function notifyTransfer(
        uint256 tokenId,
        address previousOwner,
        address newOwner
    ) external;
}