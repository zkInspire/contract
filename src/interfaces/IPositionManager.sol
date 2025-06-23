import {Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title IPositionManager
 * @dev Interface for V4's position management with subscriber support
 */
interface IPositionManager {
    struct MintParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        bytes32 salt; // For fee accounting separation
    }

    /**
     * @notice Mint a new position
     */
    function mint(MintParams calldata params) 
        external 
        payable 
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /**
     * @notice Set a subscriber for position notifications
     * @param tokenId The position token ID
     * @param subscriber The subscriber contract address
     */
    function subscribe(uint256 tokenId, address subscriber) external;

    /**
     * @notice Unsubscribe from position notifications
     * @param tokenId The position token ID
     */
    function unsubscribe(uint256 tokenId) external;

    /**
     * @notice Collect fees from a position
     * @param tokenId The position token ID
     * @param recipient Fee recipient
     * @param amount0Max Maximum amount of token0 to collect
     * @param amount1Max Maximum amount of token1 to collect
     */
    function collect(
        uint256 tokenId,
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    ) external returns (uint256 amount0, uint256 amount1);
}
