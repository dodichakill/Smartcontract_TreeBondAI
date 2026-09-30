// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ITreeRegistry } from "./interfaces/ITreeRegistry.sol";

contract TreeRegistry is ITreeRegistry, AccessControl, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");

    uint256 private _projectCount;
    uint256 private _treeCount;

    mapping(uint256 projectId => Project) private _projects;
    mapping(uint256 treeId => Tree) private _trees;
    mapping(TreeStatus from => mapping(TreeStatus to => bool)) private _allowedTransitions;

    event ProjectCreated(uint256 indexed projectId, address indexed operator, string code);
    event ProjectActiveUpdated(uint256 indexed projectId, bool active);
    event TreeRegistered(uint256 indexed treeId, uint256 indexed projectId);
    event TreeStatusChanged(uint256 indexed treeId, TreeStatus status);
    event TreeMetadataUpdated(uint256 indexed treeId, string metadataCID);

    error ZeroAddress();
    error EmptyString();
    error ProjectNotFound(uint256 projectId);
    error ProjectNotActive(uint256 projectId);
    error TreeNotFound(uint256 treeId);
    error InvalidTreeStatus(TreeStatus from, TreeStatus to);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _allow(TreeStatus.REGISTERED, TreeStatus.PENDING_VERIFICATION);
        _allow(TreeStatus.PENDING_VERIFICATION, TreeStatus.VERIFIED);
        _allow(TreeStatus.PENDING_VERIFICATION, TreeStatus.REJECTED);
        _allow(TreeStatus.VERIFIED, TreeStatus.AVAILABLE);
        _allow(TreeStatus.AVAILABLE, TreeStatus.SPONSORED);
        _allow(TreeStatus.SPONSORED, TreeStatus.MONITORING);
        _allow(TreeStatus.MONITORING, TreeStatus.MATURE);
        _allow(TreeStatus.MONITORING, TreeStatus.DEAD);
        _allow(TreeStatus.MATURE, TreeStatus.DEAD);
        _allow(TreeStatus.DEAD, TreeStatus.REPLACED);

        for (uint8 i = 1; i < uint8(TreeStatus.DISPUTED); ++i) {
            _allowedTransitions[TreeStatus(i)][TreeStatus.DISPUTED] = true;
        }
    }

    modifier onlyOperatorOrVerifier() {
        if (!hasRole(OPERATOR_ROLE, msg.sender) && !hasRole(VERIFIER_ROLE, msg.sender)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, OPERATOR_ROLE);
        }
        _;
    }

    function createProject(string calldata code, string calldata name, string calldata metadataCID, address operator)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
        returns (uint256 projectId)
    {
        if (operator == address(0)) revert ZeroAddress();
        if (bytes(code).length == 0 || bytes(name).length == 0) revert EmptyString();

        projectId = ++_projectCount;
        _projects[projectId] = Project({
            id: projectId,
            code: code,
            name: name,
            metadataCID: metadataCID,
            operator: operator,
            createdAt: uint64(block.timestamp),
            active: true
        });

        emit ProjectCreated(projectId, operator, code);
    }

    function setProjectActive(uint256 projectId, bool active) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (!projectExists(projectId)) revert ProjectNotFound(projectId);
        _projects[projectId].active = active;
        emit ProjectActiveUpdated(projectId, active);
    }

    function registerTree(
        uint256 projectId,
        string calldata treeCode,
        string calldata metadataCID,
        int64 latitude,
        int64 longitude,
        uint64 plantedAt
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint256 treeId) {
        if (!projectExists(projectId)) revert ProjectNotFound(projectId);
        if (!_projects[projectId].active) revert ProjectNotActive(projectId);
        if (bytes(treeCode).length == 0 || bytes(metadataCID).length == 0) revert EmptyString();

        treeId = ++_treeCount;
        _trees[treeId] = Tree({
            id: treeId,
            projectId: projectId,
            treeCode: treeCode,
            metadataCID: metadataCID,
            latitude: latitude,
            longitude: longitude,
            plantedAt: plantedAt,
            status: TreeStatus.REGISTERED
        });

        emit TreeRegistered(treeId, projectId);
        emit TreeStatusChanged(treeId, TreeStatus.REGISTERED);
    }

    function updateTreeStatus(uint256 treeId, TreeStatus newStatus) external onlyOperatorOrVerifier whenNotPaused {
        Tree storage tree = _requireTree(treeId);
        if (!_allowedTransitions[tree.status][newStatus]) {
            revert InvalidTreeStatus(tree.status, newStatus);
        }
        tree.status = newStatus;
        emit TreeStatusChanged(treeId, newStatus);
    }

    function markSponsored(uint256 treeId) external onlyRole(SPONSOR_ROLE) whenNotPaused {
        Tree storage tree = _requireTree(treeId);
        if (tree.status != TreeStatus.AVAILABLE) {
            revert InvalidTreeStatus(tree.status, TreeStatus.SPONSORED);
        }
        tree.status = TreeStatus.SPONSORED;
        emit TreeStatusChanged(treeId, TreeStatus.SPONSORED);
    }

    function updateTreeMetadata(uint256 treeId, string calldata metadataCID)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        if (bytes(metadataCID).length == 0) revert EmptyString();
        Tree storage tree = _requireTree(treeId);
        tree.metadataCID = metadataCID;
        emit TreeMetadataUpdated(treeId, metadataCID);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getTree(uint256 treeId) external view returns (Tree memory) {
        return _requireTree(treeId);
    }

    function getProject(uint256 projectId) external view returns (Project memory) {
        if (!projectExists(projectId)) revert ProjectNotFound(projectId);
        return _projects[projectId];
    }

    function treeExists(uint256 treeId) external view returns (bool) {
        return _trees[treeId].id != 0;
    }

    function projectExists(uint256 projectId) public view returns (bool) {
        return _projects[projectId].id != 0;
    }

    function treeStatus(uint256 treeId) external view returns (TreeStatus) {
        return _requireTree(treeId).status;
    }

    function treeMetadataURI(uint256 treeId) external view returns (string memory) {
        return string.concat("ipfs://", _requireTree(treeId).metadataCID);
    }

    function treeCount() external view returns (uint256) {
        return _treeCount;
    }

    function projectCount() external view returns (uint256) {
        return _projectCount;
    }

    function isTransitionAllowed(TreeStatus from, TreeStatus to) external view returns (bool) {
        return _allowedTransitions[from][to];
    }

    function _requireTree(uint256 treeId) private view returns (Tree storage tree) {
        tree = _trees[treeId];
        if (tree.id == 0) revert TreeNotFound(treeId);
    }

    function _allow(TreeStatus from, TreeStatus to) private {
        _allowedTransitions[from][to] = true;
    }
}
