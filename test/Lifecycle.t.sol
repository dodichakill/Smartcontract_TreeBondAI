// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { TreeNFT } from "../src/TreeNFT.sol";
import { TreeBond } from "../src/TreeBond.sol";
import { VerificationRegistry } from "../src/VerificationRegistry.sol";
import { ITreeRegistry } from "../src/interfaces/ITreeRegistry.sol";
import { IVerificationRegistry } from "../src/interfaces/IVerificationRegistry.sol";

contract LifecycleTest is Test {
    TreeRegistry internal registry;
    TreeNFT internal nft;
    TreeBond internal bond;
    VerificationRegistry internal verification;

    address internal admin = makeAddr("admin");
    address internal sponsor = makeAddr("sponsor");
    address internal projectOperator = makeAddr("projectOperator");
    address internal treasury = makeAddr("treasury");
    address internal humanVerifier = makeAddr("humanVerifier");

    uint256 internal constant PRICE = 1 ether;
    uint16 internal constant FEE_BPS = 1_000;

    function setUp() public {
        vm.startPrank(admin);
        registry = new TreeRegistry();
        nft = new TreeNFT(address(registry));
        bond = new TreeBond(address(registry), address(nft), treasury, FEE_BPS);
        verification = new VerificationRegistry(address(registry));

        registry.grantRole(registry.OPERATOR_ROLE(), admin);
        registry.grantRole(registry.VERIFIER_ROLE(), admin);
        registry.grantRole(registry.SPONSOR_ROLE(), address(bond));
        nft.grantRole(nft.MINTER_ROLE(), address(bond));
        bond.grantRole(bond.OPERATOR_ROLE(), admin);
        verification.grantRole(verification.ORACLE_ROLE(), admin);

        bond.setDefaultTreePrice(PRICE);
        vm.stopPrank();

        vm.deal(sponsor, 10 ether);
    }

    function _registerTree() internal returns (uint256 treeId) {
        vm.startPrank(admin);
        registry.createProject("JTG-001", "Central Java Reforestation #001", "bafyproject", projectOperator);
        treeId =
            registry.registerTree(1, "TREE-JTG-000192", "bafyinitial", -7_123_000, 110_456_000, uint64(block.timestamp));
        vm.stopPrank();
    }

    function test_FullLifecycle() public {
        uint256 treeId = _registerTree();
        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.REGISTERED));

        vm.startPrank(admin);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.AVAILABLE);
        vm.stopPrank();

        vm.prank(sponsor);
        uint256 tokenId = bond.sponsorTree{ value: PRICE }(treeId);

        assertEq(tokenId, treeId);
        assertEq(nft.ownerOf(treeId), sponsor);
        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.SPONSORED));
        assertEq(verification.verificationCount(treeId), 0);

        vm.prank(admin);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.MONITORING);

        vm.prank(admin);
        registry.updateTreeMetadata(treeId, "bafymonitoring1");
        assertEq(nft.tokenURI(treeId), "ipfs://bafymonitoring1");

        bytes32 hash1 = keccak256("evidence-2026-12-01");
        vm.prank(admin);
        verification.submitVerification(treeId, 94, 87, 4, hash1, "bafyevidence1", humanVerifier);

        IVerificationRegistry.Verification memory latest = verification.getLatestVerification(treeId);
        assertEq(latest.healthScore, 94);
        assertEq(latest.growthScore, 87);
        assertEq(latest.anomalyRisk, 4);
        assertEq(latest.verifier, humanVerifier);

        bytes32 hash2 = keccak256("evidence-2027-01-01");
        vm.prank(admin);
        verification.submitVerification(treeId, 92, 90, 2, hash2, "bafyevidence2", humanVerifier);

        assertEq(verification.verificationCount(treeId), 2);
        assertEq(verification.totalVerificationCount(), 2);
        assertEq(verification.getLatestVerification(treeId).evidenceHash, hash2);

        vm.startPrank(admin);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.MATURE);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.DEAD);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.REPLACED);
        vm.stopPrank();

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.REPLACED));
        assertEq(nft.ownerOf(treeId), sponsor);

        uint256 platformFee = PRICE * FEE_BPS / 10_000;
        uint256 operatorPayout = PRICE - platformFee;

        uint256 treasuryBefore = treasury.balance;
        vm.prank(treasury);
        bond.withdraw();
        assertEq(treasury.balance, treasuryBefore + platformFee);

        uint256 operatorBefore = projectOperator.balance;
        vm.prank(projectOperator);
        bond.withdraw();
        assertEq(projectOperator.balance, operatorBefore + operatorPayout);

        assertEq(address(bond).balance, 0);
    }

    function test_RejectionPath() public {
        uint256 treeId = _registerTree();

        vm.startPrank(admin);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.REJECTED);
        vm.stopPrank();

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.REJECTED));

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.TreeNotAvailable.selector, treeId));
        bond.sponsorTree{ value: PRICE }(treeId);
    }

    function test_DisputePath() public {
        uint256 treeId = _registerTree();

        vm.startPrank(admin);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.AVAILABLE);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.DISPUTED);
        vm.stopPrank();

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.DISPUTED));
    }
}
