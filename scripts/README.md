# Deployment scripts

## Full deployment script

The `deploy-and-verify.sh` script deploys and automatically verifies all required contracts on Sepolia.

### Prerequisites

1. **Required environment variables** (in `.env` or exported):
   ```bash
   SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
   PRIVATE_KEY=your_private_key_without_0x
   DEPLOYER_ADDRESS=0xYourDeployerAddress
   ETHERSCAN_API_KEY=your_etherscan_api_key
   WETH_ADDRESS=0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14
   ```

2. **Foundry installed**: `forge` must be available in PATH

3. **Account with Sepolia ETH**: Your account must have enough ETH for gas

### Usage

```bash
# From the project root
./scripts/deploy-and-verify.sh
```

### What the script does

1. **Checks required environment variables**
2. **Deploys MockPunksV1** (mock of the V1 Punks contract for Sepolia)
3. **Deploys PunksV1Wrapper** (ERC721 wrapper for V1 Punks)
4. **Verifies MockPunksV1** on Etherscan
5. **Verifies PunksV1Wrapper** on Etherscan
6. **Deploys V1PunkStashFactory** (factory for creating stashes)
7. **Deploys V1PunkStash Implementation** (stash implementation)
8. **Verifies V1PunkStashFactory** on Etherscan
9. **Verifies V1PunkStash Implementation** on Etherscan
10. **Saves all addresses** in `deployed_addresses_sepolia.json`

### Output

The script generates a `deployed_addresses_sepolia.json` file with all deployed addresses and Etherscan links.

### Re-running

The script is **idempotent** and can be re-run. If a contract is already deployed, you can:
- Use the existing addresses from `deployed_addresses_sepolia.json`
- Or let the script redeploy (this will create new addresses)

### Troubleshooting

If verification fails:
- Check that your Etherscan API key is valid
- Wait a few seconds after deployment before verification
- Verify that the source code matches the deployed code exactly
