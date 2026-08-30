// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title Minimal IERC721 interface
 */
interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/**
 * @title IWrappedPunksV1
 * @notice Interface for Wrapped Punks V1 (WPV1) contract
 * @dev This is an ERC721 contract that wraps CryptoPunks V1
 * Mainnet address: 0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d
 */
interface IWrappedPunksV1 is IERC721 {
    /**
     * @notice Wraps a punk V1 into an ERC721 token
     * @param _punkId The ID of the punk to wrap
     */
    function wrap(uint256 _punkId) external payable;

    /**
     * @notice Unwraps a wrapped punk V1 back to the original contract
     * @param _punkId The ID of the punk to unwrap
     */
    function unwrap(uint256 _punkId) external;

    /**
     * @notice Returns the address of the original CryptoPunks V1 contract
     * @return The address of the punks contract
     */
    function punkAddress() external view returns (address payable);

    /**
     * @notice Returns the total supply of wrapped tokens
     * @return The total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Checks if a token exists
     * @param tokenId The token ID to check
     * @return Whether the token exists
     */
    function exists(uint256 tokenId) external view returns (bool);
}

