// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface ISafe {
    function checkSignatures(bytes32 dataHash, bytes memory data, bytes memory signatures) external;
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    )
        external
        returns (bool success);
}
