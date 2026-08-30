// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {PunksV1Wrapper} from "src/PunksV1Wrapper.sol";
import {MockPunksV1} from "src/mocks/MockPunksV1.sol";

/**
 * @title DeployWPV1
 * @notice Script to deploy Wrapped Punks V1 (WPV1) contract
 * @dev This contract wraps CryptoPunks V1 into ERC721 standard tokens
 * Mainnet address: 0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d
 * Source: https://etherscan.io/address/0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d#code
 */
contract DeployWPV1 is Script {
    function run() external returns (address) {
        // Get the CryptoPunks V1 contract address
        // Mainnet: 0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D
        // For Sepolia, deploy a mock if PUNKS_V1_ADDRESS is not set
        address payable punkAddress;
        
        // Check if we should deploy a mock (for Sepolia/testnets)
        bool deployMock = vm.envOr("DEPLOY_MOCK_PUNKS_V1", false);
        
        if (deployMock) {
            // Deploy mock Punks V1 contract
            vm.startBroadcast();
            MockPunksV1 mockPunks = new MockPunksV1();
            punkAddress = payable(address(mockPunks));
            vm.stopBroadcast();
            
            console2.log("MockPunksV1 deployed at", address(mockPunks));
        } else {
            // Use existing address
            punkAddress = payable(
                vm.envOr("PUNKS_V1_ADDRESS", address(0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D))
            );
            require(punkAddress != address(0), "PUNKS_V1_ADDRESS not set");
        }

        // Get deployer address from environment or use tx.origin
        // When using --sender and --private-key, tx.origin is the deployer
        address deployer = vm.envOr("DEPLOYER_ADDRESS", tx.origin);
        if (deployer == address(0)) {
            deployer = tx.origin;
        }
        
        // Deploy PunksV1Wrapper
        vm.startBroadcast();
        PunksV1Wrapper wpv1 = new PunksV1Wrapper(punkAddress);
        
        // Target address to receive tokens 1, 2, and 3
        address targetAddress = 0x516Fc698fb46506aA983a14F40b30c908d86Dc82;
        
        // If using mock, mint punks to deployer first
        if (deployMock) {
            MockPunksV1 mockPunks = MockPunksV1(punkAddress);
            
            // Mint punks 1, 2, 3 to the deployer
            // These are called from script context but will be owned by deployer
            mockPunks.mintPunk(deployer, 1);
            mockPunks.mintPunk(deployer, 2);
            mockPunks.mintPunk(deployer, 3);
            
            console2.log("Minted punks 1, 2, 3 to deployer:", deployer);
        }
        
        vm.stopBroadcast();
        
        // If using mock, transfer native punks directly to target address
        if (deployMock) {
            MockPunksV1 mockPunks = MockPunksV1(punkAddress);
            
            vm.startBroadcast();
            // Transfer native punks from deployer directly to target address
            mockPunks.transferPunkFrom(deployer, targetAddress, 1);
            mockPunks.transferPunkFrom(deployer, targetAddress, 2);
            mockPunks.transferPunkFrom(deployer, targetAddress, 3);
            vm.stopBroadcast();
            
            console2.log("Transferred native punks 1, 2, 3 to", targetAddress);
        } else {
            // For mainnet, assume deployer owns punks and wrap normally
            vm.startBroadcast(deployer);
            wpv1.wrap(1);
            wpv1.wrap(2);
            wpv1.wrap(3);
            
            wpv1.safeTransferFrom(deployer, targetAddress, 1);
            wpv1.safeTransferFrom(deployer, targetAddress, 2);
            wpv1.safeTransferFrom(deployer, targetAddress, 3);
            vm.stopBroadcast();
        }
        
        if (!deployMock) {
            console2.log("Wrapped punks 1, 2, 3");
            console2.log("Transferred wrapped tokens 1, 2, 3 to", targetAddress);
        }

        console2.log("PunksV1Wrapper deployed at", address(wpv1));
        console2.log("Punk address:", punkAddress);
        console2.log("");
        console2.log("To use this address in your .env:");
        console2.log("WRAPPED_PUNKS_V1_ADDRESS=", address(wpv1));
        
        return address(wpv1);
    }
}

