// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ITreeRegistry } from "./interfaces/ITreeRegistry.sol";
import { IVerificationRegistry } from "./interfaces/IVerificationRegistry.sol";

contract VerificationRegistry is IVerificationRegistry, AccessControl, Pausable {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint16 public constant MAX_SCORE = 100;
    uint256 public constant MAX_PAGE_SIZE = 50;

    ITreeRegistry public immutable treeRegistry;

    uint256 private _totalVerificationCount;
    mapping(uint256 treeId => Verification[]) private _verifications;
    mapping(uint256 treeId => mapping(bytes32 evidenceHash => bool)) private _evidenceHashUsed;

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

    error ZeroAddress();
    error EmptyString();
    error TreeNotFound(uint256 treeId);
    error InvalidScore(uint16 score);
    error InvalidEvidenceHash();
    error DuplicateEvidence(uint256 treeId, bytes32 evidenceHash);
    error VerificationNotFound(uint256 treeId, uint256 index);
    error NoVerificationFound(uint256 treeId);
    error LimitTooHigh(uint256 limit);

    constructor(address registry) {
        if (registry == address(0)) revert ZeroAddress();
        treeRegistry = ITreeRegistry(registry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function submitVerification(
        uint256 treeId,
        uint16 healthScore,
        uint16 growthScore,
        uint16 anomalyRisk,
        bytes32 evidenceHash,
        string calldata evidenceCID,
        address verifier
    ) external onlyRole(ORACLE_ROLE) whenNotPaused returns (uint256 verificationId) {
        if (!treeRegistry.treeExists(treeId)) revert TreeNotFound(treeId);
        if (healthScore > MAX_SCORE) revert InvalidScore(healthScore);
        if (growthScore > MAX_SCORE) revert InvalidScore(growthScore);
        if (anomalyRisk > MAX_SCORE) revert InvalidScore(anomalyRisk);
        if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();
        if (bytes(evidenceCID).length == 0) revert EmptyString();
        if (verifier == address(0)) revert ZeroAddress();
        if (_evidenceHashUsed[treeId][evidenceHash]) revert DuplicateEvidence(treeId, evidenceHash);

        _evidenceHashUsed[treeId][evidenceHash] = true;
        verificationId = ++_totalVerificationCount;

        _verifications[treeId].push(
            Verification({
                id: verificationId,
                treeId: treeId,
                timestamp: block.timestamp,
                healthScore: healthScore,
                growthScore: growthScore,
                anomalyRisk: anomalyRisk,
                verifier: verifier,
                evidenceHash: evidenceHash,
                evidenceCID: evidenceCID
            })
        );

        emit VerificationSubmitted(treeId, block.timestamp, evidenceHash);
        emit VerificationRecorded(
            verificationId, treeId, verifier, healthScore, growthScore, anomalyRisk, evidenceHash, evidenceCID
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getVerification(uint256 treeId, uint256 index) external view returns (Verification memory) {
        Verification[] storage records = _verifications[treeId];
        if (index >= records.length) revert VerificationNotFound(treeId, index);
        return records[index];
    }

    function getLatestVerification(uint256 treeId) external view returns (Verification memory) {
        Verification[] storage records = _verifications[treeId];
        if (records.length == 0) revert NoVerificationFound(treeId);
        return records[records.length - 1];
    }

    function getVerifications(uint256 treeId, uint256 offset, uint256 limit)
        external
        view
        returns (Verification[] memory result)
    {
        if (limit > MAX_PAGE_SIZE) revert LimitTooHigh(limit);

        Verification[] storage records = _verifications[treeId];
        if (offset >= records.length || limit == 0) return new Verification[](0);

        uint256 end = offset + limit;
        if (end > records.length) end = records.length;
        uint256 size = end - offset;

        result = new Verification[](size);
        for (uint256 i = 0; i < size; ++i) {
            result[i] = records[offset + i];
        }
    }

    function verificationCount(uint256 treeId) external view returns (uint256) {
        return _verifications[treeId].length;
    }

    function totalVerificationCount() external view returns (uint256) {
        return _totalVerificationCount;
    }

    function isEvidenceHashUsed(uint256 treeId, bytes32 evidenceHash) external view returns (bool) {
        return _evidenceHashUsed[treeId][evidenceHash];
    }
}
