// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { TreeNFT } from "../src/TreeNFT.sol";
import { TreeBond } from "../src/TreeBond.sol";
import { ITreeRegistry } from "../src/interfaces/ITreeRegistry.sol";

contract TreeBondTest is Test {
    TreeRegistry internal registry;
    TreeNFT internal nft;
    TreeBond internal bond;

    address internal admin = makeAddr("admin");
    address internal sponsor = makeAddr("sponsor");
    address internal projectOperator = makeAddr("projectOperator");
    address internal treasury = makeAddr("treasury");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant PRICE = 1 ether;
    uint16 internal constant FEE_BPS = 1_000;

    uint256 internal treeId;
    bool internal reenter;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TreeMinted(uint256 indexed treeId, uint256 indexed tokenId, address owner);
    event TreeStatusChanged(uint256 indexed treeId, ITreeRegistry.TreeStatus status);
    event TreeSponsored(uint256 indexed treeId, address indexed sponsor);
    event TreePayment(
        uint256 indexed treeId, address indexed sponsor, uint256 amountPaid, uint256 platformFee, uint256 operatorPayout
    );
    event Withdrawal(address indexed account, address indexed to, uint256 amount);

    receive() external payable {
        if (reenter) {
            reenter = false;
            bond.withdraw();
        }
    }

    function setUp() public {
        vm.startPrank(admin);
        registry = new TreeRegistry();
        nft = new TreeNFT(address(registry));
        bond = new TreeBond(address(registry), address(nft), treasury, FEE_BPS);

        registry.grantRole(registry.OPERATOR_ROLE(), admin);
        registry.grantRole(registry.VERIFIER_ROLE(), admin);
        registry.grantRole(registry.SPONSOR_ROLE(), address(bond));

        nft.grantRole(nft.MINTER_ROLE(), address(bond));
        nft.grantRole(nft.PAUSER_ROLE(), admin);

        bond.grantRole(bond.OPERATOR_ROLE(), admin);
        bond.grantRole(bond.PAUSER_ROLE(), admin);

        registry.createProject("JTG-001", "Central Java #001", "bafyproject", projectOperator);
        treeId = registry.registerTree(1, "TREE-JTG-000192", "bafytree", 0, 0, uint64(block.timestamp));
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.PENDING_VERIFICATION);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.VERIFIED);
        registry.updateTreeStatus(treeId, ITreeRegistry.TreeStatus.AVAILABLE);

        bond.setDefaultTreePrice(PRICE);
        vm.stopPrank();

        vm.deal(sponsor, 100 ether);
    }

    function _sponsor() internal returns (uint256 tokenId) {
        vm.prank(sponsor);
        tokenId = bond.sponsorTree{ value: PRICE }(treeId);
    }

    function test_SponsorTree_Success() public {
        uint256 platformFee = PRICE * FEE_BPS / 10_000;
        uint256 operatorPayout = PRICE - platformFee;

        vm.expectEmit(true, false, false, true, address(registry));
        emit TreeStatusChanged(treeId, ITreeRegistry.TreeStatus.SPONSORED);
        vm.expectEmit(true, true, true, false, address(nft));
        emit Transfer(address(0), sponsor, treeId);
        vm.expectEmit(true, true, false, true, address(nft));
        emit TreeMinted(treeId, treeId, sponsor);
        vm.expectEmit(true, true, false, true, address(bond));
        emit TreeSponsored(treeId, sponsor);
        vm.expectEmit(true, true, false, true, address(bond));
        emit TreePayment(treeId, sponsor, PRICE, platformFee, operatorPayout);

        uint256 tokenId = _sponsor();

        assertEq(tokenId, treeId);
        assertEq(nft.ownerOf(treeId), sponsor);
        assertEq(uint8(registry.treeStatus(treeId)), uint8(ITreeRegistry.TreeStatus.SPONSORED));
        assertEq(bond.pendingWithdrawals(treasury), platformFee);
        assertEq(bond.pendingWithdrawals(projectOperator), operatorPayout);
        assertEq(address(bond).balance, PRICE);
        assertEq(sponsor.balance, 100 ether - PRICE);
    }

    function test_SponsorTree_RevertsWhenNotAvailable() public {
        _sponsor();

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.TreeNotAvailable.selector, treeId));
        bond.sponsorTree{ value: PRICE }(treeId);
    }

    function test_SponsorTree_RevertsOnIncorrectPayment() public {
        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.IncorrectPayment.selector, PRICE, PRICE - 1));
        bond.sponsorTree{ value: PRICE - 1 }(treeId);

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.IncorrectPayment.selector, PRICE, PRICE + 1));
        bond.sponsorTree{ value: PRICE + 1 }(treeId);
    }

    function test_SponsorTree_RevertsWhenPriceNotSet() public {
        vm.prank(admin);
        bond.setDefaultTreePrice(0);

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.PriceNotSet.selector, treeId));
        bond.sponsorTree{ value: PRICE }(treeId);
    }

    function test_SponsorTree_RevertsForUnknownTree() public {
        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeRegistry.TreeNotFound.selector, 999));
        bond.sponsorTree{ value: PRICE }(999);
    }

    function test_SponsorTree_RevertsWhenPaused() public {
        vm.prank(admin);
        bond.pause();

        vm.prank(sponsor);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bond.sponsorTree{ value: PRICE }(treeId);
    }

    function test_SponsorTree_UsesPerTreePrice() public {
        uint256 customPrice = 2 ether;
        vm.prank(admin);
        bond.setTreePrice(treeId, customPrice);

        assertEq(bond.getTreePrice(treeId), customPrice);

        vm.prank(sponsor);
        bond.sponsorTree{ value: customPrice }(treeId);

        uint256 platformFee = customPrice * FEE_BPS / 10_000;
        assertEq(bond.pendingWithdrawals(treasury), platformFee);
        assertEq(bond.pendingWithdrawals(projectOperator), customPrice - platformFee);
    }

    function test_SetTreePrice_RevertsForUnknownTree() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.TreeNotFound.selector, 999));
        bond.setTreePrice(999, 1 ether);
    }

    function test_SetTreePrice_RevertsWithoutRole() public {
        bytes32 operatorRole = bond.OPERATOR_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, operatorRole)
        );
        bond.setTreePrice(treeId, 1 ether);
    }

    function test_Withdraw() public {
        _sponsor();
        uint256 platformFee = PRICE * FEE_BPS / 10_000;

        vm.expectEmit(true, true, false, true, address(bond));
        emit Withdrawal(treasury, treasury, platformFee);

        uint256 balanceBefore = treasury.balance;
        vm.prank(treasury);
        uint256 amount = bond.withdraw();

        assertEq(amount, platformFee);
        assertEq(treasury.balance, balanceBefore + platformFee);
        assertEq(bond.pendingWithdrawals(treasury), 0);
        assertEq(address(bond).balance, PRICE - platformFee);

        vm.prank(treasury);
        vm.expectRevert(TreeBond.NothingToWithdraw.selector);
        bond.withdraw();
    }

    function test_WithdrawTo() public {
        _sponsor();
        uint256 operatorPayout = PRICE - (PRICE * FEE_BPS / 10_000);

        uint256 balanceBefore = bob.balance;
        vm.prank(projectOperator);
        bond.withdrawTo(bob);

        assertEq(bob.balance, balanceBefore + operatorPayout);
        assertEq(bond.pendingWithdrawals(projectOperator), 0);
    }

    function test_WithdrawTo_RevertsForZeroAddress() public {
        _sponsor();

        vm.prank(treasury);
        vm.expectRevert(TreeBond.ZeroAddress.selector);
        bond.withdrawTo(address(0));
    }

    function test_Withdraw_RevertsOnReentrancy() public {
        vm.prank(admin);
        bond.setTreasury(address(this));

        _sponsor();
        uint256 platformFee = PRICE * FEE_BPS / 10_000;

        reenter = true;
        vm.expectRevert(TreeBond.TransferFailed.selector);
        bond.withdraw();

        assertEq(bond.pendingWithdrawals(address(this)), platformFee);
    }

    function test_SetPlatformFeeBps_EnforcesCap() public {
        uint16 maxFee = bond.MAX_PLATFORM_FEE_BPS();

        vm.prank(admin);
        bond.setPlatformFeeBps(maxFee);
        assertEq(bond.platformFeeBps(), maxFee);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.InvalidPlatformFee.selector, 2_001));
        bond.setPlatformFeeBps(2_001);
    }

    function test_SetTreasury() public {
        bytes32 adminRole = bond.DEFAULT_ADMIN_ROLE();

        vm.prank(admin);
        bond.setTreasury(bob);
        assertEq(bond.treasury(), bob);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, adminRole)
        );
        bond.setTreasury(stranger);
    }

    function test_Constructor_RevertsOnInvalidFee() public {
        vm.expectRevert(abi.encodeWithSelector(TreeBond.InvalidPlatformFee.selector, 2_001));
        new TreeBond(address(registry), address(nft), treasury, 2_001);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(TreeBond.ZeroAddress.selector);
        new TreeBond(address(0), address(nft), treasury, FEE_BPS);

        vm.expectRevert(TreeBond.ZeroAddress.selector);
        new TreeBond(address(registry), address(0), treasury, FEE_BPS);

        vm.expectRevert(TreeBond.ZeroAddress.selector);
        new TreeBond(address(registry), address(nft), address(0), FEE_BPS);
    }

    function testFuzz_SponsorTreeSplit(uint16 feeBps, uint96 price) public {
        feeBps = uint16(bound(feeBps, 0, bond.MAX_PLATFORM_FEE_BPS()));
        price = uint96(bound(price, 1, 100 ether));

        vm.startPrank(admin);
        bond.setPlatformFeeBps(feeBps);
        bond.setDefaultTreePrice(price);
        vm.stopPrank();

        vm.deal(sponsor, price);
        vm.prank(sponsor);
        bond.sponsorTree{ value: price }(treeId);

        uint256 platformFee = uint256(price) * feeBps / bond.BPS_DENOMINATOR();
        assertEq(bond.pendingWithdrawals(treasury), platformFee);
        assertEq(bond.pendingWithdrawals(projectOperator), uint256(price) - platformFee);
        assertEq(address(bond).balance, price);
    }

    function testFuzz_SponsorTree_RevertsOnWrongValue(uint96 value) public {
        value = uint96(bound(value, 0, 5 ether));
        vm.assume(value != PRICE);

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(TreeBond.IncorrectPayment.selector, PRICE, value));
        bond.sponsorTree{ value: value }(treeId);
    }
}
