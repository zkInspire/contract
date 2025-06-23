// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract MockZkVerifier {
    mapping(bytes32 => bool) public verifiedProofs;

    function setProofVerification(bytes32 proofHash, bool verified) external {
        verifiedProofs[proofHash] = verified;
    }

    function verify(bytes32 proofHash) external view returns (bool) {
        return verifiedProofs[proofHash];
    }
}
