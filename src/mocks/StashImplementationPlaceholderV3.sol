// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Minimal bytecode registered as factory version 3 so `addVersion` can satisfy sequential versioning.
contract StashImplementationPlaceholderV3 {
    function version() external pure returns (uint256) {
        return 3;
    }
}
