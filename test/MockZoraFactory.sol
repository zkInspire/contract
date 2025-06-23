// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./MockERC20.sol";

// Mock contracts for testing
contract MockZoraFactory {
    uint256 public constant DEPLOYMENT_COST = 0.01 ether;

    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes memory hookData,
        bytes32 salt
    ) external payable returns (address coinAddress, uint256 tokenId) {
        require(msg.value >= DEPLOYMENT_COST, "Insufficient deployment fee");

        // Deploy mock ERC20 token
        MockERC20 token = new MockERC20(name, symbol);
        coinAddress = address(token);
        tokenId = 1;

        // Mint initial supply to creator
        token.mint(owners[0], 1000000 * 10 ** 18);

        return (coinAddress, tokenId);
    }
}
