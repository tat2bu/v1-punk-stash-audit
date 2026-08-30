// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {V1PunkStashFactory} from "src/V1PunkStashFactory.sol";

/// @notice Upgrade the deterministic stash proxy for the broadcast account to the factory's latest implementation.
/// @dev The broadcast wallet MUST be the stash owner (`PRIVATE_KEY` -> `vm.addr`). Uses `STASH_FACTORY` env.
///      For hardware wallets, call `upgradeStash()` on the factory from the owner address via cast/etherscan instead.
///
/// Example (mainnet):
///   export STASH_FACTORY=0x25d136deEBE7C07C2B9A933924aB4BA419027F37
///   export PRIVATE_KEY=...   # stash owner key (hex without 0x or with — forge accepts both per version)
///   forge script script/UpgradeStashViaFactory.s.sol:UpgradeStashViaFactory \
///     --rpc-url mainnet --broadcast -vvvv
contract UpgradeStashViaFactory is Script {
    function run() external {
        address factoryAddr = vm.envAddress("STASH_FACTORY");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address stashOwner = vm.addr(pk);

        vm.startBroadcast(pk);
        V1PunkStashFactory(factoryAddr).upgradeStash();
        vm.stopBroadcast();

        address stash = V1PunkStashFactory(factoryAddr).stashAddressFor(stashOwner);
        console2.log("Upgraded stash for owner", stashOwner);
        console2.log("Stash proxy", stash);
        console2.log("Factory currentVersion()", V1PunkStashFactory(factoryAddr).currentVersion());
    }
}
