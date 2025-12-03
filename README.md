# ScheduledTxModule

A Safe module that enables scheduling transactions with time-based execution windows using EIP-712 signatures.

> ⚠️ **WARNING: This contract has NOT been audited. Use at your own risk.**

## Overview

The ScheduledTxModule allows Safe owners to pre-sign transactions that can only be executed within a specific time window. This is useful for:

- **Delayed execution**: Schedule transactions to execute at a future time
- **Time-bounded permissions**: Grant temporary execution rights that expire after a deadline
- **Automation**: Enable third parties to execute pre-authorized transactions within defined time constraints

## How It Works

1. **Sign**: Safe owner(s) create an EIP-712 signature authorizing a transaction with time constraints
2. **Wait**: Transaction cannot execute until `executeAfter` timestamp
3. **Execute**: Anyone can call `execute()` with the signature between `executeAfter` and `deadline`
4. **Expire**: Transaction becomes invalid after `deadline`

## Contract Interface

### execute()

```solidity
function execute(
    address safe,
    address to,
    uint256 value,
    bytes memory data,
    uint256 nonce,
    uint64 executeAfter,
    uint64 deadline,
    bytes memory signatures
) external
```

**Parameters:**
- `safe`: Address of the Safe contract
- `to`: Destination address for the transaction
- `value`: ETH amount to send (in wei)
- `data`: Transaction calldata
- `nonce`: Unique transaction identifier (prevents replay)
- `executeAfter`: Earliest execution timestamp (Unix timestamp)
- `deadline`: Latest execution timestamp (Unix timestamp)
- `signatures`: EIP-712 signature(s) from Safe owner(s)

**Reverts:**
- `TooEarly`: When `block.timestamp < executeAfter`
- `TransactionExpired`: When `block.timestamp > deadline`
- `AlreadyExecuted`: When nonce has been used
- `ModuleTxFailed`: When Safe transaction execution fails

## EIP-712 Type Definition

```solidity
ScheduledTxModule(
    address to,
    uint256 value,
    bytes data,
    uint256 nonce,
    uint64 executeAfter,
    uint64 deadline
)
```

**Domain Separator:**
```solidity
EIP712Domain(
    string name,           // "ScheduledTxModule"
    string version,        // "1"
    uint256 chainId,       // Current chain ID
    address verifyingContract  // Module address
)
```

## Installation

### Using Forge

```bash
forge install 5afe/scheduled-tx-module
```

### Manual

```bash
git clone https://github.com/5afe/scheduled-tx-module.git
cd scheduled-tx-module
forge install
```

## Usage Example

### 1. Enable Module on Safe

First, enable the module on your Safe:

```solidity
safe.enableModule(scheduledTxModuleAddress);
```

### 2. Create EIP-712 Signature

```javascript
const domain = {
    name: "ScheduledTxModule",
    version: "1",
    chainId: chainId,
    verifyingContract: moduleAddress
};

const types = {
    ScheduledTxModule: [
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "data", type: "bytes" },
        { name: "nonce", type: "uint256" },
        { name: "executeAfter", type: "uint64" },
        { name: "deadline", type: "uint64" }
    ]
};

const value = {
    to: recipientAddress,
    value: ethers.parseEther("1.0"),
    data: "0x",
    nonce: 0,
    executeAfter: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
    deadline: Math.floor(Date.now() / 1000) + 86400    // 24 hours from now
};

const signature = await signer.signTypedData(domain, types, value);
```

### 3. Execute Transaction

```solidity
scheduledTxModule.execute(
    safeAddress,
    recipientAddress,
    1 ether,
    "",
    0,
    executeAfter,
    deadline,
    signature
);
```

## Security Considerations

⚠️ **Important Security Notes:**

1. **Signature Validity**: Signatures remain valid even if Safe configuration changes (e.g., adding owners), as long as the original signer is still an owner
2. **No Cancellation**: Once signed, transactions cannot be cancelled (only prevented by removing the signer or disabling the module)
3. **Permissionless Execution**: Anyone can execute a properly signed transaction within the time window
4. **Nonce Management**: Nonces are per-Safe and non-sequential

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Test with Verbosity

```bash
forge test -vvv
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

## Test Coverage

The project includes following tests:

- Basic ETH transfers
- ERC20 token transfers
- Time window enforcement (too early/expired)
- Replay protection
- Invalid signature rejection
- Cross-Safe signature isolation
- Module disable handling
- Safe configuration changes

## Foundry

This project uses **Foundry**, a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.

### Foundry Documentation

https://book.getfoundry.sh/
