// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { TreeNFT } from "../src/TreeNFT.sol";
import { ITreeRegistry } from "../src/interfaces/ITreeRegistry.sol";

contract TreeNFTTest is Test {
    TreeRegistry internal registry;
    TreeNFT internal nft;

    address internal admin = makeAddr("admin");
    address internal sponsor = makeAddr("sponsor");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    uint256 internal treeId;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TreeMinted(uint256 indexed treeId, uint256 indexed tokenId, address owner);

    function setUp() public {
        vm.startPrank(admin);
        registry = new TreeRegistry();
        nft = new TreeNFT(address(registry));

        nft.grantRole(nft.MINTER_ROLE(), address(this));
        nft.grantRole(nft.PAUSER_ROLE(), admin);

        registry.grantRole(registry.OPERATOR_ROLE(), admin);
        registry.createProject("JTG-001", "Central Java #001", "bafyproject", admin);
        treeId = registry.registerTree(1, "TREE-JTG-000192", "bafytree", 0, 0, uint64(block.timestamp));
        vm.stopPrank();
    }

    function test_Mint() public {
        vm.expectEmit(true, true, true, false, address(nft));
        emit Transfer(address(0), sponsor, treeId);
        vm.expectEmit(true, true, false, true, address(nft));
        emit TreeMinted(treeId, treeId, sponsor);

        uint256 tokenId = nft.mint(sponsor, treeId);

        assertEq(tokenId, treeId);
        assertEq(nft.ownerOf(treeId), sponsor);
        assertEq(nft.balanceOf(sponsor), 1);
        assertTrue(nft.minted(treeId));
    }

    function test_Mint_RevertsOnDuplicate() public {
        nft.mint(sponsor, treeId);

        vm.expectRevert(abi.encodeWithSelector(TreeNFT.AlreadyMinted.selector, treeId));
        nft.mint(bob, treeId);
    }

    function test_Mint_RevertsForUnknownTree() public {
        vm.expectRevert(abi.encodeWithSelector(TreeNFT.TreeNotFound.selector, 999));
        nft.mint(sponsor, 999);
    }

    function test_Mint_RevertsForZeroAddress() public {
        vm.expectRevert(TreeNFT.ZeroAddress.selector);
        nft.mint(address(0), treeId);
    }

    function test_Mint_RevertsWithoutMinterRole() public {
        bytes32 minterRole = nft.MINTER_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, minterRole)
        );
        nft.mint(stranger, treeId);
    }

    function test_Mint_RevertsWhenPaused() public {
        vm.prank(admin);
        nft.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.mint(sponsor, treeId);
    }

    function test_TokenURI_ResolvesRegistryMetadata() public {
        nft.mint(sponsor, treeId);

        assertEq(nft.tokenURI(treeId), "ipfs://bafytree");

        vm.prank(admin);
        registry.updateTreeMetadata(treeId, "bafyupdated");

        assertEq(nft.tokenURI(treeId), "ipfs://bafyupdated");
    }

    function test_TokenURI_RevertsForUnknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 123));
        nft.tokenURI(123);
    }

    function test_Transfer() public {
        nft.mint(sponsor, treeId);

        vm.expectEmit(true, true, true, false, address(nft));
        emit Transfer(sponsor, bob, treeId);

        vm.prank(sponsor);
        nft.transferFrom(sponsor, bob, treeId);

        assertEq(nft.ownerOf(treeId), bob);
    }

    function test_Transfer_RevertsWhenPaused() public {
        nft.mint(sponsor, treeId);

        vm.prank(admin);
        nft.pause();

        vm.prank(sponsor);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.transferFrom(sponsor, bob, treeId);
    }

    function test_SupportsInterface() public view {
        assertTrue(nft.supportsInterface(0x80ac58cd));
        assertTrue(nft.supportsInterface(0x7965db0b));
        assertFalse(nft.supportsInterface(0xffffffff));
    }

    function test_TreeRegistryImmutable() public view {
        assertEq(address(nft.treeRegistry()), address(registry));
    }
}
