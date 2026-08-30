// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {V1PunkStashFactory} from "src/V1PunkStashFactory.sol";
import {V1PunkStash} from "src/V1PunkStash.sol";

/// @notice Deploy a new V1PunkStash implementation and register it on an existing factory via `addVersion`.
/// @dev Requires `msg.sender` to have the factory's version-manager role. Uses mainnet defaults when chainid == 1
///      and env vars are unset (override with WETH_ADDRESS, WRAPPED_PUNKS_V1_ADDRESS, PUNKS_V1_ADDRESS,
///      WRAPPED_PUNKS_MARKETPLACE_ADDRESS).
///
/// Example (mainnet, `PRIVATE_KEY` must be a factory version-manager):
///   export STASH_FACTORY=0x25d136deEBE7C07C2B9A933924aB4BA419027F37
///   export PRIVATE_KEY=...
///   forge script script/AddStashImplementationToFactory.s.sol:AddStashImplementationToFactory \
///     --rpc-url mainnet --broadcast -vvvv
contract AddStashImplementationToFactory is Script {
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant MAINNET_WPV1 = 0x282BDD42f4eb70e7A9D9F40c8fEA0825B7f68C5D;
    /// @dev CryptoPunks V1 market (same as frontend `v1PunksMarketAddress`).
    address internal constant MAINNET_PUNKS_V1 = 0x6Ba6f2207e343923BA692e5Cae646Fb0F566DB8D;
    /// @dev FrankPoncelet's wrapped punks marketplace.
    address internal constant MAINNET_WRAPPED_MARKETPLACE = 0x759c6C1923910930C18ef490B3c3DbeFf24003cE;

    function run() external {
        address factoryAddr = vm.envAddress("STASH_FACTORY");

        address weth;
        address wrappedPunksV1;
        address punksV1;
        address wrappedMarketplace;
        if (block.chainid == 1) {
            weth = vm.envOr("WETH_ADDRESS", MAINNET_WETH);
            wrappedPunksV1 = vm.envOr("WRAPPED_PUNKS_V1_ADDRESS", MAINNET_WPV1);
            punksV1 = vm.envOr("PUNKS_V1_ADDRESS", MAINNET_PUNKS_V1);
            wrappedMarketplace = vm.envOr("WRAPPED_PUNKS_MARKETPLACE_ADDRESS", MAINNET_WRAPPED_MARKETPLACE);
        } else {
            weth = vm.envAddress("WETH_ADDRESS");
            wrappedPunksV1 = vm.envAddress("WRAPPED_PUNKS_V1_ADDRESS");
            punksV1 = vm.envAddress("PUNKS_V1_ADDRESS");
            wrappedMarketplace = vm.envAddress("WRAPPED_PUNKS_MARKETPLACE_ADDRESS");
        }

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        V1PunkStash implementation = new V1PunkStash(factoryAddr, weth, wrappedPunksV1, punksV1, wrappedMarketplace);
        V1PunkStashFactory(factoryAddr).addVersion(address(implementation));

        vm.stopBroadcast();

        console2.log("Factory", factoryAddr);
        console2.log("New implementation", address(implementation));
        console2.log("Implementation version()", implementation.version());
        console2.log("Factory currentVersion()", V1PunkStashFactory(factoryAddr).currentVersion());
    }
}
