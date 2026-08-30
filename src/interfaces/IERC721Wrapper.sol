// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IERC721Wrapper {
  function unwrapToken(uint256 tokenId) external;
}

