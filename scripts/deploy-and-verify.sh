#!/bin/bash

# Full script to deploy and verify all contracts on Sepolia or Mainnet
# Usage: ./scripts/deploy-and-verify.sh [mainnet|sepolia]
# If no argument is provided, the network is detected automatically from environment variables

set -e  # Stop on error

# Colors for messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Message display functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check that we are in the correct directory
if [ ! -f "foundry.toml" ]; then
    error "This script must be run from the project root"
    exit 1
fi

# Load base environment variables
if [ -f .env ]; then
    info "Loading environment variables from .env"
    set -a
    source .env
    set +a
else
    warning ".env file not found. Make sure variables are exported."
fi

# Detect network (argument or environment variable)
if [ "$1" = "mainnet" ] || [ "$1" = "sepolia" ]; then
    NETWORK="$1"
elif [ ! -z "$MAINNET_RPC_URL" ] && [ -z "$SEPOLIA_RPC_URL" ]; then
    NETWORK="mainnet"
    info "Network detected: mainnet (via MAINNET_RPC_URL)"
elif [ ! -z "$SEPOLIA_RPC_URL" ] && [ -z "$MAINNET_RPC_URL" ]; then
    NETWORK="sepolia"
    info "Network detected: sepolia (via SEPOLIA_RPC_URL)"
elif [ ! -z "$MAINNET_RPC_URL" ]; then
    NETWORK="mainnet"
    info "Default network: mainnet (MAINNET_RPC_URL found)"
else
    NETWORK="sepolia"
    info "Default network: sepolia"
fi

# Load network-specific variables if on testnet
if [ "$NETWORK" = "sepolia" ] && [ -f .env.sepolia ]; then
    info "Loading environment variables from .env.sepolia"
    set -a
    source .env.sepolia
    set +a
fi

# Network configuration
if [ "$NETWORK" = "mainnet" ]; then
    CHAIN_ID=1
    RPC_URL="${MAINNET_RPC_URL}"
    ETHERSCAN_BASE_URL="https://etherscan.io"
    MAINNET_WPV1_ADDRESS="0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d"
    DEPLOY_MOCK_PUNKS_V1=false
    REQUIRED_VARS=("PRIVATE_KEY" "DEPLOYER_ADDRESS" "ETHERSCAN_API_KEY" "WETH_ADDRESS" "MAINNET_RPC_URL")
else
    CHAIN_ID=11155111
    RPC_URL="${SEPOLIA_RPC_URL}"
    ETHERSCAN_BASE_URL="https://sepolia.etherscan.io"
    DEPLOY_MOCK_PUNKS_V1=true
    REQUIRED_VARS=("PRIVATE_KEY" "DEPLOYER_ADDRESS" "ETHERSCAN_API_KEY" "WETH_ADDRESS" "SEPOLIA_RPC_URL")
fi

# Check required variables
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    error "Missing environment variables: ${MISSING_VARS[*]}"
    exit 1
fi

info "Environment variables verified ✓"

# File to save deployed addresses
DEPLOYED_ADDRESSES_FILE="deployed_addresses_${NETWORK}.json"

info "=========================================="
info "Deploying and verifying contracts"
info "Network: $NETWORK (Chain ID: $CHAIN_ID)"
info "=========================================="
echo ""

