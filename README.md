# V1 Punk Stash Contracts

Per-user escrow ("stash") contracts for CryptoPunks V1 trading (native **and** wrapped as ERC721) on the CryptoPunks.eth marketplace.

## Lineage

This codebase is a **fork of Yuga Labs' Stash system**, originally written by [0xQuit](https://x.com/0xQuit) for CryptoPunks V2. The original contracts are deployed on Ethereum mainnet:

| Original contract | Address |
|---|---|
| StashFactory | [`0x000000000000A6fA31F5fC51c1640aAc76866750`](https://etherscan.io/address/0x000000000000A6fA31F5fC51c1640aAc76866750#code) |
| ERC1967Factory | (deployed by the StashFactory constructor) |
| StashVerifier | (deployed by the StashFactory constructor) |

The original source is verified on Etherscan (Solidity 0.8.23, MIT license). The core architecture — per-user ERC1967 proxies deployed by a versioned factory, off-chain EIP-712 signed bids settled on-chain, account + bid nonce replay protection, Merkle proofs for collection bids — is entirely 0xQuit's design.

### What we changed

The fork adapts the system from CryptoPunks V2 to **CryptoPunks V1**, which requires handling both native V1 punks (non-ERC721) and wrapped V1 punks (standard ERC721 via WPV1). Here is the full delta:

**`V1PunkStash.sol`** (main contract — 96% of original code retained):

| Change | Description |
|---|---|
| Dual-path settlement | `processV1PunkBid` now handles two paths: **wrapped punks** bought through FrankPoncelet's WPV1 marketplace, and **native V1 punks** bought via `buyPunk`/`withdraw` (leveraging the V1 sale-proceeds bug for real-price recording). The original had a single direct `transferFrom` path. This is the bulk of the diff (+103 lines added, −27 removed). |
| WETH transfer hardening | `_swapWETH` uses `SafeTransferLib.safeTransferFrom` instead of unchecked `_WETH.transferFrom` (1 line) |
| `_isPunkWrapped` helper | New internal view to check if a punk is in wrapped state (6 lines) |
| Constructor args | Added `punksV1Contract` and `wrappedPunksMarketplace` immutables |
| Version bump | `_VERSION` changed from 1 → 4 (tracks mainnet deployment versions) |

**`V1PunkStashFactory.sol`**, **`V1PunkStashVerifier.sol`**: author header only (logic identical).

**`ERC1967Factory.sol`**: vendored unchanged from Yuga Labs' Solady fork (author header annotated).

**Unchanged files** (byte-identical to original): `Enum.sol`, `IWETH.sol`, `IAuction.sol`, `IERC721Wrapper.sol`, `IERC721TransferHelper.sol`.

**New files** (V1-specific, not in the original codebase):

| File | Lines | Purpose |
|---|---|---|
| `IWrappedPunksMarketplace.sol` | 32 | Interface for FrankPoncelet's WPV1 marketplace |
| `IWrappedPunksV1.sol` | 56 | Interface for the WPV1 ERC721 wrapper |
| `PunksV1Contract.sol` | 38 | Interface for the native CryptoPunks V1 contract |
| `PunksV1Wrapper.sol` | 89 | V1 punk wrapper interactions |

### Metrics

```
Original Yuga Labs codebase:  1,373 lines (core contracts + interfaces)
Current fork (excl. mocks):   1,662 lines

Core contract (V1PunkStash.sol):
  Original:  707 lines
  Current:   783 lines  (+76 net)
  Retained:  96.1% of original lines unchanged
  Delta:     +103 added, −27 removed (settlement paths rewritten for V1)

Supporting contracts (Factory, Verifier, ERC1967Factory):
  Changed:   author headers only (0 logic changes)

Helpers & interfaces carried over:
  5 files byte-identical to original

New V1-specific code:
  4 interface/wrapper files, 215 lines total
```

## Overview

The system handles both native CryptoPunks V1 (non-ERC721, using `transferPunk()` and the `buyPunk`/`withdraw` sale-proceeds pattern) and wrapped V1 punks (standard ERC721 via WPV1). Off-chain bids are signed as EIP-712 typed data and settled on-chain via `processV1PunkBid`.

## Project Structure

```
v1-punk-stash-contracts/
├── src/
│   ├── V1PunkStash.sol              # Main stash contract
│   ├── V1PunkStashFactory.sol       # Factory for deploying stash proxies
│   ├── V1PunkStashVerifier.sol      # Stash identity verification helper
│   ├── ERC1967Factory.sol           # ERC1967 proxy factory (vendored unchanged)
│   ├── PunksV1Wrapper.sol           # V1 punk wrapper interactions
│   ├── interfaces/
│   │   ├── IV1PunkStash.sol
│   │   ├── IV1PunkStashFactory.sol
│   │   ├── IWrappedPunksMarketplace.sol
│   │   ├── IWrappedPunksV1.sol
│   │   ├── PunksV1Contract.sol
│   │   ├── IERC721Wrapper.sol
│   │   ├── IERC721TransferHelper.sol
│   │   ├── IAuction.sol
│   │   └── IWETH.sol
│   ├── helpers/
│   │   ├── V1PunkStruct.sol         # Order and V1PunkBid structs
│   │   └── Enum.sol                 # OrderType enum
│   └── mocks/                       # Test mocks (out of audit scope)
├── test/
│   └── V1PunkStash.t.sol
├── script/
│   └── DeployV1PunkStashFactory.s.sol
├── foundry.toml
└── AUDIT_SCOPE.md
```

## Build & Test

```bash
forge build
forge test
```

Dependencies are vendored in `lib/` (forge-std, OpenZeppelin v4.4.0, Solady v0.1.26).

## License

MIT
