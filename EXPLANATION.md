# Address architecture and simplification

## Differences between versions (original vs simplified)

### Original version (CryptoPunks V2)

In the original Stash for CryptoPunks V2, there were 3 distinct addresses:

1. **`ERC721_TOKEN_ADDRESS`**: The original CryptoPunks contract (non-ERC721)
   - Uses `transferPunk()` instead of `transferFrom()`
   - Not an ERC721 standard

2. **`ERC721_WRAPPER_ADDRESS`**: The contract that wraps punks into ERC721
   - Example: `ICryptoPunks721` for V2 punks
   - Converts non-ERC721 punks into ERC721 tokens

3. **`ERC721_TRANSFER_HELPER_ADDRESS`**: A helper for transferring wrapped tokens
   - Required because wrapped punks need special verification
   - Checks that the caller is the owner before transferring

### Simplified version (Punks V1 with WPV1)

For V1 punks, we use the **WPV1 (Wrapped Punks V1)** contract which is a **standard ERC721**. This greatly simplifies the architecture:

1. **`WRAPPED_PUNKS_V1_ADDRESS`**: The WPV1 contract (replaces the 3 previous addresses)
   - **Is a standard ERC721**: uses `transferFrom()` like any ERC721
   - **Acts as a wrapper**: has `wrap()` and `unwrap()` functions
   - **No TransferHelper needed**: uses standard ERC721 `transferFrom()` directly

## Why this simplification?

### Advantages

1. **ERC721 standard**: WPV1 is a standard ERC721 contract, so:
   - Compatible with all ERC721 marketplaces (OpenSea, Blur, etc.)
   - Uses standard methods (`transferFrom`, `approve`, etc.)
   - No special logic needed

2. **Fewer dependencies**:
   - Before: 3 contracts (Token + Wrapper + TransferHelper)
   - Now: 1 contract (WPV1)

3. **Easier to maintain**:
   - Less code to manage
   - Fewer points of failure
   - Clearer logic

### How it works

```
┌─────────────────────────────────────────────────────────┐
│                    Punks V1 Original                     │
│  (Non-ERC721, uses transferPunk())                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ wrap()
                     ▼
┌─────────────────────────────────────────────────────────┐
│              WPV1 (Wrapped Punks V1)                     │
│  ✅ ERC721 Standard                                      │
│  ✅ Standard transferFrom()                              │
│  ✅ wrap() / unwrap()                                    │
│  Mainnet: 0x282BDD42f4eb70e7A9D9F40c8fEA0825B7f68C5D    │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ transferFrom() (standard ERC721)
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  V1PunkStash                             │
│  Handles tokens as any standard ERC721                   │
└─────────────────────────────────────────────────────────┘
```

## Deployment on Sepolia

### Step 1: Deploy WPV1 (if needed)

The WPV1 contract must be deployed on Sepolia. You need:
- The WPV1 contract source code
- The address of the original Punks V1 contract on Sepolia

```bash
# Deploy WPV1
forge script script/DeployWPV1.s.sol:DeployWPV1 --rpc-url sepolia --broadcast
```

### Step 2: Use the deployed WPV1 address

Once WPV1 is deployed, use its address in your `.env`:

```bash
WRAPPED_PUNKS_V1_ADDRESS=0xYourDeployedWPV1Address
```

### Step 3: Deploy V1PunkStashFactory

```bash
forge script script/DeployV1PunkStashFactory.s.sol:DeployV1PunkStashFactory \
  --rpc-url sepolia \
  --broadcast
```

## Summary

| Concept | Original version | Simplified version |
|---------|-------------------|---------------------|
| Token | CryptoPunks (non-ERC721) | WPV1 (standard ERC721) |
| Wrapper | Separate contract | Built into WPV1 |
| TransferHelper | Required | Not needed (standard ERC721) |
| Number of addresses | 3 | 1 |
| Complexity | High | Low |

**Conclusion**: By using WPV1 which is a standard ERC721, the architecture is greatly simplified and the need for a separate TransferHelper is eliminated.
