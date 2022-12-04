// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../library/RMRKLib.sol";
import "../interfaces/IRMRKNestable.sol";
import "./ERC721Internal.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {NestableStorage} from "./Storage.sol";

import "hardhat/console.sol";

error RMRKChildIndexOutOfRange();
error RMRKDuplicateAdd();
error RMRKInvalidChildReclaim();
error RMRKIsNotContract();
error RMRKIsNotNestableImplementer();
error RMRKMaxPendingChildrenReached();
error RMRKMaxRecursiveBurnsReached(address childContract, uint256 childTokenId);
error RMRKMintToNonRMRKImplementer();
error RMRKNestableTooDeep();
error RMRKNestableTransferToDescendant();
error RMRKNestableTransferToNonRMRKNestableImplementer();
error RMRKNestableTransferToSelf();
error RMRKNotApprovedOrDirectOwner();
error RMRKParentChildMismatch();
error RMRKPendingChildIndexOutOfRange();

abstract contract RMRKNestableInternal is
    IRMRKNestableEventsAndStruct,
    ERC721Internal
{
    using RMRKLib for uint256;
    using Address for address;

    uint256 private constant _MAX_LEVELS_TO_CHECK_FOR_INHERITANCE_LOOP = 100;

    function getNestableState()
        internal
        pure
        returns (NestableStorage.State storage)
    {
        return NestableStorage.getState();
    }

    // ------------------------ Ownership ------------------------

    function _ownerOf(uint256 tokenId)
        internal
        view
        virtual
        override
        returns (address)
    {
        (address owner, uint256 ownerTokenId, bool isNft) = _directOwnerOf(
            tokenId
        );

        if (isNft) {
            owner = IRMRKNestable(owner).ownerOf(ownerTokenId);
        }
        if (owner == address(0)) revert ERC721InvalidTokenId();
        return owner;
    }

    /**
     * @dev Returns the immediate provenance data of the current RMRK NFT. In the event the NFT is owned
     * by a wallet, tokenId will be zero and isNft will be false. Otherwise, the returned data is the
     * contract address and tokenID of the owner NFT, as well as its isNft flag.
     */
    function _directOwnerOf(uint256 tokenId)
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bool
        )
    {
        RMRKOwner storage owner = getNestableState()._RMRKOwners[tokenId];
        if (owner.ownerAddress == address(0)) revert ERC721InvalidTokenId();

        return (owner.ownerAddress, owner.tokenId, owner.isNft);
    }

    function _isApprovedOrDirectOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        (address owner, uint256 parentTokenId, ) = _directOwnerOf(tokenId);
        if (parentTokenId != 0) {
            return (spender == owner);
        }
        return (spender == owner ||
            _isApprovedForAll(owner, spender) ||
            _getApproved(tokenId) == spender);
    }

    /**
     * @notice Internal function for checking token ownership relative to immediate parent.
     * @dev This does not delegate to ownerOf, which returns the root owner.
     * Reverts if caller is not immediate owner.
     * Used for parent-scoped transfers.
     * @param tokenId tokenId to check owner against.
     */
    function _onlyApprovedOrDirectOwner(uint256 tokenId) private view {
        if (!_isApprovedOrDirectOwner(_msgSender(), tokenId))
            revert RMRKNotApprovedOrDirectOwner();
    }

    modifier onlyApprovedOrDirectOwner(uint256 tokenId) {
        _onlyApprovedOrDirectOwner(tokenId);
        _;
    }

    /**
     * @dev Returns all confirmed children
     */

    function _childrenOf(uint256 parentTokenId)
        internal
        view
        returns (Child[] memory)
    {
        Child[] memory children = getNestableState()._activeChildren[
            parentTokenId
        ];
        return children;
    }

    function _pendingChildrenOf(uint256 parentTokenId)
        internal
        view
        returns (Child[] memory)
    {
        Child[] memory pendingChildren = getNestableState()._pendingChildren[
            parentTokenId
        ];
        return pendingChildren;
    }

    function _childOf(uint256 parentTokenId, uint256 index)
        internal
        view
        returns (Child memory)
    {
        _isOverLength(parentTokenId, index, false);

        Child memory child = getNestableState()._activeChildren[parentTokenId][
            index
        ];
        return child;
    }

    function _pendingChildOf(uint256 parentTokenId, uint256 index)
        internal
        view
        returns (Child memory)
    {
        _isOverLength(parentTokenId, index, true);

        Child memory child = getNestableState()._pendingChildren[parentTokenId][
            index
        ];
        return child;
    }

    function _hasChild(
        uint256 tokenId,
        address childContract,
        uint256 childTokenId
    )
        internal
        view
        returns (
            bool found,
            bool isPending,
            uint256 index
        )
    {
        _requireMinted(tokenId);

        NestableStorage.State storage ns = getNestableState();

        uint256 _index = ns._posInChildArray[childContract][childTokenId];

        if (_index > 0) {
            found = true;
            index = _index;

            Child memory _pendingChild = ns._pendingChildren[tokenId][index];

            if (
                _pendingChild.contractAddress == childContract &&
                _pendingChild.tokenId == childTokenId
            ) {
                isPending = true;
            }
        } else {
            (address parentContract, , bool isNft) = IRMRKNestable(childContract)
                .directOwnerOf(childTokenId);

            if (isNft && parentContract == address(this)) {
                if (ns._activeChildren[tokenId].length > 0) {
                    Child memory child = ns._activeChildren[tokenId][0];
                    if (
                        child.contractAddress == childContract &&
                        child.tokenId == childTokenId
                    ) {
                        found = true;
                        return (found, isPending, index);
                    }
                }

                if (ns._pendingChildren[tokenId].length > 0) {
                    Child memory pendingChild = ns._pendingChildren[tokenId][0];
                    if (
                        pendingChild.contractAddress == childContract &&
                        pendingChild.tokenId == childTokenId
                    ) {
                        found = true;
                        isPending = true;
                    }
                }
            }
        }
    }

    // ------------------------ MINTING ------------------------

    function _mint(
        address to,
        uint256 tokenId,
        bool isNft,
        uint256 destinationId
    ) internal {
        if (to == address(0)) revert ERC721MintToTheZeroAddress();
        if (_exists(tokenId)) revert ERC721TokenAlreadyMinted();

        if (isNft) {
            _isNestableContract(to, 1);
        }

        _beforeTokenTransfer(address(0), to, tokenId);

        getState()._balances[to] += 1;

        if (isNft) {
            getNestableState()._RMRKOwners[tokenId] = RMRKOwner({
                ownerAddress: to,
                tokenId: destinationId,
                isNft: true
            });

            _sendToNFT(address(0), to, 0, destinationId, tokenId);
        } else {
            getNestableState()._RMRKOwners[tokenId] = RMRKOwner({
                ownerAddress: to,
                tokenId: 0,
                isNft: false
            });
        }

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal virtual override {
        _mint(to, tokenId, false, 0);
    }

    function _nestMint(
        address to,
        uint256 tokenId,
        uint256 destinationId
    ) internal virtual {
        _mint(to, tokenId, true, destinationId);
    }

    function _sendToNFT(
        address from,
        address to,
        uint256 fromTokenId,
        uint256 destinationId,
        uint256 tokenId
    ) private {
        IRMRKNestable destContract = IRMRKNestable(to);

        destContract.addChild(destinationId, tokenId);
        emit NestTransfer(from, to, fromTokenId, destinationId, tokenId);
    }

    // ------------------------ BURNING ------------------------

    function _burn(uint256 tokenId, uint256 maxChildrenBurns)
        internal
        virtual
        returns (uint256)
    {
        (address immediateOwner, uint256 parentId, ) = _directOwnerOf(tokenId);
        address owner = _ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);
        _beforeNestedTokenTransfer(
            immediateOwner,
            address(0),
            parentId,
            0,
            tokenId
        );

        {
            ERC721Storage.State storage s = getState();
            s._balances[immediateOwner] -= 1;
            delete s._tokenApprovals[tokenId];
        }

        NestableStorage.State storage ns = getNestableState();

        _approve(address(0), tokenId);
        _cleanApprovals(tokenId);

        Child[] memory children = ns._activeChildren[tokenId];

        delete ns._activeChildren[tokenId];
        delete ns._pendingChildren[tokenId];

        uint256 totalChildBurns;
        {
            uint256 pendingRecursiveBurns;
            uint256 length = children.length; //gas savings
            for (uint256 i; i < length; ) {
                if (totalChildBurns >= maxChildrenBurns) {
                    revert RMRKMaxRecursiveBurnsReached(
                        children[i].contractAddress,
                        children[i].tokenId
                    );
                }

                delete ns._posInChildArray[children[i].contractAddress][
                    children[i].tokenId
                ];

                unchecked {
                    // At this point we know pendingRecursiveBurns must be at least 1
                    pendingRecursiveBurns = maxChildrenBurns - totalChildBurns;
                }
                // We substract one to the next level to count for the token being burned, then add it again on returns
                // This is to allow the behavior of 0 recursive burns meaning only the current token is deleted.
                totalChildBurns +=
                    IRMRKNestable(children[i].contractAddress).burn(
                        children[i].tokenId,
                        pendingRecursiveBurns - 1
                    ) +
                    1;
                unchecked {
                    ++i;
                }
            }
        }
        // Can't remove before burning child since child will call back to get root owner
        delete ns._RMRKOwners[tokenId];

        _afterTokenTransfer(owner, address(0), tokenId);
        _afterNestedTokenTransfer(
            immediateOwner,
            address(0),
            parentId,
            0,
            tokenId
        );
        emit Transfer(owner, address(0), tokenId);
        emit NestTransfer(immediateOwner, address(0), parentId, 0, tokenId);

        return totalChildBurns;
    }

    // ------------------------ TRANSFERING ------------------------

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        _transfer(from, to, tokenId, false, 0);
    }

    function _nestTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 destinationId
    ) internal virtual {
        _transfer(from, to, tokenId, true, destinationId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId,
        bool isNft,
        uint256 destinationId
    ) private {
        (address directOwner, uint256 fromTokenId, ) = _directOwnerOf(tokenId);
        if (directOwner != from) revert ERC721TransferFromIncorrectOwner();
        if (to == address(0)) revert ERC721TransferToTheZeroAddress();
        if (isNft) {
            _isNestableContract(to, 2);

            if (to == address(this) && tokenId == destinationId) {
                revert RMRKNestableTransferToSelf();
            }

            _checkForInheritanceLoop(tokenId, to, destinationId);
        }

        _beforeTokenTransfer(from, to, tokenId);
        if (isNft) {
            _beforeNestedTokenTransfer(
                directOwner,
                to,
                fromTokenId,
                destinationId,
                tokenId
            );
        }

        getState()._balances[from] -= 1;
        _updateOwnerAndClearApprovals(
            tokenId,
            isNft ? destinationId : 0,
            to,
            isNft
        );
        getState()._balances[to] += 1;

        if (isNft) _sendToNFT(from, to, fromTokenId, destinationId, tokenId);

        emit Transfer(from, to, tokenId);
        _afterTokenTransfer(from, to, tokenId);
    }

    function _checkForInheritanceLoop(
        uint256 currentId,
        address targetContract,
        uint256 targetId
    ) private view {
        for (uint256 i; i < _MAX_LEVELS_TO_CHECK_FOR_INHERITANCE_LOOP; ) {
            (
                address nextOwner,
                uint256 nextOwnerTokenId,
                bool isNft
            ) = IRMRKNestable(targetContract).directOwnerOf(targetId);
            // If there's a final address, we're good. There's no loop.
            if (!isNft) {
                return;
            }
            // Ff the current nft is an ancestor at some point, there is an inheritance loop
            if (nextOwner == address(this) && nextOwnerTokenId == currentId) {
                revert RMRKNestableTransferToDescendant();
            }
            // We reuse the parameters to save some contract size
            targetContract = nextOwner;
            targetId = nextOwnerTokenId;
            unchecked {
                ++i;
            }
        }
        revert RMRKNestableTooDeep();
    }

    function _updateOwnerAndClearApprovals(
        uint256 tokenId,
        uint256 destinationId,
        address to,
        bool isNft
    ) internal {
        getNestableState()._RMRKOwners[tokenId] = RMRKOwner({
            ownerAddress: to,
            tokenId: destinationId,
            isNft: isNft
        });

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);
        _cleanApprovals(tokenId);
    }

    function _cleanApprovals(uint256 tokenId) internal virtual {}

    function _exists(uint256 tokenId)
        internal
        view
        virtual
        override
        returns (bool)
    {
        return
            getNestableState()._RMRKOwners[tokenId].ownerAddress != address(0);
    }

    // ------------------------ CHILD MANAGEMENT ------------------------
    function _addChild(uint256 parentTokenId, uint256 childTokenId)
        internal
        virtual
    {
        _requireMinted(parentTokenId);

        address childContractAddress = _msgSender();
        _isNestableContract(childContractAddress, 0);

        (bool isDuplicate, , ) = _hasChild(
            parentTokenId,
            childContractAddress,
            childTokenId
        );
        if (isDuplicate) revert RMRKDuplicateAdd();

        _beforeAddChild(parentTokenId, childContractAddress, childTokenId);

        IRMRKNestable childTokenContract = IRMRKNestable(childContractAddress);
        (address _parentContract, uint256 _parentTokenId, ) = childTokenContract
            .directOwnerOf(childTokenId);
        if (_parentContract != address(this) || _parentTokenId != parentTokenId)
            revert RMRKParentChildMismatch();

        Child memory child = Child({
            contractAddress: childContractAddress,
            tokenId: childTokenId
        });

        _addChildToPending(parentTokenId, child);
        emit ChildProposed(parentTokenId, child.contractAddress, child.tokenId);

        _afterAddChild(parentTokenId, childContractAddress, childTokenId);
    }

    function _acceptChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId
    ) internal virtual {
        NestableStorage.State storage s = getNestableState();
        uint256 index = s._posInChildArray[childContractAddress][childTokenId];

        Child memory child = s._pendingChildren[tokenId][index];

        _isOverLength(tokenId, index, true);

        if (
            child.contractAddress != childContractAddress ||
            child.tokenId != childTokenId
        ) {
            revert RMRKParentChildMismatch();
        }

        _beforeAcceptChild(tokenId, childContractAddress, childTokenId);

        _removeItemByIndexAndUpdateLastChildIndex(
            s._pendingChildren[tokenId],
            index
        );

        _addChildToChildren(tokenId, child);
        emit ChildAccepted(tokenId, child.contractAddress, child.tokenId);

        _afterAcceptChild(tokenId, childContractAddress, childTokenId);
    }

    function _unnestChild(
        uint256 tokenId,
        address to,
        address childContractAddress,
        uint256 childTokenId,
        bool isPending
    ) internal virtual {
        NestableStorage.State storage ns = getNestableState();
        uint256 index = ns._posInChildArray[childContractAddress][childTokenId];

        _isOverLength(tokenId, index, isPending);

        Child[] storage children = isPending
            ? ns._pendingChildren[tokenId]
            : ns._activeChildren[tokenId];

        Child memory child = children[index];

        if (
            child.contractAddress != childContractAddress ||
            child.tokenId != childTokenId
        ) {
            revert RMRKParentChildMismatch();
        }

        _beforeUnnestChild(
            tokenId,
            childContractAddress,
            childTokenId,
            isPending
        );

        delete ns._posInChildArray[childContractAddress][childTokenId];
        _removeItemByIndexAndUpdateLastChildIndex(children, index);

        if (to != address(0)) {
            IERC721(childContractAddress).safeTransferFrom(
                address(this),
                to,
                childTokenId
            );
        }

        emit ChildUnnested(
            tokenId,
            childContractAddress,
            childTokenId,
            isPending
        );

        _afterUnnestChild(
            tokenId,
            childContractAddress,
            childTokenId,
            isPending
        );
    }

    /**
     * @dev Adds an instance of Child to the pending children array for tokenId. This is hardcoded to be 128 by default.
     */
    function _addChildToPending(uint256 tokenId, Child memory child) internal {
        NestableStorage.State storage ns = getNestableState();
        uint256 len = ns._pendingChildren[tokenId].length;
        if (len < 128) {
            ns._posInChildArray[child.contractAddress][child.tokenId] = len;
            ns._pendingChildren[tokenId].push(child);
        } else {
            revert RMRKMaxPendingChildrenReached();
        }
    }

    /**
     * @dev Adds an instance of Child to the children array for tokenId.
     */
    function _addChildToChildren(uint256 tokenId, Child memory child) internal {
        NestableStorage.State storage ns = getNestableState();

        ns._posInChildArray[child.contractAddress][child.tokenId] = ns
            ._activeChildren[tokenId]
            .length;

        ns._activeChildren[tokenId].push(child);
    }

    // ------------------------ HOOKS ------------------------
    function _beforeNestedTokenTransfer(
        address from,
        address to,
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 tokenId
    ) internal virtual {}

    function _afterNestedTokenTransfer(
        address from,
        address to,
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 tokenId
    ) internal virtual {}

    function _beforeAddChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId
    ) internal virtual {}

    function _afterAddChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId
    ) internal virtual {}

    function _beforeAcceptChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId
    ) internal virtual {}

    function _afterAcceptChild(
        uint256 parentId,
        address childContractAddress,
        uint256 childTokenId
    ) internal virtual {}

    function _beforeUnnestChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId,
        bool isPending
    ) internal virtual {}

    function _afterUnnestChild(
        uint256 tokenId,
        address childContractAddress,
        uint256 childTokenId,
        bool isPending
    ) internal virtual {}

    function _beforeRejectAllChildren(uint256 tokenId) internal virtual {}

    function _afterRejectAllChildren(uint256 tokenId) internal virtual {}

    // ------------------------ HELPERS ------------------------

    // For child storage array
    function _removeItemByIndex(Child[] storage array, uint256 index) internal {
        array[index] = array[array.length - 1];
        array.pop();
    }

    function _removeItemByIndexAndUpdateLastChildIndex(
        Child[] storage array,
        uint256 index
    ) internal {
        uint256 len = array.length;
        Child storage lastChild = array[len - 1];
        address lastChildContract = lastChild.contractAddress;
        uint256 lastChildTokenId = lastChild.tokenId;

        // after this operation, the last child will replace the target child position in `_children`/`_pendingChildren`
        _removeItemByIndex(array, index);

        // so have to change last child's index record in `posInChildArray`
        getNestableState()._posInChildArray[lastChildContract][
            lastChildTokenId
        ] = index;
    }

    function _isNestableContract(address contractAddress, uint256 errorIndex)
        internal
        view
    {
        if (!contractAddress.isContract()) revert RMRKIsNotContract();
        if (
            !IERC165(contractAddress).supportsInterface(
                type(IRMRKNestable).interfaceId
            )
        ) {
            if (errorIndex == 1) {
                revert RMRKMintToNonRMRKImplementer();
            } else if (errorIndex == 2) {
                revert RMRKNestableTransferToNonRMRKNestableImplementer();
            } else {
                revert RMRKIsNotNestableImplementer();
            }
        }
    }

    function _isOverLength(
        uint256 tokenId,
        uint256 index,
        bool isPending
    ) internal view {
        if (isPending) {
            if (getNestableState()._pendingChildren[tokenId].length <= index)
                revert RMRKPendingChildIndexOutOfRange();
        } else {
            if (getNestableState()._activeChildren[tokenId].length <= index)
                revert RMRKChildIndexOutOfRange();
        }
    }
}