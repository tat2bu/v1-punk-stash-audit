// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IWrappedPunksV1} from "../../src/interfaces/IWrappedPunksV1.sol";

/// @notice Full WPV1 mock with ERC721 ownership tracking for wrapped-path tests.
/// Punks are "wrapped" via `mintWrapped` (test helper) — `exists` returns true for minted tokens.
contract MockWPV1Full is IWrappedPunksV1 {
    mapping(uint256 => address) private _owners;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    uint256 private _supply;

    // ---- Test helpers ----

    /// @dev Mint a wrapped punk to `to`. Used by test setup to simulate a punk that is already wrapped.
    function mintWrapped(address to, uint256 tokenId) external {
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = to;
        _supply++;
    }

    // ---- IWrappedPunksV1 ----

    function exists(uint256 tokenId) external view override returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function wrap(uint256) external payable override {}
    function unwrap(uint256) external override {}

    function punkAddress() external pure override returns (address payable) {
        return payable(address(0));
    }

    function totalSupply() external view override returns (uint256) {
        return _supply;
    }

    // ---- IERC721 ----

    function balanceOf(address owner_) external view override returns (uint256) {
        uint256 count;
        // Not gas-efficient, but fine for tests
        for (uint256 i = 0; i < 10000; i++) {
            if (_owners[i] == owner_) count++;
        }
        return count;
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "not minted");
        return o;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        _transfer(from, to, tokenId);

        // Call onERC721Received on the recipient if it is a contract
        uint256 codeSize;
        assembly { codeSize := extcodesize(to) }
        if (codeSize > 0) {
            (bool ok, bytes memory ret) = to.call(
                abi.encodeWithSignature("onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, "")
            );
            require(ok && abi.decode(ret, (bytes4)) == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")), "ERC721: transfer to non ERC721Receiver");
        }
    }

    function transferFrom(address from, address to, uint256 tokenId) external override {
        _transfer(from, to, tokenId);
    }

    function approve(address to, uint256 tokenId) external override {
        require(_owners[tokenId] == msg.sender, "not owner");
        _approvals[tokenId] = to;
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        return _approvals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address owner_, address operator) external view override returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    // ---- Internal ----

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(_owners[tokenId] == from, "not owner");
        require(
            msg.sender == from || _approvals[tokenId] == msg.sender || _operatorApprovals[from][msg.sender],
            "not approved"
        );
        _owners[tokenId] = to;
        delete _approvals[tokenId];
    }
}
