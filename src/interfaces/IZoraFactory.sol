// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IZoraFactory {
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes calldata postDeployHookData,
        bytes32 coinSalt
    ) external payable returns (address coin, bytes memory postDeployHookDataOut);

    function coinAddress(
        address msgSender,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) external view returns (address);
}