# ============================================
# STEP 1: Deploy MockPunksV1 and PunksV1Wrapper (Sepolia only)
# ============================================
if [ "$NETWORK" = "sepolia" ]; then
    info "STEP 1: Deploying MockPunksV1 and PunksV1Wrapper (Sepolia only)"

    export DEPLOY_MOCK_PUNKS_V1=true

    DEPLOY_OUTPUT=$(forge script script/DeployWPV1.s.sol:DeployWPV1 \
        --rpc-url $RPC_URL \
        --broadcast \
        --sender $DEPLOYER_ADDRESS \
        --private-key $PRIVATE_KEY \
        -vvv 2>&1)

    # Extract addresses from output (macOS/BSD compatible)
    MOCK_PUNKS_V1_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "MockPunksV1 deployed at" | sed -nE 's/.*MockPunksV1 deployed at (0x[0-9a-fA-F]{40}).*/\1/p' | head -1)
    PUNKS_V1_WRAPPER_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "PunksV1Wrapper deployed at" | sed -nE 's/.*PunksV1Wrapper deployed at (0x[0-9a-fA-F]{40}).*/\1/p' | head -1)

    # If extraction fails, try from JSON logs
    if [ -z "$MOCK_PUNKS_V1_ADDRESS" ] || [ -z "$PUNKS_V1_WRAPPER_ADDRESS" ]; then
        info "Attempting extraction from JSON files..."
        BROADCAST_FILE="broadcast/DeployWPV1.s.sol/$CHAIN_ID/run-latest.json"
        if [ -f "$BROADCAST_FILE" ]; then
            if command -v jq &> /dev/null; then
                MOCK_PUNKS_V1_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "MockPunksV1") | .contractAddress' "$BROADCAST_FILE" | head -1)
                PUNKS_V1_WRAPPER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "PunksV1Wrapper") | .contractAddress' "$BROADCAST_FILE" | head -1)
            fi
        fi
    fi

    if [ -z "$MOCK_PUNKS_V1_ADDRESS" ] || [ -z "$PUNKS_V1_WRAPPER_ADDRESS" ]; then
        error "Could not extract deployed contract addresses"
        echo "$DEPLOY_OUTPUT"
        exit 1
    fi

    success "MockPunksV1 deployed at: $MOCK_PUNKS_V1_ADDRESS"
    success "PunksV1Wrapper deployed at: $PUNKS_V1_WRAPPER_ADDRESS"
    echo ""

    # Export PUNKS_V1_ADDRESS for the next deployment script
    export PUNKS_V1_ADDRESS=$MOCK_PUNKS_V1_ADDRESS

    # Wait for transaction confirmations
    info "Waiting for transaction confirmations (10 seconds)..."
    sleep 10

    # ============================================
    # STEP 2: Verify MockPunksV1 on Etherscan
    # ============================================
    info "STEP 2: Verifying MockPunksV1 on Etherscan"

    VERIFY_MOCK=$(forge verify-contract \
        $MOCK_PUNKS_V1_ADDRESS \
        src/mocks/MockPunksV1.sol:MockPunksV1 \
        --chain-id $CHAIN_ID \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --watch 2>&1)

    if echo "$VERIFY_MOCK" | grep -q "OK"; then
        success "MockPunksV1 verified on Etherscan ✓"
    else
        warning "MockPunksV1 verification failed (may already be verified)"
        echo "$VERIFY_MOCK"
    fi
    echo ""

    # ============================================
    # STEP 3: Verify PunksV1Wrapper on Etherscan
    # ============================================
    info "STEP 3: Verifying PunksV1Wrapper on Etherscan"

    # Encode constructor argument
    CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" $MOCK_PUNKS_V1_ADDRESS)

    VERIFY_WRAPPER=$(forge verify-contract \
        $PUNKS_V1_WRAPPER_ADDRESS \
        src/PunksV1Wrapper.sol:PunksV1Wrapper \
        --chain-id $CHAIN_ID \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --constructor-args $CONSTRUCTOR_ARGS \
        --watch 2>&1)

    if echo "$VERIFY_WRAPPER" | grep -q "OK"; then
        success "PunksV1Wrapper verified on Etherscan ✓"
    else
        warning "PunksV1Wrapper verification failed (may already be verified)"
        echo "$VERIFY_WRAPPER"
    fi
    echo ""
else
    # On mainnet, use existing WPV1 address or one provided via environment
    info "STEP 1: Using existing WPV1 on Mainnet"
    if [ ! -z "$WRAPPED_PUNKS_V1_ADDRESS" ]; then
        PUNKS_V1_WRAPPER_ADDRESS="$WRAPPED_PUNKS_V1_ADDRESS"
        info "Using WRAPPED_PUNKS_V1_ADDRESS from environment"
    else
        PUNKS_V1_WRAPPER_ADDRESS="$MAINNET_WPV1_ADDRESS"
        info "Using default mainnet WPV1 address"
    fi
    MOCK_PUNKS_V1_ADDRESS=""
    success "Using WPV1 at: $PUNKS_V1_WRAPPER_ADDRESS"
    echo ""
fi

# ============================================
# STEP 4: Deploy V1PunkStashFactory
# ============================================
STEP_NUMBER=$([ "$NETWORK" = "mainnet" ] && echo "2" || echo "4")
info "STEP $STEP_NUMBER: Deploying V1PunkStashFactory"

