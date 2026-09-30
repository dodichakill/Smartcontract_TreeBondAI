// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVerificationRegistry {
    struct Verification {
        uint256 id;
        uint256 treeId;
        uint256 timestamp;
        uint16 healthScore;
        uint16 growthScore;
        uint16 anomalyRisk;
        address verifier;
        bytes32 evidenceHash;
        string evidenceCID;
    }

    function submitVerification(
        uint256 treeId,
        uint16 healthScore,
        uint16 growthScore,
        uint16 anomalyRisk,
        bytes32 evidenceHash,
        string calldata evidenceCID,
        address verifier
    ) external returns (uint256 verificationId);

    function getVerification(uint256 treeId, uint256 index) external view returns (Verification memory);

    function getLatestVerification(uint256 treeId) external view returns (Verification memory);

    function getVerifications(uint256 treeId, uint256 offset, uint256 limit)
        external
        view
        returns (Verification[] memory);

    function verificationCount(uint256 treeId) external view returns (uint256);

    function totalVerificationCount() external view returns (uint256);

    function isEvidenceHashUsed(uint256 treeId, bytes32 evidenceHash) external view returns (bool);
}
