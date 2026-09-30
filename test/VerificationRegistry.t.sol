// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { VerificationRegistry } from "../src/VerificationRegistry.sol";
import { IVerificationRegistry } from "../src/interfaces/IVerificationRegistry.sol";

contract VerificationRegistryTest is Test {
    TreeRegistry internal registry;
    VerificationRegistry internal verification;

    address internal admin = makeAddr("admin");
    address internal oracle = makeAddr("oracle");
    address internal humanVerifier = makeAddr("humanVerifier");
    address internal stranger = makeAddr("stranger");

    uint256 internal treeId;
    uint256 internal secondTreeId;

    bytes32 internal constant HASH_1 = keccak256("evidence-1");
    bytes32 internal constant HASH_2 = keccak256("evidence-2");

    event VerificationSubmitted(uint256 indexed treeId, uint256 timestamp, bytes32 evidenceHash);
    event VerificationRecorded(
        uint256 indexed verificationId,
        uint256 indexed treeId,
        address indexed verifier,
        uint16 healthScore,
        uint16 growthScore,
        uint16 anomalyRisk,
        bytes32 evidenceHash,
        string evidenceCID
    );

    function setUp() public {
        vm.startPrank(admin);
        registry = new TreeRegistry();
        verification = new VerificationRegistry(address(registry));

        verification.grantRole(verification.ORACLE_ROLE(), oracle);
        verification.grantRole(verification.PAUSER_ROLE(), admin);

        registry.grantRole(registry.OPERATOR_ROLE(), admin);
        registry.createProject("JTG-001", "Central Java #001", "bafyproject", admin);
        treeId = registry.registerTree(1, "TREE-JTG-000192", "bafytree", 0, 0, uint64(block.timestamp));
        secondTreeId = registry.registerTree(1, "TREE-JTG-000193", "bafytree2", 0, 0, uint64(block.timestamp));
        vm.stopPrank();
    }

    function _submit(uint256 targetTreeId, bytes32 evidenceHash, uint16 health, uint16 growth, uint16 anomaly)
        internal
        returns (uint256 verificationId)
    {
        vm.prank(oracle);
        verificationId = verification.submitVerification(
            targetTreeId, health, growth, anomaly, evidenceHash, "bafyevidence", humanVerifier
        );
    }

    function test_SubmitVerification() public {
        vm.expectEmit(true, false, false, true, address(verification));
        emit VerificationSubmitted(treeId, block.timestamp, HASH_1);
        vm.expectEmit(true, true, true, true, address(verification));
        emit VerificationRecorded(1, treeId, humanVerifier, 94, 87, 4, HASH_1, "bafyevidence");

        uint256 verificationId = _submit(treeId, HASH_1, 94, 87, 4);

        IVerificationRegistry.Verification memory record = verification.getVerification(treeId, 0);

        assertEq(verificationId, 1);
        assertEq(record.id, 1);
        assertEq(record.treeId, treeId);
        assertEq(record.timestamp, block.timestamp);
        assertEq(record.healthScore, 94);
        assertEq(record.growthScore, 87);
        assertEq(record.anomalyRisk, 4);
        assertEq(record.verifier, humanVerifier);
        assertEq(record.evidenceHash, HASH_1);
        assertEq(record.evidenceCID, "bafyevidence");
        assertEq(verification.verificationCount(treeId), 1);
        assertEq(verification.totalVerificationCount(), 1);
        assertTrue(verification.isEvidenceHashUsed(treeId, HASH_1));
    }

    function test_SubmitVerification_RevertsWithoutOracleRole() public {
        bytes32 oracleRole = verification.ORACLE_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, oracleRole)
        );
        verification.submitVerification(treeId, 94, 87, 4, HASH_1, "bafy", humanVerifier);
    }

    function test_SubmitVerification_RevertsForUnknownTree() public {
        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.TreeNotFound.selector, 999));
        verification.submitVerification(999, 94, 87, 4, HASH_1, "bafy", humanVerifier);
    }

    function test_SubmitVerification_RevertsForInvalidScores() public {
        vm.startPrank(oracle);
        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.InvalidScore.selector, 101));
        verification.submitVerification(treeId, 101, 87, 4, HASH_1, "bafy", humanVerifier);

        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.InvalidScore.selector, 101));
        verification.submitVerification(treeId, 94, 101, 4, HASH_1, "bafy", humanVerifier);

        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.InvalidScore.selector, 101));
        verification.submitVerification(treeId, 94, 87, 101, HASH_1, "bafy", humanVerifier);
        vm.stopPrank();
    }

    function test_SubmitVerification_RevertsForInvalidEvidence() public {
        vm.startPrank(oracle);
        vm.expectRevert(VerificationRegistry.InvalidEvidenceHash.selector);
        verification.submitVerification(treeId, 94, 87, 4, bytes32(0), "bafy", humanVerifier);

        vm.expectRevert(VerificationRegistry.EmptyString.selector);
        verification.submitVerification(treeId, 94, 87, 4, HASH_1, "", humanVerifier);

        vm.expectRevert(VerificationRegistry.ZeroAddress.selector);
        verification.submitVerification(treeId, 94, 87, 4, HASH_1, "bafy", address(0));
        vm.stopPrank();
    }

    function test_SubmitVerification_RevertsOnDuplicateEvidence() public {
        _submit(treeId, HASH_1, 94, 87, 4);

        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.DuplicateEvidence.selector, treeId, HASH_1));
        verification.submitVerification(treeId, 90, 80, 5, HASH_1, "bafyother", humanVerifier);
    }

    function test_SubmitVerification_AllowsSameHashForDifferentTrees() public {
        _submit(treeId, HASH_1, 94, 87, 4);
        _submit(secondTreeId, HASH_1, 90, 80, 5);

        assertEq(verification.verificationCount(treeId), 1);
        assertEq(verification.verificationCount(secondTreeId), 1);
        assertEq(verification.totalVerificationCount(), 2);
    }

    function test_GetLatestVerification() public {
        _submit(treeId, HASH_1, 94, 87, 4);
        _submit(treeId, HASH_2, 88, 82, 6);

        IVerificationRegistry.Verification memory latest = verification.getLatestVerification(treeId);
        assertEq(latest.id, 2);
        assertEq(latest.evidenceHash, HASH_2);
        assertEq(latest.healthScore, 88);
    }

    function test_GetLatestVerification_RevertsWhenEmpty() public {
        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.NoVerificationFound.selector, treeId));
        verification.getLatestVerification(treeId);
    }

    function test_GetVerification_RevertsOutOfBounds() public {
        _submit(treeId, HASH_1, 94, 87, 4);

        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.VerificationNotFound.selector, treeId, 1));
        verification.getVerification(treeId, 1);
    }

    function test_GetVerifications_Pagination() public {
        for (uint256 i = 0; i < 5; ++i) {
            _submit(treeId, keccak256(abi.encode("evidence", i)), 90, 80, 2);
        }

        IVerificationRegistry.Verification[] memory page = verification.getVerifications(treeId, 0, 2);
        assertEq(page.length, 2);
        assertEq(page[0].id, 1);
        assertEq(page[1].id, 2);

        page = verification.getVerifications(treeId, 4, 10);
        assertEq(page.length, 1);
        assertEq(page[0].id, 5);

        page = verification.getVerifications(treeId, 5, 10);
        assertEq(page.length, 0);

        page = verification.getVerifications(treeId, 0, 0);
        assertEq(page.length, 0);

        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.LimitTooHigh.selector, 51));
        verification.getVerifications(treeId, 0, 51);
    }

    function test_Pause_BlocksSubmit() public {
        vm.prank(admin);
        verification.pause();

        vm.prank(oracle);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        verification.submitVerification(treeId, 94, 87, 4, HASH_1, "bafy", humanVerifier);

        vm.prank(admin);
        verification.unpause();

        _submit(treeId, HASH_1, 94, 87, 4);
        assertEq(verification.verificationCount(treeId), 1);
    }

    function testFuzz_SubmitVerification_AcceptsValidScores(uint16 health, uint16 growth, uint16 anomaly) public {
        health = uint16(bound(health, 0, 100));
        growth = uint16(bound(growth, 0, 100));
        anomaly = uint16(bound(anomaly, 0, 100));

        _submit(treeId, HASH_1, health, growth, anomaly);

        IVerificationRegistry.Verification memory record = verification.getLatestVerification(treeId);
        assertEq(record.healthScore, health);
        assertEq(record.growthScore, growth);
        assertEq(record.anomalyRisk, anomaly);
    }

    function testFuzz_SubmitVerification_RejectsScoresAboveMax(uint16 health) public {
        health = uint16(bound(health, 101, type(uint16).max));

        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(VerificationRegistry.InvalidScore.selector, health));
        verification.submitVerification(treeId, health, 50, 50, HASH_1, "bafy", humanVerifier);
    }
}
