// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ISafe} from "./interfaces/ISafe.sol";

/**
 * @title ScheduledTxModule
 * @notice A Safe module that allows scheduling transactions with time-based execution windows
 * @dev Uses EIP-712 signatures to authorize scheduled transactions that can only be executed within specified time
 * windows
 */
contract ScheduledTxModule {
    /**
     * @notice EIP-712 type hash for scheduled transaction permits
     * @dev Used to generate the struct hash for signature verification
     */
    bytes32 public immutable PERMIT_TYPEHASH = keccak256(
        "ScheduledTxModule(address to,uint256 value,bytes data,uint256 nonce,uint64 executeAfter,uint64 deadline)"
    );

    /**
     * @notice Tracks which nonces have been used for each Safe
     * @dev Mapping from Safe address to nonce to execution status
     */
    mapping(address safe => mapping(uint256 nonce => bool used)) public nonces;

    /**
     * @notice Tracks which nonces have been cancelled for each Safe
     * @dev Mapping from Safe address to nonce to cancellation status.
     */
    mapping(address safe => mapping(uint256 nonce => bool cancelled)) public cancelled;

    /**
     * @notice Emitted when a Safe cancels a scheduled transaction by nonce
     * @param safe The Safe that cancelled the scheduled transaction
     * @param nonce The nonce that was cancelled
     */
    event Cancelled(address indexed safe, uint256 indexed nonce);

    /**
     * @notice Thrown when attempting to execute a transaction after its deadline
     */
    error TransactionExpired();

    /**
     * @notice Thrown when attempting to reuse a nonce that has already been executed
     */
    error AlreadyExecuted();

    /**
     * @notice Thrown when attempting to execute a transaction before its executeAfter timestamp
     */
    error TooEarly();

    /**
     * @notice Thrown when the module transaction execution fails
     */
    error ModuleTxFailed();

    /**
     * @notice Thrown when attempting to execute a transaction that has been cancelled
     */
    error TransactionCancelled();

    /**
     * @notice Generates the EIP-712 domain separator for this contract
     * @dev The domain separator includes the contract name, version, chain ID, and address
     * @return The EIP-712 domain separator hash
     */
    function getDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ScheduledTxModule")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Executes a scheduled transaction on behalf of a Safe
     * @dev Validates timing constraints, signature, and marks nonce as used before execution
     * @param safe The address of the Safe contract that will execute the transaction
     * @param to The destination address for the transaction
     * @param value The amount of ETH to send with the transaction (in wei)
     * @param data The calldata to send with the transaction
     * @param nonce A unique identifier for this scheduled transaction (prevents replay attacks)
     * @param executeAfter The earliest timestamp when this transaction can be executed
     * @param deadline The latest timestamp when this transaction can be executed
     * @param signatures EIP-712 signature(s) from Safe owner(s) authorizing this transaction
     * @custom:reverts TooEarly if current timestamp is before executeAfter
     * @custom:reverts TransactionExpired if current timestamp is after deadline
     * @custom:reverts AlreadyExecuted if this nonce has already been used for this Safe
     * @custom:reverts TransactionCancelled if this nonce has been cancelled for this Safe
     * @custom:reverts ModuleTxFailed if the Safe transaction execution fails
     */
    function execute(
        address safe,
        address to,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        uint64 executeAfter,
        uint64 deadline,
        bytes memory signatures
    )
        external
    {
        require(block.timestamp <= deadline, TransactionExpired());
        require(block.timestamp >= executeAfter, TooEarly());
        require(nonces[safe][nonce] == false, AlreadyExecuted());
        require(cancelled[safe][nonce] == false, TransactionCancelled());

        nonces[safe][nonce] = true;

        bytes32 signatureData = keccak256(abi.encode(PERMIT_TYPEHASH, to, value, data, nonce, executeAfter, deadline));

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), signatureData));

        ISafe(payable(safe)).checkSignatures(hash, abi.encodePacked(signatureData), signatures);

        require(ISafe(payable(safe)).execTransactionFromModule(to, value, data, 0), ModuleTxFailed());
    }

    /**
     * @notice Cancels a scheduled transaction so it can be blocked before execution.
     * @dev Must be called by the Safe itself, via Safe transaction. Cancelling an already-cancelled
     * nonce is a no-op; cancelling an already-executed nonce reverts with AlreadyExecuted.
     * @param nonce The nonce of the scheduled transaction to cancel
     * @custom:reverts AlreadyExecuted if this nonce has already been executed for the caller
     */
    function cancel(uint256 nonce) external {
        require(nonces[msg.sender][nonce] == false, AlreadyExecuted());
        cancelled[msg.sender][nonce] = true;
        emit Cancelled(msg.sender, nonce);
    }
}
