// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibDiamond} from "./library/LibDiamond.sol";
import {IERC165, IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IDiamondLoupe} from "./interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IRMRKNestable, ILightmNestable} from "./interfaces/ILightmNestable.sol";
import {IRMRKMultiAsset, ILightmMultiAsset} from "./interfaces/ILightmMultiAsset.sol";
import {ILightmEquippable} from "./interfaces/ILightmEquippable.sol";
import {IRMRKCollectionMetadata} from "./interfaces/IRMRKCollectionMetadata.sol";
import {ERC721Storage, MultiAssetStorage, EquippableStorage, CollectionMetadataStorage, LightmImplStorage} from "./internalFunctionSet/Storage.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init funciton if you need to.

contract LightmInit {
    struct InitStruct {
        string name;
        string symbol;
        string fallbackURI;
        string collectionMetadataURI;
    }

    // You can add parameters to this function in order to pass in
    // data to set your own state variables
    function init(InitStruct calldata _initStruct, address _owner) external {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC721).interfaceId] = true;
        ds.supportedInterfaces[type(IERC721Metadata).interfaceId] = true;
        ds.supportedInterfaces[type(IRMRKNestable).interfaceId] = true;
        ds.supportedInterfaces[type(ILightmNestable).interfaceId] = true;
        ds.supportedInterfaces[type(IRMRKMultiAsset).interfaceId] = true;
        ds.supportedInterfaces[type(ILightmMultiAsset).interfaceId] = true;
        ds.supportedInterfaces[type(ILightmEquippable).interfaceId] = true;
        ds.supportedInterfaces[
            type(IRMRKCollectionMetadata).interfaceId
        ] = true;

        // add your own state variables
        // EIP-2535 specifies that the `diamondCut` function takes two optional
        // arguments: address _init and bytes calldata _calldata
        // These arguments are used to execute an arbitrary function using delegatecall
        // in order to set state variables in the diamond during deployment or an upgrade
        // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface
        LightmImplStorage.State storage lis = LightmImplStorage.getState();
        lis._owner = _owner;

        ERC721Storage.State storage s = ERC721Storage.getState();
        s._name = _initStruct.name;
        s._symbol = _initStruct.symbol;

        MultiAssetStorage.State storage mrs = MultiAssetStorage
            .getState();
        mrs._fallbackURI = _initStruct.fallbackURI;

        CollectionMetadataStorage.State storage cms = CollectionMetadataStorage
            .getState();
        cms._collectionMetadata = _initStruct.collectionMetadataURI;
    }
}
