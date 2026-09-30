// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { ITreeRegistry } from "../src/interfaces/ITreeRegistry.sol";

contract TreeRegistryTest is Test {
    TreeRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal verifier = makeAddr("verifier");
    address internal bond = makeAddr("bond");
    address internal payout = makeAddr("payout");
    address internal stranger = makeAddr("stranger");

    event ProjectCreated(uint256 indexed projectId, address indexed operator, string code);
    event TreeRegistered(uint256 indexed treeId, uint256 indexed projectId);
    event TreeStatusChanged(uint256 indexed treeId, ITreeRegistry.TreeStatus status);
    event TreeMetadataUpdated(uint256 indexed treeId, string metadataCID);

    function setUp() public {
        vm.prank(admin);
        registry = new TreeRegistry();

        vm.startPrank(admin);
        registry.grantRole(registry.OPERATOR_ROLE(), operator);
        registry.grantRole(registry.VERIFIER_ROLE(), verifier);
        registry.grantRole(registry.SPONSOR_ROLE(), bond);
        registry.grantRole(registry.PAUSER_ROLE(), admin);
        vm.stopPrank();
    }

    function _createProject() internal returns (uint256 projectId) {
        vm.prank(operator);
        projectId = registry.createProject("JTG-001", "Central Java Reforestation #001", "bafyproject", payout);
    }

    function _registerTree(uint256 projectId) internal returns (uint256 treeId) {
        vm.prank(operator);
        treeId = registry.registerTree(
            projectId, "TREE-JTG-000192", "bafytree", -7_123_000, 110_456_000, uint64(block.timestamp)
        );
    }

    function _advanceToAvailable(uint256 treeId) internal {
        vm.startPrank(operator);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.AVAILABLE);
        vm.stopPrank();
    }

    function test_CreateProject() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit ProjectCreated(1, payout, "JTG-001");

        uint256 projectId = _createProject();

        ITreeRegistry.Project memory project = registry.getProject(projectId);

        assertEq(projectId, 1);
        assertEq(project.id, 1);
        assertEq(project.code, "JTG-001");
        assertEq(project.name, "Central Java Reforestation #001");
        assertEq(project.metadataCID, "bafyproject");
        assertEq(project.operator, payout);
        assertEq(project.createdAt, uint64(block.timestamp));
        assertTrue(project.active);
        assertEq(registry.projectCount(), 1);
        assertTrue(registry.projectExists(projectId));
    }

    function test_CreateProject_RevertsForNonOperator() public {
        bytes32 operatorRole = registry.OPERATOR_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, operatorRole)
        );
        registry.createProject("JTG-001", "Central Java #001", "bafy", payout);
    }

    function test_CreateProject_RevertsForZeroOperator() public {
        vm.prank(operator);
        vm.expectRevert(TreeRegistry.ZeroAddress.selector);
        registry.createProject("JTG-001", "Central Java #001", "bafy", address(0));
    }

    function test_CreateProject_RevertsForEmptyCode() public {
        vm.prank(operator);
        vm.expectRevert(TreeRegistry.EmptyString.selector);
        registry.createProject("", "Central Java #001", "bafy", payout);
    }

    function test_RegisterTree() public {
        uint256 projectId = _createProject();

        vm.expectEmit(true, true, false, true, address(registry));
        emit TreeRegistered(1, projectId);
        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(1, ITreeRegistry.TreeStatus.REGISTERED);

        uint256 treeId = _registerTree(projectId);
        ITreeRegistry.Tree memory tree = registry.getTree(treeId);

        assertEq(treeId, 1);
        assertEq(tree.id, 1);
        assertEq(tree.projectId, projectId);
        assertEq(tree.treeCode, "TREE-JTG-000192");
        assertEq(tree.metadataCID, "bafytree");
        assertEq(tree.latitude, int64(-7_123_000));
        assertEq(tree.longitude, int64(110_456_000));
        assertEq(tree.plantedAt, uint64(block.timestamp));
        assertEq(uint8(tree.status), uint8(ITreeRegistry.TreeStatus.REGISTERED));
        assertEq(registry.treeCount(), 1);
        assertTrue(registry.treeExists(treeId));
    }

    function test_RegisterTree_RevertsForUnknownProject() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreeRegistry.ProjectNotFound.selector, 99));
        registry.registerTree(99, "TREE-1", "bafy", 0, 0, uint64(block.timestamp));
    }

    function test_RegisterTree_RevertsForInactiveProject() public {
        uint256 projectId = _createProject();
        vm.prank(operator);
        registry.setProjectActive(projectId, false);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreeRegistry.ProjectNotActive.selector, projectId));
        registry.registerTree(projectId, "TREE-1", "bafy", 0, 0, uint64(block.timestamp));
    }

    function test_RegisterTree_RevertsForEmptyFields() public {
        uint256 projectId = _createProject();

        vm.startPrank(operator);
        vm.expectRevert(TreeRegistry.EmptyString.selector);
        registry.registerTree(projectId, "", "bafy", 0, 0, uint64(block.timestamp));

        vm.expectRevert(TreeRegistry.EmptyString.selector);
        registry.registerTree(projectId, "TREE-1", "", 0, 0, uint64(block.timestamp));
        vm.stopPrank();
    }

    function test_UpdateStatus_FullHappyPath() public {
        uint256 treeId = _registerTree(_createProject());

        vm.startPrank(operator);
        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);

        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(treeId, ITreeRegistry.TreeStatus.VERIFIED);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);

        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(treeId, ITreeRegistry.TreeStatus.AVAILABLE);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.AVAILABLE);
        vm.stopPrank();

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.AVAILABLE));
    }

    function test_UpdateStatus_VerifierCanUpdate() public {
        uint256 treeId = _registerTree(_createProject());

        vm.prank(verifier);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.PENDING_VERIFICATION));
    }

    function test_UpdateStatus_RevertsOnInvalidTransition() public {
        uint256 treeId = _registerTree(_createProject());

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreeRegistry.InvalidTreeStatus.selector,
                ITreeRegistry.TreeStatus.REGISTERED,
                ITreeRegistry.TreeStatus.VERIFIED
            )
        );
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);
    }

    function test_UpdateStatus_RevertsForUnknownTree() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(TreeRegistry.TreeNotFound.selector, 42));
        registry.updateTreeStatus(42, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
    }

    function test_UpdateStatus_RevertsWithoutRole() public {
        uint256 treeId = _registerTree(_createProject());
        bytes32 operatorRole = registry.OPERATOR_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, operatorRole)
        );
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
    }

    function test_UpdateStatus_CanDisputeFromAnyActiveStatus() public {
        uint256 treeId = _registerTree(_createProject());
        _advanceToAvailable(treeId);

        vm.prank(verifier);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.DISPUTED);

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.DISPUTED));
    }

    function test_MarkSponsored() public {
        uint256 treeId = _registerTree(_createProject());
        _advanceToAvailable(treeId);

        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(treeId, ITreeRegistry.TreeStatus.SPONSORED);

        vm.prank(bond);
        registry.markSponsored(treeId);

        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.SPONSORED));
    }

    function test_MarkSponsored_RevertsWhenNotAvailable() public {
        uint256 treeId = _registerTree(_createProject());

        vm.prank(bond);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreeRegistry.InvalidTreeStatus.selector,
                ITreeRegistry.TreeStatus.REGISTERED,
                ITreeRegistry.TreeStatus.SPONSORED
            )
        );
        registry.markSponsored(treeId);
    }

    function test_MarkSponsored_RevertsWithoutSponsorRole() public {
        uint256 treeId = _registerTree(_createProject());
        _advanceToAvailable(treeId);
        bytes32 sponsorRole = registry.SPONSOR_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, sponsorRole)
        );
        registry.markSponsored(treeId);
    }

    function test_UpdateTreeMetadata() public {
        uint256 treeId = _registerTree(_createProject());

        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeMetadataUpdated(treeId, "bafyupdated");

        vm.prank(operator);
        registry.updateTreeMetadata(treeId, "bafyupdated");

        assertEq(registry.getTree(treeId).metadataCID, "bafyupdated");
    }

    function test_TreeMetadataURI() public {
        uint256 treeId = _registerTree(_createProject());
        assertEq(registry.treeMetadataURI(treeId), "ipfs://bafytree");
    }

    function test_GetTree_RevertsForUnknownTree() public {
        vm.expectRevert(abi.encodeWithSelector(TreeRegistry.TreeNotFound.selector, 7));
        registry.getTree(7);
    }

    function test_Pause_BlocksWritesAndAllowsReads() public {
        uint256 projectId = _createProject();
        uint256 treeId = _registerTree(projectId);

        vm.prank(admin);
        registry.pause();

        vm.prank(operator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);

        vm.prank(operator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.registerTree(projectId, "TREE-2", "bafy", 0, 0, uint64(block.timestamp));

        assertEq(registry.treeCount(), 1);

        vm.prank(admin);
        registry.unpause();

        vm.prank(operator);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.PENDING_VERIFICATION));
    }

    function test_IsTransitionAllowed() public view {
        assertTrue(
            registry.isTransitionAllowed(
                ITreeRegistry.TreeStatus.REGISTERED, ITreeRegistry.TreeStatus.PENDING_VERIFICATION
            )
        );
        assertFalse(registry.isTransitionAllowed(ITreeRegistry.TreeStatus.DRAFT, ITreeRegistry.TreeStatus.VERIFIED));
        assertTrue(registry.isTransitionAllowed(ITreeRegistry.TreeStatus.MONITORING, ITreeRegistry.TreeStatus.DEAD));
        assertFalse(
            registry.isTransitionAllowed(ITreeRegistry.TreeStatus.DISPUTED, ITreeRegistry.TreeStatus.REGISTERED)
        );
    }

    function testFuzz_RegisterTreeStoresCoordinates(int64 latitude, int64 longitude) public {
        latitude = int64(bound(latitude, -90_000_000, 90_000_000));
        longitude = int64(bound(longitude, -180_000_000, 180_000_000));
        uint256 projectId = _createProject();

        vm.prank(operator);
        uint256 treeId =
            registry.registerTree(projectId, "TREE-FUZZ", "bafy", latitude, longitude, uint64(block.timestamp));

        ITreeRegistry.Tree memory tree = registry.getTree(treeId);
        assertEq(tree.latitude, latitude);
        assertEq(tree.longitude, longitude);
    }
}
