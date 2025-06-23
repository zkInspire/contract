// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ProofOfInspiration.sol";

contract MockUniswapV4PoolManager {
    mapping(bytes32 => bool) public pools;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes memory hookData)
        external
        returns (int24 tick)
    {
        bytes32 poolId = keccak256(abi.encode(key));
        pools[poolId] = true;
        return 0;
    }

    function getSlot0(PoolId poolId)
        external
        pure
        returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint16 lpFee)
    {
        return (79228162514264337593543950336, 0, 0, 3000);
    }
}
