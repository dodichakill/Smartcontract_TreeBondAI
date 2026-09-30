// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreeRegistry {
    enum TreeStatus {
        DRAFT,
        REGISTERED,
        PENDING_VERIFICATION,
        VERIFIED,
        AVAILABLE,
        SPONSORED,
        MONITORING,
        MATURE,
        REJECTED,
        DEAD,
        REMOVED,
        REPLACED,
        DISPUTED
    }

    struct Project {
        uint256 id;
        string code;
        string name;
        string metadataCID;
        address operator;
        uint64 createdAt;
        bool active;
    }

    struct Tree {
        uint256 id;
        uint256 projectId;
        string treeCode;
        string metadataCID;
        int64 latitude;
        int64 longitude;
        uint64 plantedAt;
        TreeStatus status;
    }

    function createProject(string calldata code, string calldata name, string calldata metadataCID, address operator)
        external
        returns (uint256 projectId);

    function setProjectActive(uint256 projectId, bool active) external;

    function registerTree(
        uint256 projectId,
        string calldata treeCode,
        string calldata metadataCID,
        int64 latitude,
        int64 longitude,
        uint64 plantedAt
    ) external returns (uint256 treeId);

    function updateTreeStatus(uint256 treeId, TreeStatus newStatus) external;

    function markSponsored(uint256 treeId) external;

    function updateTreeMetadata(uint256 treeId, string calldata metadataCID) external;

    function getTree(uint256 treeId) external view returns (Tree memory);

    function getProject(uint256 projectId) external view returns (Project memory);

    function treeExists(uint256 treeId) external view returns (bool);

    function projectExists(uint256 projectId) external view returns (bool);

    function treeStatus(uint256 treeId) external view returns (TreeStatus);

    function treeMetadataURI(uint256 treeId) external view returns (string memory);

    function treeCount() external view returns (uint256);

    function projectCount() external view returns (uint256);
}
