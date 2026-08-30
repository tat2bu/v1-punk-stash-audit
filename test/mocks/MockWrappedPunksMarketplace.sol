// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IWrappedPunksMarketplace} from "../../src/interfaces/IWrappedPunksMarketplace.sol";

interface IERC721ForMarketplace {
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/**
 * @title MockWrappedPunksMarketplace
 * @notice Minimal mock of FrankPoncelet's wrapped punks marketplace for testing.
 * @dev Reproduces the core buyPunk / offerPunkForSale flow:
 *   - Seller lists via offerPunkForSaleToAddress (seller must own the WPV1 token)
 *   - Buyer calls buyPunk{value >= minValue}
 *   - Marketplace pays seller directly and transfers the WPV1 ERC721 to buyer via safeTransferFrom
 *   - Emits PunkBought with the real sale price
 */
contract MockWrappedPunksMarketplace is IWrappedPunksMarketplace {
    IERC721ForMarketplace public wpv1;

    mapping(uint256 => Offer) private _offers;
    uint256 public totalVolume;

    event PunkBought(uint256 indexed punkIndex, uint256 value, address indexed fromAddress, address indexed toAddress);
    event PunkOffered(uint256 indexed punkIndex, uint256 minValue, address indexed toAddress);

    constructor(address _wpv1) {
        wpv1 = IERC721ForMarketplace(_wpv1);
    }

    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external {
        require(wpv1.ownerOf(punkIndex) == msg.sender, "you are not the owner of this token");
        _offers[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, toAddress);
        emit PunkOffered(punkIndex, minSalePriceInWei, toAddress);
    }

    function offerPunkForSale(uint256 punkIndex, uint256 minSalePriceInWei) external {
        require(wpv1.ownerOf(punkIndex) == msg.sender, "you are not the owner of this token");
        _offers[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, address(0));
        emit PunkOffered(punkIndex, minSalePriceInWei, address(0));
    }

    function buyPunk(uint256 punkIndex) external payable override {
        Offer memory offer = _offers[punkIndex];
        require(offer.isForSale, "Punk is not for sale");
        require(offer.onlySellTo == address(0) || offer.onlySellTo == msg.sender, "Private sale.");
        require(msg.value >= offer.minValue, "Not enough ether send");
        address seller = offer.seller;
        require(seller == wpv1.ownerOf(punkIndex), "seller no longer owner of punk");

        // Clear the offer
        _offers[punkIndex] = Offer(false, punkIndex, msg.sender, 0, address(0));

        // Pay seller directly (no pendingWithdrawals)
        (bool success, ) = payable(seller).call{value: msg.value}("");
        require(success, "Failed to send Ether");

        totalVolume += msg.value;

        // Transfer ERC721 from seller to buyer
        wpv1.safeTransferFrom(seller, msg.sender, punkIndex);

        emit PunkBought(punkIndex, msg.value, seller, msg.sender);
    }

    function getOffer(uint256 punkIndex) external view override returns (Offer memory) {
        return _offers[punkIndex];
    }
}
