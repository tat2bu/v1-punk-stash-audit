// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IV1PunkStash} from "./interfaces/IV1PunkStash.sol";
import {IV1PunkStashFactory} from "./interfaces/IV1PunkStashFactory.sol";

/**
 * @title V1PunkStashVerifier
 * @author Cryptopunks.eth.limo (forked from Yuga Labs' StashVerifier)
 * @notice Helper contract used by the V1PunkStashFactory to make external calls to the V1PunkStash contract.
 */
contract V1PunkStashVerifier {
    address private immutable _STASH_FACTORY_ADDRESS;

    constructor() {
        _STASH_FACTORY_ADDRESS = msg.sender;
    }

    function isStash(address stashAddress) external view returns (bool) {
        IV1PunkStash stashContract = IV1PunkStash(stashAddress);

        uint256 size;
        assembly {
            size := extcodesize(stashAddress)
        }
        if (size == 0) return false;

        // call owner() method on stash
        (bool success, bytes memory result) = address(stashContract).staticcall(abi.encodeWithSelector(0x8da5cb5b));
        if (!success) return false;

        address stashOwner;
        assembly {
            // extract stash owner address from result
            stashOwner := and(mload(add(result, 32)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        address predictedAddress = IV1PunkStashFactory(_STASH_FACTORY_ADDRESS).stashAddressFor(stashOwner);

        // ensure that the stash owner would have deployed to the provided stashAddress
        return predictedAddress == stashAddress;
    }

    function stashVersion(address stashAddress) external view returns (uint256) {
        IV1PunkStash stashContract = IV1PunkStash(stashAddress);

        return stashContract.version();
    }
}