# Export wrapper address for the deployment script
export WRAPPED_PUNKS_V1_ADDRESS=$PUNKS_V1_WRAPPER_ADDRESS

DEPLOY_FACTORY_OUTPUT=$(forge script script/DeployV1PunkStashFactory.s.sol:DeployV1PunkStashFactory \
    --rpc-url $RPC_URL \
    --broadcast \
    --sender $DEPLOYER_ADDRESS \
    --private-key $PRIVATE_KEY \
    -vvv 2>&1)

# Extract addresses from output (macOS/BSD compatible)
FACTORY_ADDRESS=$(echo "$DEPLOY_FACTORY_OUTPUT" | grep "V1PunkStashFactory deployed at" | sed -nE 's/.*V1PunkStashFactory deployed at (0x[0-9a-fA-F]{40}).*/\1/p' | head -1)
VERIFIER_ADDRESS=$(echo "$DEPLOY_FACTORY_OUTPUT" | grep "V1PunkStashVerifier deployed at" | sed -nE 's/.*V1PunkStashVerifier deployed at (0x[0-9a-fA-F]{40}).*/\1/p' | head -1)
IMPLEMENTATION_ADDRESS=$(echo "$DEPLOY_FACTORY_OUTPUT" | grep "V1PunkStash implementation.*deployed at" | sed -nE 's/.*V1PunkStash implementation.*deployed at (0x[0-9a-fA-F]{40}).*/\1/p' | head -1)

# If extraction fails, try from JSON logs
if [ -z "$FACTORY_ADDRESS" ]; then
    info "Attempting extraction from JSON files..."
    BROADCAST_FILE="broadcast/DeployV1PunkStashFactory.s.sol/$CHAIN_ID/run-latest.json"
    if [ -f "$BROADCAST_FILE" ]; then
        if command -v jq &> /dev/null; then
            FACTORY_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "V1PunkStashFactory") | .contractAddress' "$BROADCAST_FILE" | head -1)
            IMPLEMENTATION_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "V1PunkStash") | .contractAddress' "$BROADCAST_FILE" | head -1)
        fi
    fi
fi

if [ -z "$FACTORY_ADDRESS" ]; then
    error "Could not extract Factory address"
    echo "$DEPLOY_FACTORY_OUTPUT"
    exit 1
fi

success "V1PunkStashFactory deployed at: $FACTORY_ADDRESS"
if [ ! -z "$VERIFIER_ADDRESS" ]; then
    success "V1PunkStashVerifier deployed at: $VERIFIER_ADDRESS"
fi
if [ ! -z "$IMPLEMENTATION_ADDRESS" ]; then
    success "V1PunkStash implementation deployed at: $IMPLEMENTATION_ADDRESS"
fi
echo ""

# Wait for transaction confirmations
info "Waiting for transaction confirmations (10 seconds)..."
sleep 10

# ============================================
# STEP 5/3: Verify V1PunkStashFactory on Etherscan
# ============================================
STEP_NUMBER=$([ "$NETWORK" = "mainnet" ] && echo "3" || echo "5")
info "STEP $STEP_NUMBER: Verifying V1PunkStashFactory on Etherscan"

# The Factory is deployed with address(0) as initial implementation
# then the implementation is added via addVersion
CONSTRUCTOR_ARGS_FACTORY=$(cast abi-encode "constructor(address)" "0x0000000000000000000000000000000000000000")

VERIFY_FACTORY=$(forge verify-contract \
    $FACTORY_ADDRESS \
    src/V1PunkStashFactory.sol:V1PunkStashFactory \
    --chain-id $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $CONSTRUCTOR_ARGS_FACTORY \
    --watch 2>&1)

if echo "$VERIFY_FACTORY" | grep -q "OK"; then
    success "V1PunkStashFactory verified on Etherscan ✓"
else
    warning "V1PunkStashFactory verification failed (may already be verified)"
    echo "$VERIFY_FACTORY"
fi
echo ""

