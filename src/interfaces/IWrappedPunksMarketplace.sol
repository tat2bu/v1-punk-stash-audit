// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IWrappedPunksMarketplace
 * @notice Interface for FrankPoncelet's Wrapped Punks V1 Marketplace
 * @dev Mainnet address: 0x759c6C1923910930C18ef490B3c3DbeFf24003cE
 *
 * This marketplace operates on WPV1 ERC721 tokens and mirrors the native CryptoPunks
 * marketplace API (offerPunkForSale / buyPunk / enterBidForPunk). Unlike the native V1
 * contract, it pays sellers directly (no pendingWithdrawals bug) and emits a PunkBought
 * event with the real sale price.
 */
interface IWrappedPunksMarketplace {
    struct Offer {
        bool isForSale;
        uint256 punkIndex;
        address seller;
        uint256 minValue;
        address onlySellTo;
    }

    /// @notice Buy a wrapped punk that is listed for sale. The marketplace pays the seller
    ///         directly and transfers the WPV1 ERC721 token to msg.sender via safeTransferFrom.
    /// @param punkIndex The punk index to buy.
    function buyPunk(uint256 punkIndex) external payable;

    /// @notice Returns the current offer for a given punk index.
    /// @param punkIndex The punk index to query.
    /// @return offer The current offer details.
    function getOffer(uint256 punkIndex) external view returns (Offer memory offer);
}
