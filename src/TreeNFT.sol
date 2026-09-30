// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ITreeRegistry } from "./interfaces/ITreeRegistry.sol";
import { ITreeNFT } from "./interfaces/ITreeNFT.sol";

contract TreeNFT is ITreeNFT, ERC721, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    ITreeRegistry public immutable treeRegistry;

    mapping(uint256 treeId => bool) public minted;

    event TreeMinted(uint256 indexed treeId, uint256 indexed tokenId, address owner);

    error ZeroAddress();
    error AlreadyMinted(uint256 treeId);
    error TreeNotFound(uint256 treeId);

    constructor(address registry) ERC721("TreeBond Tree", "TREE") {
        if (registry == address(0)) revert ZeroAddress();
        treeRegistry = ITreeRegistry(registry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 treeId) external onlyRole(MINTER_ROLE) whenNotPaused returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (minted[treeId]) revert AlreadyMinted(treeId);
        if (!treeRegistry.treeExists(treeId)) revert TreeNotFound(treeId);

        minted[treeId] = true;
        tokenId = treeId;
        _safeMint(to, tokenId);

        emit TreeMinted(treeId, tokenId, to);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return treeRegistry.treeMetadataURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }
}
