// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Minimal bytecode registered as factory version 2 when the real V1PunkStash reports version 3+.
/// @dev Used by tests and greenfield deploy scripts so `addVersion` can satisfy sequential versioning.
contract StashImplementationPlaceholderV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}
