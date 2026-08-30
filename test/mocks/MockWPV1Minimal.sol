// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IWrappedPunksV1} from "../../src/interfaces/IWrappedPunksV1.sol";

/// @notice Minimal WPV1 stand-in for tests: `exists` is always false so punks are treated as unwrapped on V1.
contract MockWPV1Minimal is IWrappedPunksV1 {
    function exists(uint256) external pure returns (bool) {
        return false;
    }

    function wrap(uint256) external payable {}

    function unwrap(uint256) external {}

    function punkAddress() external pure returns (address payable) {
        return payable(address(0));
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function ownerOf(uint256) external pure returns (address) {
        return address(0);
    }

    function safeTransferFrom(address, address, uint256) external pure {}

    function transferFrom(address, address, uint256) external pure {}

    function approve(address, uint256) external pure {}

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function setApprovalForAll(address, bool) external pure {}

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }
}
