// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ProofOfInspiration.sol";

contract MockPositionManager {
    uint256 private nextTokenId = 1;
    mapping(uint256 => address) public subscribers;
    mapping(uint256 => address) public owners;

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
    }

    function mint(MintParams memory params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = nextTokenId++;
        owners[tokenId] = params.recipient;
        return (tokenId, 100000, 1000, 1000);
    }

    function subscribe(uint256 tokenId, address subscriber) external {
        subscribers[tokenId] = subscriber;
    }

    function collect(uint256 tokenId, address recipient, uint128 amount0Max, uint128 amount1Max)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return (1000, 1000);
    }

    // Simulate fee notification
    function simulateFeeCollection(uint256 tokenId, int256 feeAmount) external {
        address subscriber = subscribers[tokenId];
        if (subscriber != address(0)) {
            IPositionSubscriber(subscriber).notifyModifyLiquidity(tokenId, 0, BalanceDelta.wrap(feeAmount));
        }
    }
}
