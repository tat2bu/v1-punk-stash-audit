// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {MockPunksV1} from "src/mocks/MockPunksV1.sol";

/**
 * @title DeployMockPunksV1
 * @notice Script to deploy MockPunksV1 contract for testing on Sepolia
 * @dev This mock contract simulates the CryptoPunks V1 contract for testing purposes
 */
contract DeployMockPunksV1 is Script {
    function run() external returns (address) {
        vm.startBroadcast();
        MockPunksV1 mockPunks = new MockPunksV1();
        vm.stopBroadcast();

        console2.log("MockPunksV1 deployed at", address(mockPunks));
        return address(mockPunks);
    }
}

