// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ITreeRegistry } from "./interfaces/ITreeRegistry.sol";
import { ITreeNFT } from "./interfaces/ITreeNFT.sol";

contract TreeBond is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint16 public constant MAX_PLATFORM_FEE_BPS = 2_000;
    uint16 public constant BPS_DENOMINATOR = 10_000;

    ITreeRegistry public immutable treeRegistry;
    ITreeNFT public immutable treeNFT;

    address public treasury;
    uint16 public platformFeeBps;
    uint256 public defaultTreePrice;

    mapping(uint256 treeId => uint256 price) public treePrice;
    mapping(address account => uint256 amount) public pendingWithdrawals;

    event TreeSponsored(uint256 indexed treeId, address indexed sponsor);
    event TreePayment(
        uint256 indexed treeId, address indexed sponsor, uint256 amountPaid, uint256 platformFee, uint256 operatorPayout
    );
    event TreePriceSet(uint256 indexed treeId, uint256 price);
    event DefaultTreePriceSet(uint256 price);
    event PlatformFeeUpdated(uint16 platformFeeBps);
    event TreasuryUpdated(address treasury);
    event Withdrawal(address indexed account, address indexed to, uint256 amount);

    error ZeroAddress();
    error TreeNotFound(uint256 treeId);
    error TreeNotAvailable(uint256 treeId);
    error PriceNotSet(uint256 treeId);
    error IncorrectPayment(uint256 expected, uint256 received);
    error InvalidPlatformFee(uint16 platformFeeBps);
    error NothingToWithdraw();
    error TransferFailed();

    constructor(address registry, address nft, address initialTreasury, uint16 initialPlatformFeeBps) {
        if (registry == address(0) || nft == address(0) || initialTreasury == address(0)) revert ZeroAddress();
        if (initialPlatformFeeBps > MAX_PLATFORM_FEE_BPS) revert InvalidPlatformFee(initialPlatformFeeBps);

        treeRegistry = ITreeRegistry(registry);
        treeNFT = ITreeNFT(nft);
        treasury = initialTreasury;
        platformFeeBps = initialPlatformFeeBps;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function sponsorTree(uint256 treeId) external payable nonReentrant whenNotPaused returns (uint256 tokenId) {
        ITreeRegistry.Tree memory tree = treeRegistry.getTree(treeId);
        if (tree.status != ITreeRegistry.TreeStatus.AVAILABLE) revert TreeNotAvailable(treeId);

        uint256 price = getTreePrice(treeId);
        if (price == 0) revert PriceNotSet(treeId);
        if (msg.value != price) revert IncorrectPayment(price, msg.value);

        uint256 platformFee = (msg.value * platformFeeBps) / BPS_DENOMINATOR;
        uint256 operatorPayout = msg.value - platformFee;

        pendingWithdrawals[treasury] += platformFee;
        address operator = treeRegistry.getProject(tree.projectId).operator;
        pendingWithdrawals[operator] += operatorPayout;

        treeRegistry.markSponsored(treeId);
        tokenId = treeNFT.mint(msg.sender, treeId);

        emit TreeSponsored(treeId, msg.sender);
        emit TreePayment(treeId, msg.sender, msg.value, platformFee, operatorPayout);
    }

    function withdraw() external nonReentrant returns (uint256 amount) {
        return _withdraw(msg.sender, msg.sender);
    }

    function withdrawTo(address to) external nonReentrant returns (uint256 amount) {
        if (to == address(0)) revert ZeroAddress();
        return _withdraw(msg.sender, to);
    }

    function setTreePrice(uint256 treeId, uint256 price) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (!treeRegistry.treeExists(treeId)) revert TreeNotFound(treeId);
        treePrice[treeId] = price;
        emit TreePriceSet(treeId, price);
    }

    function setDefaultTreePrice(uint256 price) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        defaultTreePrice = price;
        emit DefaultTreePriceSet(price);
    }

    function setPlatformFeeBps(uint16 newPlatformFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPlatformFeeBps > MAX_PLATFORM_FEE_BPS) revert InvalidPlatformFee(newPlatformFeeBps);
        platformFeeBps = newPlatformFeeBps;
        emit PlatformFeeUpdated(newPlatformFeeBps);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function getTreePrice(uint256 treeId) public view returns (uint256) {
        uint256 price = treePrice[treeId];
        return price != 0 ? price : defaultTreePrice;
    }

    function _withdraw(address account, address to) private returns (uint256 amount) {
        amount = pendingWithdrawals[account];
        if (amount == 0) revert NothingToWithdraw();

        pendingWithdrawals[account] = 0;

        (bool success,) = payable(to).call{ value: amount }("");
        if (!success) revert TransferFailed();

        emit Withdrawal(account, to, amount);
    }
}