# ============================================
# STEP 6/4: Verify V1PunkStash Implementation (if deployed)
# ============================================
if [ ! -z "$IMPLEMENTATION_ADDRESS" ]; then
    STEP_NUMBER=$([ "$NETWORK" = "mainnet" ] && echo "4" || echo "6")
    info "STEP $STEP_NUMBER: Verifying V1PunkStash Implementation on Etherscan"

    # Encode V1PunkStash constructor arguments
    # constructor(address stashFactory, address weth, address erc721Token, address wrappedPunksV1)
    # Note: wrappedPunksV1 is used as both erc721Token and wrapper
    CONSTRUCTOR_ARGS_IMPL=$(cast abi-encode "constructor(address,address,address)" \
        $FACTORY_ADDRESS \
        $WETH_ADDRESS \
        $PUNKS_V1_WRAPPER_ADDRESS)

    VERIFY_IMPL=$(forge verify-contract \
        $IMPLEMENTATION_ADDRESS \
        src/V1PunkStash.sol:V1PunkStash \
        --chain-id $CHAIN_ID \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --constructor-args $CONSTRUCTOR_ARGS_IMPL \
        --watch 2>&1)

    if echo "$VERIFY_IMPL" | grep -q "OK"; then
        success "V1PunkStash Implementation verified on Etherscan ✓"
    else
        warning "V1PunkStash Implementation verification failed (may already be verified)"
        echo "$VERIFY_IMPL"
    fi
    echo ""
fi

# ============================================
# STEP 7/5: Save addresses
# ============================================
STEP_NUMBER=$([ "$NETWORK" = "mainnet" ] && echo "5" || echo "7")
info "STEP $STEP_NUMBER: Saving deployed addresses"

# Build JSON with jq if available, otherwise use a simple method
if command -v jq &> /dev/null; then
    JSON_OBJECT=$(jq -n \
        --arg network "$NETWORK" \
        --arg chainId "$CHAIN_ID" \
        --arg deployedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg wpv1Address "$PUNKS_V1_WRAPPER_ADDRESS" \
        --arg wpv1Etherscan "$ETHERSCAN_BASE_URL/address/$PUNKS_V1_WRAPPER_ADDRESS" \
        --arg wpv1Note "$([ "$NETWORK" = "mainnet" ] && echo "Existing contract" || echo "Deployed")" \
        --arg factoryAddress "$FACTORY_ADDRESS" \
        --arg factoryEtherscan "$ETHERSCAN_BASE_URL/address/$FACTORY_ADDRESS" \
        --arg verifierAddress "$VERIFIER_ADDRESS" \
        --arg verifierEtherscan "$ETHERSCAN_BASE_URL/address/$VERIFIER_ADDRESS" \
        --arg implAddress "$IMPLEMENTATION_ADDRESS" \
        --arg implEtherscan "$ETHERSCAN_BASE_URL/address/$IMPLEMENTATION_ADDRESS" \
        --arg wethAddress "$WETH_ADDRESS" \
        --arg deployerAddress "$DEPLOYER_ADDRESS" \
        --arg mockAddress "$MOCK_PUNKS_V1_ADDRESS" \
        --arg mockEtherscan "$ETHERSCAN_BASE_URL/address/$MOCK_PUNKS_V1_ADDRESS" \
        '{
            network: $network,
            chainId: ($chainId | tonumber),
            deployedAt: $deployedAt,
            contracts: ({
                PunksV1Wrapper: {
                    address: $wpv1Address,
                    etherscan: $wpv1Etherscan,
                    note: $wpv1Note
                },
                V1PunkStashFactory: {
                    address: $factoryAddress,
                    etherscan: $factoryEtherscan
                },
                V1PunkStashVerifier: {
                    address: $verifierAddress,
                    etherscan: $verifierEtherscan
                },
                V1PunkStashImplementation: {
                    address: $implAddress,
                    etherscan: $implEtherscan
                }
            } + (if $network == "sepolia" and $mockAddress != "" then {
                MockPunksV1: {
                    address: $mockAddress,
                    etherscan: $mockEtherscan
                }
            } else {} end)),
            environment: {
                WETH_ADDRESS: $wethAddress,
                DEPLOYER_ADDRESS: $deployerAddress
            }
        }')
    echo "$JSON_OBJECT" > $DEPLOYED_ADDRESSES_FILE
