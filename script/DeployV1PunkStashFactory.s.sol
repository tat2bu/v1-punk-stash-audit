// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {V1PunkStashFactory} from "src/V1PunkStashFactory.sol";
import {V1PunkStash} from "src/V1PunkStash.sol";
import {StashImplementationPlaceholderV1} from "src/mocks/StashImplementationPlaceholderV1.sol";
import {StashImplementationPlaceholderV2} from "src/mocks/StashImplementationPlaceholderV2.sol";
import {StashImplementationPlaceholderV3} from "src/mocks/StashImplementationPlaceholderV3.sol";

contract DeployV1PunkStashFactory is Script {
    function run() external {
        // Get configuration from environment variables
        address initialImplementation = vm.envOr("ERC721_STASH_IMPLEMENTATION_V1", address(0));
        
        // If not set, deploy a new implementation
        if (initialImplementation == address(0)) {
            // Get required addresses from environment
            address weth = vm.envOr("WETH_ADDRESS", address(0));
            address wrappedPunksV1 = vm.envOr("WRAPPED_PUNKS_V1_ADDRESS", address(0));
            address punksV1Contract = vm.envOr("PUNKS_V1_ADDRESS", address(0));
            address wrappedMarketplace = vm.envOr("WRAPPED_PUNKS_MARKETPLACE_ADDRESS", address(0));

            require(weth != address(0), "WETH_ADDRESS not set");
            require(wrappedPunksV1 != address(0), "WRAPPED_PUNKS_V1_ADDRESS not set");
            require(punksV1Contract != address(0), "PUNKS_V1_ADDRESS not set");
            require(wrappedMarketplace != address(0), "WRAPPED_PUNKS_MARKETPLACE_ADDRESS not set");

            vm.startBroadcast();

            // Deploy factory first (without implementation)
            V1PunkStashFactory factory = new V1PunkStashFactory(address(0));

            // Deploy implementation with factory address
            // WPV1 is used as both the ERC721 token and wrapper (it's an ERC721 standard)
            V1PunkStash implementation = new V1PunkStash(
                address(factory),
                weth,
                wrappedPunksV1,
                punksV1Contract,
                wrappedMarketplace
            );

            // Register placeholders v1–v3 then real implementation (V1PunkStash.version() is 4).
            factory.addVersion(address(new StashImplementationPlaceholderV1()));
            factory.addVersion(address(new StashImplementationPlaceholderV2()));
            factory.addVersion(address(new StashImplementationPlaceholderV3()));
            factory.addVersion(address(implementation));

            vm.stopBroadcast();

            console2.log("V1PunkStashFactory deployed at", address(factory));
            console2.log("V1PunkStashVerifier deployed at", factory.stashVerifier());
            console2.log("V1PunkStash implementation (current) deployed at", address(implementation));
        } else {
            // Use existing implementation
            vm.startBroadcast();
            V1PunkStashFactory factory = new V1PunkStashFactory(initialImplementation);
            vm.stopBroadcast();

            console2.log("V1PunkStashFactory deployed at", address(factory));
            console2.log("V1PunkStashVerifier deployed at", factory.stashVerifier());
            console2.log("Initial implementation (v1) set at", initialImplementation);
        }
    }
}

