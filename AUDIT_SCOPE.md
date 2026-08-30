# Audit Scope — Punk Stash Contracts (CryptoPunks.eth Marketplace)

## Snapshot

- **Repository commit**: `3ee5b1c9fca2606df54a285f095021bc3083f393` (branch `feature/ai_audit-quickwins`, 2026-08-28)
- **Toolchain**: Foundry (forge 1.7.1), solc **0.8.23** (pinned in `foundry.toml`)
- **Dependencies**: vendored in `lib/`, pinned via `foundry.lock`
  - forge-std `v1.12.0` (`7117c90`) — test-only
  - openzeppelin-contracts `v4.4.0` (`4961a51`)
  - solady `v0.1.26` (`acd959a`)
- **Build / test**: `forge build && forge test` — 15/15 tests passing at packaging time, `forge lint` clean of `erc20-unchecked-transfer`. The package is self-contained (no `forge install` needed).

### Delta vs. deployed code

This snapshot includes two pre-audit changes that are **not yet deployed**:

1. **WETH transfer hardening**: `V1PunkStash._swapWETH` now uses `SafeTransferLib.safeTransferFrom` for the owner WETH pull (the deployed implementation V4 uses an unchecked `_WETH.transferFrom`; behaviorally equivalent with canonical WETH9, which reverts on failure).
2. **Naming**: contracts, structs, events and functions renamed from `ERC721Stash`/`ERC721Bid` to `V1PunkStash`/`V1PunkBid` to accurately reflect that the system handles both native V1 punks (non-ERC721) and wrapped V1 punks (ERC721). This is a source-level rename only — the deployed V4 bytecode still uses the `ERC721*` names.

Both changes will ship with the next implementation version.

## System overview

Per-user escrow ("stash") contracts for an off-chain orderbook with on-chain settlement, used by the CryptoPunks.eth marketplace to trade CryptoPunks V1 (native and wrapped). Each user deploys a personal `V1PunkStash` as an ERC1967 proxy through `V1PunkStashFactory`, which maintains a versioned registry of implementations. Bids are signed off-chain as EIP-712 typed data and settled on-chain via `processV1PunkBid` (ETH/WETH payment), with account-level and bid-level nonces for replay protection and Merkle proofs for multi-token bids. See `README.md`, `EXPLANATION.md` and `confidential-bids-technical-implementation.md` for the full architecture (off-chain orderbook, JWT auth, confidential bids).

## In scope

| File | LOC | Description |
|---|---|---|
| `src/V1PunkStash.sol` | ~783 | Main per-user stash: order placement, EIP-712 bid settlement (`processV1PunkBid`), native V1 punk purchase at real price, wrap/unwrap flows, WETH/ETH handling |
| `src/V1PunkStashFactory.sol` | ~215 | Proxy deployment, implementation versioning/registry, auction registry |
| `src/ERC1967Factory.sol` | ~303 | ERC1967 proxy factory (Yuga Labs' Solady fork, vendored unchanged) |
| `src/V1PunkStashVerifier.sol` | ~50 | Stash identity verification helper |
| `src/PunksV1Wrapper.sol` | ~89 | V1 punk wrapper interactions |
| `src/helpers/` | 32 | `Order` / `V1PunkBid` structs, `OrderType` enum |
| `src/interfaces/` | 190 | Interfaces (V1 punks, wrapper, WPV1 marketplace, WETH, auction, transfer helper) |

**Total in scope: ~1,660 LOC** (including interfaces).

## Out of scope

- `src/mocks/`, `test/` (mocks and Foundry test suite — provided for context/repro only)
- `script/`, `scripts/` (deployment scripts)
- `lib/` (vendored third-party dependencies)
- Off-chain components (indexer/orderbook backend, frontend)

## Trust assumptions (by design — please challenge them)

1. **Registered auctions are highly trusted.** An auction address flagged by the factory (`setAuction`) can pull committed order funds from a stash via `processOrder` (bounded by the order's `numberOfUnits × pricePerUnit`). `bidConfig()` is re-queried at read time, so a malicious registered auction that mutates its payment token could distort lock accounting. Auction registration is owner/role-gated on the factory.
2. **Bids with `expiration == 0` never expire** until explicitly canceled (`cancelV1PunkBid` / `cancelAllV1PunkBids`). Combined with a standing owner WETH allowance to the stash, a signed collection bid authorizes pulling the owner's wallet WETH at settlement time (`_swapWETH`). This is intentional (the off-chain orderbook and frontend manage expirations) but is a key economic surface.
3. **Bid-nonce use accounting is keyed by nonce only** (`v1PunkBidNonceUsesRemaining[bidNonce]`). Two different signed bids sharing a nonce share one use budget, at either bid's price. Nonce uniqueness is guaranteed by the off-chain orderbook backend.
4. **`tx.origin`-based authorization** is used in `placeOrder` (stash owner must originate the tx; the caller must be a registered auction) and for the factory's initial owner. This is deliberate but excludes smart-contract wallets (ERC-4337 / Safe) from those paths.
5. **External dependencies**: the native CryptoPunks V1 contract (including its known sale-proceeds bug, deliberately leveraged and documented in `processV1PunkBid`), the WPV1 wrapper, and FrankPoncelet's WPV1 marketplace (`0x759c…03CE`) are trusted as deployed, immutable dependencies.
6. **CREATE2 salt** in `V1PunkStashFactory._salt` is a fixed vanity phrase baked into the deployed factory; it is address-derivation-critical and intentionally unchanged.

## Deployed contracts (Ethereum mainnet)

See `deployed_addresses_mainnet.json`. Current live implementation is **V4** (`0xc0a3425a2801EcDAe9c022559e4A6A52B8949df7`), registered in factory `0x25d136deEBE7C07C2B9A933924aB4BA419027F37`. V4 routes wrapped punk sales through the WPV1 marketplace (`0x759c6C1923910930C18ef490B3c3DbeFf24003cE`) and settles native V1 punks at the real sale price (`buyPunk` at bid price + withdraw).

## Suggested focus areas

1. **Signature settlement path** — EIP-712 domain/struct hashing (note: domain uses only `chainId` + `verifyingContract`), account vs bid nonce replay protection, Merkle proof validation for multi-token bids, expiration handling.
2. **Funds flows** — WETH pulls, native ETH from V1 `buyPunk`/`withdraw`, refund paths, reentrancy across external calls to the V1 punks contract, wrapper and WPV1 marketplace (no reentrancy guard; CEI is relied upon).
3. **Upgradeability & trust model** — factory-controlled implementation registry, ERC1967 proxy initialization, storage layout compatibility across implementation versions V1→V4, who can upgrade a user's stash and to what.
4. **Access control** — stash owner vs factory vs arbitrary callers on every external entry point.
5. **Wrap/unwrap flows** — token custody invariants when moving between native V1 punks and wrapped (ERC721) representation.

## Contact

tat2bu — @tat2bu on Telegram
