# Deployment guide (Sepolia)

## Prerequisites

1. An account with Sepolia ETH (get some from [Sepolia Faucet](https://sepoliafaucet.com/))
2. Environment variables configured

## Environment variables

Create a `.env` file at the project root with the following variables:

```bash
# Sepolia RPC (Alchemy, Infura, or other)
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
# or
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY

# Deployer private key (without the 0x prefix)
PRIVATE_KEY=your_private_key_here

# Deployer address (must match the private key)
DEPLOYER_ADDRESS=0xYourDeployerAddress

# Contract addresses on Sepolia
WETH_ADDRESS=0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14  # WETH Sepolia
WRAPPED_PUNKS_V1_ADDRESS=0xYourWPV1Address  # WPV1 (Wrapped Punks V1) contract address
# Mainnet WPV1: 0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d
# For Sepolia, you need to deploy a new WPV1 instance
```

## Common Sepolia addresses

### WETH Sepolia
```
0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
```

### WPV1 (Wrapped Punks V1)
**Mainnet**: `0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d`

For Sepolia, you need to deploy a new WPV1 instance. The WPV1 contract is a standard ERC721 that wraps V1 punks.

## Address explanation

### WRAPPED_PUNKS_V1_ADDRESS
This is the address of the **WPV1 (Wrapped Punks V1)** contract which:
- Is a standard ERC721 contract
- Wraps non-ERC721 V1 punks into ERC721 tokens
- Allows wrapping/unwrapping via `wrap()` and `unwrap()` functions
- **Replaces both** `ERC721_TOKEN_ADDRESS` and `ERC721_WRAPPER_ADDRESS`

**Why this simplification?**
- Original V1 punks are not ERC721 (they use `transferPunk()`)
- WPV1 converts them to standard ERC721
- In the V1PunkStash context, we work with both native V1 punks (via `buyPunk`/`withdraw`) and ERC721 tokens (wrapped)
- No need for a separate TransferHelper as we use the ERC721 standard (`transferFrom`)

## Deployment

### 1. Deploy WPV1 (if needed)

If you don't yet have a WPV1 contract on Sepolia, you must deploy one first:

#### Option 1: Deploy with Mock Punks V1 (Recommended for Sepolia)

On Sepolia, the original Punks V1 contract does not exist. You must deploy a mock:

```bash
# Deploy mock Punks V1 and wrapper in a single command
export DEPLOY_MOCK_PUNKS_V1=true
forge script script/DeployWPV1.s.sol:DeployWPV1 \
  --rpc-url sepolia \
  --broadcast \
  -vvvv
```

This command will:
1. Deploy a `MockPunksV1` (simulation of the Punks V1 contract)
2. Deploy `PunksV1Wrapper` with the mock's address

#### Option 2: Use an existing address

If you already have a Punks V1 contract on Sepolia:

```bash
export PUNKS_V1_ADDRESS=0xYourPunksV1Address
forge script script/DeployWPV1.s.sol:DeployWPV1 \
  --rpc-url sepolia \
  --broadcast \
  -vvvv
```

#### Option 3: Use the mainnet address (for mainnet only)

```bash
# For mainnet, use the existing address
export PUNKS_V1_ADDRESS=0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D
forge script script/DeployWPV1.s.sol:DeployWPV1 \
  --rpc-url mainnet \
  --broadcast \
  -vvvv
```

**Note**: The WPV1 contract source code was retrieved from Etherscan (https://etherscan.io/address/0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d#code) and adapted for OpenZeppelin v4.4.0.

### 2. Verify configuration

```bash
# Check that variables are loaded
source .env
echo $SEPOLIA_RPC_URL
echo $PRIVATE_KEY
echo $WRAPPED_PUNKS_V1_ADDRESS
```

### 3. Deploy the Factory and implementation

```bash
forge script script/DeployV1PunkStashFactory.s.sol:DeployV1PunkStashFactory \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  -vvvv
```

**Without Etherscan verification** (if you don't have an API key):

```bash
forge script script/DeployV1PunkStashFactory.s.sol:DeployV1PunkStashFactory \
  --rpc-url sepolia \
  --broadcast \
  -vvvv
```

### 4. Verify deployed contracts (optional)

If you have an Etherscan API key, you can verify the contracts:

```bash
forge verify-contract \
  <FACTORY_ADDRESS> \
  src/V1PunkStashFactory.sol:V1PunkStashFactory \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY

forge verify-contract \
  <IMPLEMENTATION_ADDRESS> \
  src/V1PunkStash.sol:V1PunkStash \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" <FACTORY_ADDRESS> <WETH_ADDRESS> <ERC721_TOKEN_ADDRESS> <ERC721_WRAPPER_ADDRESS> <ERC721_TRANSFER_HELPER_ADDRESS>)
```

## Full example

```bash
# 1. Go to the project directory
cd v1-punk-stash-contracts

# 2. Load environment variables
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="your_private_key"
export DEPLOYER_ADDRESS="0xYourAddress"
export WETH_ADDRESS="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
export WRAPPED_PUNKS_V1_ADDRESS="0xYourWPV1Address"

# 3. Deploy
forge script script/DeployV1PunkStashFactory.s.sol:DeployV1PunkStashFactory \
  --rpc-url sepolia \
  --broadcast \
  -vvvv
```

## Expected output

After deployment, you should see in the console:

```
V1PunkStashFactory deployed at 0x...
V1PunkStashVerifier deployed at 0x...
V1PunkStash implementation (v1) deployed at 0x...
```

Addresses will also be saved in `broadcast/DeployV1PunkStashFactory.s.sol/11155111/run-latest.json`

## Etherscan verification

1. Go to [Sepolia Etherscan](https://sepolia.etherscan.io/)
2. Search for the Factory address
3. Verify the contract is properly deployed and verified

## Next steps

After deployment:

1. **Save addresses** in a `deployed_addresses.json` file:
```json
{
  "sepolia": {
    "V1PunkStashFactory": "0x...",
    "V1PunkStashVerifier": "0x...",
    "V1PunkStashImplementation": "0x..."
  }
}
```

2. **Configure auctions** by calling `setAuction()` on the Factory for each valid auction

3. **Test the deployment** by deploying a Stash for a test user:
```solidity
V1PunkStashFactory factory = V1PunkStashFactory(0x...);
factory.deployStash(0xTestUserAddress);
```

## V1PunkStash implementation upgrades (mainnet / production)

When a new `V1PunkStash` implementation is released (e.g. `version()` bumps from 1 to 2), the factory enforces sequential versions via `addVersion`:

1. **Deploy** the new implementation contract (immutable constructor args unchanged: factory, WETH, WPV1, Punks V1).
2. **Register** it on the factory with an account that has the version-manager role: `addVersion(newImplementation)`. The implementation's `version()` must equal `factory.currentVersion() + 1` after the increment inside `addVersion`.
3. **New stashes** created with `deployStash(owner)` use `implementations[currentVersion]` (the latest registered version).
4. **Existing stashes** (ERC1967 proxies at `stashAddressFor(owner)`) must call **`upgradeStash()`** from the stash **owner** EOA (`msg.sender` must be that owner). That upgrades the proxy to `implementations[currentVersion]`. It reverts with `AlreadyOnCurrentVersion` if the proxy already points at the latest implementation.

Operational notes:

- Coordinate with users after an upgrade: behavior changes (e.g. unwrapped V1 acceptance now delivers **native** V1 custody to the bidder via `transferPunk` instead of auto-wrapping to WPV1) should be communicated before they accept bids.
- After `addVersion`, `currentVersion` is the new number; every `upgradeStash()` pulls that implementation until a newer version is added again.

### Production factory (mainnet)

Factory: `0x25d136deEBE7C07C2B9A933924aB4BA419027F37` (matches frontend `stashFactoryAddress`).

**1) Register a new implementation** (wallet with factory version-manager role):

```bash
export STASH_FACTORY=0x25d136deEBE7C07C2B9A933924aB4BA419027F37
export PRIVATE_KEY=<version_manager_private_key>
export MAINNET_RPC_URL=<your_mainnet_https_url>
forge script script/AddStashImplementationToFactory.s.sol:AddStashImplementationToFactory \
  --rpc-url "$MAINNET_RPC_URL" \
  --broadcast \
  -vvvv
```

On mainnet, WETH / WPV1 / Punks V1 defaults are baked into the script; override with `WETH_ADDRESS`, `WRAPPED_PUNKS_V1_ADDRESS`, `PUNKS_V1_ADDRESS` if needed.

**2) Upgrade your stash proxy** (wallet must be the **stash owner** — same address as `deployStash` / bid owner):

```bash
export STASH_FACTORY=0x25d136deEBE7C07C2B9A933924aB4BA419027F37
export PRIVATE_KEY=<stash_owner_private_key>
export MAINNET_RPC_URL=<your_mainnet_https_url>
forge script script/UpgradeStashViaFactory.s.sol:UpgradeStashViaFactory \
  --rpc-url "$MAINNET_RPC_URL" \
  --broadcast \
  -vvvv
```

Alternatively, from the owner wallet, call `upgradeStash()` on the factory via Etherscan "Write contract" or `cast send`.

### Verify the implementation on Etherscan (after each `addVersion`)

The address to verify is **`implementations(factory.currentVersion())`**, not the factory and not user stash proxies. Example (as of a v2 deploy): `0x552be4dA31eE8F81eEDd0055dBe9FF9C16575312`. If Etherscan still shows "Verify and Publish", the deploy never ran verification (normal for `forge script --broadcast` without `--verify`).

From the project root (same constructor args as `AddStashImplementationToFactory.s.sol` on mainnet):

```bash
export ETHERSCAN_API_KEY=<your_etherscan_api_key>

forge verify-contract \
  0x552be4dA31eE8F81eEDd0055dBe9FF9C16575312 \
  src/V1PunkStash.sol:V1PunkStash \
  --chain mainnet \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args $(cast abi-encode \
    "constructor(address,address,address,address)" \
    0x25d136deEBE7C07C2B9A933924aB4BA419027F37 \
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
    0x282BDD42f4eb70e7A9D9F40c8fEA0825B7f68C5D \
    0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D) \
  --watch
```

Replace the first address with the output of `cast call … implementations(N)` if you add v3 later. If verification fails, compare **compiler 0.8.23** and **optimizer** settings to your local `forge build` (Etherscan often suggests the exact flags).
