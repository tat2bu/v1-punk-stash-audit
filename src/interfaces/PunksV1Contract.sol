// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title PunksV1Contract Interface
 * @notice Interface for the original CryptoPunks V1 contract
 */
interface PunksV1Contract {
    // Events
    event Assign(address indexed to, uint256 punkIndex);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PunkTransfer(address indexed from, address indexed to, uint256 punkIndex);
    event PunkOffered(uint indexed punkIndex, uint minValue, address indexed toAddress);
    event PunkBought(uint indexed punkIndex, uint value, address indexed fromAddress, address indexed toAddress);
    event PunkNoLongerForSale(uint indexed punkIndex);

    // Read contract
    function name() external view returns (string memory);
    function punksOfferedForSale(uint id) external view returns (bool isForSale, uint punkIndex, address seller, uint minValue, address onlySellTo);
    function totalSupply() external view returns (uint);
    function decimals() external view returns (uint8);
    function imageHash() external view returns (string memory);
    function nextPunkIndexToAssign() external view returns (uint);
    function punksRemainingToAssign() external view returns (uint);
    function standard() external view returns (string memory);
    function balanceOf(address owner) external view returns (uint256);
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function pendingWithdrawals(address account) external view returns (uint256);

    // Write contract
    function transferPunk(address to, uint256 punkIndex) external;
    function buyPunk(uint punkIndex) external payable;
    function withdraw() external;
    function offerPunkForSale(uint punkIndex, uint minSalePriceInWei) external;
    function offerPunkForSaleToAddress(uint punkIndex, uint minSalePriceInWei, address toAddress) external;
    function punkNoLongerForSale(uint punkIndex) external;
}

