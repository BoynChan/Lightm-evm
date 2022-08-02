// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "../RMRK/RMRKEquippable.sol";

/* import "hardhat/console.sol"; */

//Minimal public implementation of RMRKEquippable for testing.
contract RMRKEquippableMock is RMRKEquippable {

    constructor(address nestingAddress)
    RMRKEquippable(nestingAddress)
    {}

    function setFallbackURI(string memory fallbackURI) external {
        _setFallbackURI(fallbackURI);
    }

    function setNestingAddress(address nestingAddress) external {
        _setNestingAddress(nestingAddress);
    }

    function setTokenEnumeratedResource(
        uint64 resourceId,
        bool state
    ) external {
        _setTokenEnumeratedResource(resourceId, state);
    }

    function addResourceToToken(
        uint256 tokenId,
        uint64 resourceId,
        uint64 overwrites
    ) external {
        // This reverts if token does not exist:
        _ownerOf(tokenId);
        _addResourceToToken(tokenId, resourceId, overwrites);
    }

    function addResourceEntry(
        ExtendedResource calldata resource,
        uint64[] calldata fixedPartIds,
        uint64[] calldata slotPartIds
    ) external {
        _addResourceEntry(resource, fixedPartIds, slotPartIds);
    }

    function setCustomResourceData(
        uint64 resourceId,
        uint128 customResourceId,
        bytes memory data
    ) external {
        _setCustomResourceData(resourceId, customResourceId, data);
    }

    function addCustomDataToResource(
        uint64 resourceId,
        uint128 customResourceId
    ) external {
        _addCustomDataToResource(resourceId, customResourceId);
    }

    function removeCustomDataFromResource(
        uint64 resourceId,
        uint256 index
    ) external {
        _removeCustomDataFromResource(resourceId, index);
    }

    function setValidParentRefId(
        uint64 refId,
        address parentAddress,
        uint64 partId
    ) external {
        _setValidParentRefId(refId, parentAddress, partId);
    }
}
