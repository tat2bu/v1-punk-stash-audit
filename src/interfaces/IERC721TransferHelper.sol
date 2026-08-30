// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IERC721TransferHelper {
  function transferWrappedTokenToStash(bytes32 tokenIdAndOwnerPacked) external;
}