else
    # Simple method without jq
    {
        echo "{"
        echo "  \"network\": \"$NETWORK\","
        echo "  \"chainId\": $CHAIN_ID,"
        echo "  \"deployedAt\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
        echo "  \"contracts\": {"
        if [ "$NETWORK" = "sepolia" ] && [ ! -z "$MOCK_PUNKS_V1_ADDRESS" ]; then
            echo "    \"MockPunksV1\": {"
            echo "      \"address\": \"$MOCK_PUNKS_V1_ADDRESS\","
            echo "      \"etherscan\": \"$ETHERSCAN_BASE_URL/address/$MOCK_PUNKS_V1_ADDRESS\""
            echo "    },"
        fi
        echo "    \"PunksV1Wrapper\": {"
        echo "      \"address\": \"$PUNKS_V1_WRAPPER_ADDRESS\","
        echo "      \"etherscan\": \"$ETHERSCAN_BASE_URL/address/$PUNKS_V1_WRAPPER_ADDRESS\","
        echo "      \"note\": \"$([ "$NETWORK" = "mainnet" ] && echo "Existing contract" || echo "Deployed")\""
        echo "    },"
        echo "    \"V1PunkStashFactory\": {"
        echo "      \"address\": \"$FACTORY_ADDRESS\","
        echo "      \"etherscan\": \"$ETHERSCAN_BASE_URL/address/$FACTORY_ADDRESS\""
        echo "    },"
        echo "    \"V1PunkStashVerifier\": {"
        echo "      \"address\": \"$VERIFIER_ADDRESS\","
        echo "      \"etherscan\": \"$ETHERSCAN_BASE_URL/address/$VERIFIER_ADDRESS\""
        echo "    },"
        echo "    \"V1PunkStashImplementation\": {"
        echo "      \"address\": \"$IMPLEMENTATION_ADDRESS\","
        echo "      \"etherscan\": \"$ETHERSCAN_BASE_URL/address/$IMPLEMENTATION_ADDRESS\""
        echo "    }"
        echo "  },"
        echo "  \"environment\": {"
        echo "    \"WETH_ADDRESS\": \"$WETH_ADDRESS\","
        echo "    \"DEPLOYER_ADDRESS\": \"$DEPLOYER_ADDRESS\""
        echo "  }"
        echo "}"
    } > $DEPLOYED_ADDRESSES_FILE
fi

success "Addresses saved to: $DEPLOYED_ADDRESSES_FILE"
echo ""

# ============================================
# SUMMARY
# ============================================
info "=========================================="
success "Deployment and verification complete!"
info "=========================================="
echo ""
echo "📋 Deployed contracts summary:"
echo ""

if [ "$NETWORK" = "sepolia" ] && [ ! -z "$MOCK_PUNKS_V1_ADDRESS" ]; then
    echo "  MockPunksV1:"
    echo "    Address: $MOCK_PUNKS_V1_ADDRESS"
    echo "    Etherscan: $ETHERSCAN_BASE_URL/address/$MOCK_PUNKS_V1_ADDRESS"
    echo ""
fi

echo "  PunksV1Wrapper:"
echo "    Address: $PUNKS_V1_WRAPPER_ADDRESS"
if [ "$NETWORK" = "mainnet" ]; then
    echo "    Note: Existing contract (not deployed)"
fi
echo "    Etherscan: $ETHERSCAN_BASE_URL/address/$PUNKS_V1_WRAPPER_ADDRESS"
echo ""

echo "  V1PunkStashFactory:"
echo "    Address: $FACTORY_ADDRESS"
echo "    Etherscan: $ETHERSCAN_BASE_URL/address/$FACTORY_ADDRESS"
echo ""

if [ ! -z "$VERIFIER_ADDRESS" ]; then
    echo "  V1PunkStashVerifier:"
    echo "    Address: $VERIFIER_ADDRESS"
    echo "    Etherscan: $ETHERSCAN_BASE_URL/address/$VERIFIER_ADDRESS"
    echo ""
fi

if [ ! -z "$IMPLEMENTATION_ADDRESS" ]; then
    echo "  V1PunkStash Implementation:"
    echo "    Address: $IMPLEMENTATION_ADDRESS"
    echo "    Etherscan: $ETHERSCAN_BASE_URL/address/$IMPLEMENTATION_ADDRESS"
    echo ""
fi

echo ""
echo "💾 All addresses saved to: $DEPLOYED_ADDRESSES_FILE"
echo ""
echo "🔧 To use these addresses in your .env:"
echo "   export WRAPPED_PUNKS_V1_ADDRESS=$PUNKS_V1_WRAPPER_ADDRESS"
echo "   export ERC721_STASH_FACTORY_ADDRESS=$FACTORY_ADDRESS"
echo ""
