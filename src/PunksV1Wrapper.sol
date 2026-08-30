// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC721/ERC721.sol";
import "@openzeppelin/access/Ownable.sol";
import "./interfaces/PunksV1Contract.sol";

/**
 * @title PunksV1Wrapper contract
 * @dev Extends ERC721 Non-Fungible Token Standard basic implementation.
 * Based on the V1 wrapper of @author @foobar, but optimised to work with our MarketPlace contract.
 * @author @FrankPoncelet
 * 
 * Mainnet address: 0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d
 * Source: https://etherscan.io/address/0x282bdd42f4eb70e7a9d9f40c8fea0825b7f68c5d#code
 */
contract PunksV1Wrapper is Ownable, ERC721 {
    address payable public punkAddress;
    string private _baseTokenURI;
    uint256 private _tokenSupply;

    constructor(address payable _punkAddress) ERC721("V1 Cryptopunks (Wrapped)", "WPV1") {
        punkAddress = _punkAddress;
        _baseTokenURI = "ipfs://Qma3sC19HbnWHqeLgcsQnR7Kvgus4oPQirXNH7QYBeACaq/";
    }

    /**
     * @dev Accepts an offer from the punks contract and assigns a wrapped token to msg.sender
     */
    function wrap(uint _punkId) external payable {
        // Prereq: owner should call `offerPunkForSaleToAddress` with price 0 (or higher if they wish)
        (bool isForSale, , address seller, uint minValue, address onlySellTo) = PunksV1Contract(punkAddress).punksOfferedForSale(_punkId);
        require(isForSale == true, "Punk not for sale");
        require(seller == msg.sender, "Seller must be msg.sender");
        require(minValue == 0, "Min value must be 0");
        require((onlySellTo == address(this)) || (onlySellTo == address(0x0)), "Punk not offered to wrapper");
        // Buy the punk
        PunksV1Contract(punkAddress).buyPunk{value: msg.value}(_punkId);
        _tokenSupply += 1;
        // Mint a wrapped punk
        _mint(msg.sender, _punkId);
    }

    /**
     * @dev Burns the wrapped token and transfers the underlying punk to the owner
     **/
    function unwrap(uint256 _punkId) external {
        require(_isApprovedOrOwner(msg.sender, _punkId), "Not approved or owner");
        _burn(_punkId);
        _tokenSupply -= 1;
        PunksV1Contract(punkAddress).transferPunk(msg.sender, _punkId);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Set a new base token URI
     */
    function setBaseTokenURI(string memory __baseTokenURI) public onlyOwner {
        _baseTokenURI = __baseTokenURI;
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function exists(uint256 tokenId) external view virtual returns (bool) {
        return _exists(tokenId);
    }

    /**
     * @dev Gets the total amount of tokens stored by the contract.
     * @return uint256 representing the total amount of tokens
     */
    function totalSupply() public view returns (uint256) {
        return _tokenSupply;
    }
}
