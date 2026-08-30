// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OrderType} from "../helpers/Enum.sol";
import {Order} from "../helpers/V1PunkStruct.sol";

interface IV1PunkStash {
    function placeOrder(uint80 pricePerUnit, uint16 numberOfUnits) external payable;
    function processOrder(uint80 costPerUnit, uint16 numberOfUnits) external;
    function availableLiquidity(address tokenAddress) external view returns (uint256);
    function wrapToken(uint256 tokenId) external;
    function getOrder(address auction) external view returns (Order memory);
    function withdraw(address tokenAddress, uint256 amount) external;
    function withdrawERC721(address tokenAddress, uint256[] calldata tokenIds) external;
    function owner() external view returns (address);
    function version() external view returns (uint256);
}

