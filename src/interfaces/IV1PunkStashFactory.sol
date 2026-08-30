// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IV1PunkStashFactory {
    function isStash(address stash) external view returns (bool);
    function deployStash(address owner) external returns (address);
    function isAuction(address auction) external view returns (bool);
    function stashAddressFor(address owner) external view returns (address);
}

