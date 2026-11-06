// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { Deployment } from "../script/Deployment.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Transfer Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  After the upgrade, `transfer` behaves as a standard ERC-20 transfer of the
  caller's own balance, and every pre-existing function keeps its exact
  behavior and authorization.

  @custom:date November 6th, 2026.
*/
contract TransferTest is
  BlurPoolForkTest {

  /// The Blur Pool `Transfer` event.
  event Transfer (address indexed from, address indexed to, uint256 amount);

  /// A test depositor.
  address internal alice;

  /// A test recipient.
  address internal bob;

  /// Fork and fund a depositor.
  function setUp () public override {
    super.setUp();

    // Foundry's stock `makeAddr("alice")` and friends hold Ether-sweeping
    // contracts on mainnet, so use unique labels and insist on clean accounts.
    alice = makeAddr("BlurPoolTransferTest.alice");
    bob = makeAddr("BlurPoolTransferTest.bob");
    assertEq(alice.code.length, 0);
    assertEq(bob.code.length, 0);
    assertEq(alice.balance, 0);
    assertEq(bob.balance, 0);
    vm.deal(alice, 100 ether);
  }

  /**
    Deposit `_amount` for `alice`.

    @param _amount The amount to deposit.
  */
  function _deposit (
    uint256 _amount
  ) internal {
    vm.prank(alice);
    POOL.deposit{ value: _amount }();
  }

  /// Before the upgrade there is no `transfer`; the call reverts.
  function test_transferRevertsBeforeUpgrade () public {
    _deposit(1 ether);
    vm.prank(alice);
    vm.expectRevert();
    POOL.transfer(bob, 1 ether);
  }

  /// `transfer` moves the caller's balance, emits, and returns true.
  function test_transfer () public {
    _upgrade();
    _deposit(3 ether);
    uint256 _supply = POOL.totalSupply();
    vm.expectEmit(address(POOL));
    emit Transfer(alice, bob, 1 ether);
    vm.prank(alice);
    assertTrue(POOL.transfer(bob, 1 ether));
    assertEq(POOL.balanceOf(alice), 2 ether);
    assertEq(POOL.balanceOf(bob), 1 ether);
    assertEq(POOL.totalSupply(), _supply);
    assertEq(POOL.totalSupply(), address(POOL).balance);
  }

  /**
    `transfer` conserves balances for any amount up to the caller's balance.

    @param _deposited The amount deposited.
    @param _amount The amount transferred.
  */
  function testFuzz_transfer (
    uint256 _deposited,
    uint256 _amount
  ) public {
    _upgrade();
    _deposited = bound(_deposited, 0, 100 ether);
    _amount = bound(_amount, 0, _deposited);
    _deposit(_deposited);
    vm.prank(alice);
    assertTrue(POOL.transfer(bob, _amount));
    assertEq(POOL.balanceOf(alice), _deposited - _amount);
    assertEq(POOL.balanceOf(bob), _amount);
  }

  /// `transfer` cannot exceed the caller's balance.
  function test_transferRevertsOnInsufficientBalance () public {
    _upgrade();
    _deposit(1 ether);
    vm.prank(alice);
    vm.expectRevert("Insufficient balance");
    POOL.transfer(bob, 1 ether + 1);
  }

  /// `transfer` cannot burn to the zero address.
  function test_transferRevertsToZeroAddress () public {
    _upgrade();
    _deposit(1 ether);
    vm.prank(alice);
    vm.expectRevert("Cannot transfer to 0 address");
    POOL.transfer(address(0), 1 ether);
  }

  /// A self-transfer leaves the balance unchanged.
  function test_transferToSelf () public {
    _upgrade();
    _deposit(1 ether);
    vm.prank(alice);
    assertTrue(POOL.transfer(alice, 1 ether));
    assertEq(POOL.balanceOf(alice), 1 ether);
  }

  /// A real holder's pre-existing balance transfers and unwraps.
  function test_transferRealBalance () public {
    _upgrade();
    address _holder = 0xe65B6865DBCe299Ae6a20efcc7543362540741d8;
    uint256 _balance = POOL.balanceOf(_holder);
    assertGt(_balance, 0);
    vm.prank(_holder);
    assertTrue(POOL.transfer(bob, _balance));
    assertEq(POOL.balanceOf(_holder), 0);
    _assertWithdraws(bob);
  }

  /// Deposits via `receive` and `deposit()` and withdrawals are unchanged.
  function test_depositAndWithdrawUnchanged () public {
    _upgrade();
    vm.prank(alice);
    (bool _success, ) = address(POOL).call{ value: 1 ether }("");
    assertTrue(_success);
    _deposit(2 ether);
    assertEq(POOL.balanceOf(alice), 3 ether);
    vm.prank(alice);
    POOL.withdraw(1 ether);
    assertEq(POOL.balanceOf(alice), 2 ether);
    assertEq(alice.balance, 98 ether);
    vm.prank(alice);
    vm.expectRevert("Insufficient funds");
    POOL.withdraw(2 ether + 1);
  }

  /// `deposit(user)` remains restricted to Blend and Exchange V2.
  function test_depositForUnchanged () public {
    _upgrade();
    vm.prank(alice);
    vm.expectRevert("Unauthorized deposit");
    POOL.deposit{ value: 1 ether }(bob);
    address[2] memory _callers = [Deployment.BLEND, Deployment.EXCHANGE_V2];
    for (uint256 i = 0; i < _callers.length; i++) {
      vm.deal(_callers[i], 1 ether);
      vm.prank(_callers[i]);
      POOL.deposit{ value: 1 ether }(bob);
    }
    assertEq(POOL.balanceOf(bob), 2 ether);
  }

  /// `withdrawFrom` remains restricted to Blend and Exchange V2.
  function test_withdrawFromUnchanged () public {
    _upgrade();
    _deposit(2 ether);
    vm.prank(bob);
    vm.expectRevert("Unauthorized transfer");
    POOL.withdrawFrom(alice, bob, 1 ether);
    address[2] memory _callers = [Deployment.BLEND, Deployment.EXCHANGE_V2];
    for (uint256 i = 0; i < _callers.length; i++) {
      vm.prank(_callers[i]);
      POOL.withdrawFrom(alice, bob, 1 ether);
    }
    assertEq(POOL.balanceOf(alice), 0);
    assertEq(bob.balance, 2 ether);
  }

  /**
    `transferFrom` remains restricted to the four Blur contracts, needs no
    allowance from them, and grants no one else an allowance-based path.
  */
  function test_transferFromUnchanged () public {
    _upgrade();
    _deposit(4 ether);

    // Not even the holder may call `transferFrom` on its own balance.
    vm.prank(alice);
    vm.expectRevert("Unauthorized transfer");
    POOL.transferFrom(alice, bob, 1 ether);
    vm.prank(bob);
    vm.expectRevert("Unauthorized transfer");
    POOL.transferFrom(alice, bob, 1 ether);
    address[4] memory _callers = [
      Deployment.EXCHANGE,
      Deployment.EXCHANGE_V2,
      Deployment.SWAP,
      Deployment.BLEND
    ];
    for (uint256 i = 0; i < _callers.length; i++) {
      vm.prank(_callers[i]);
      assertTrue(POOL.transferFrom(alice, bob, 1 ether));
    }
    assertEq(POOL.balanceOf(alice), 0);
    assertEq(POOL.balanceOf(bob), 4 ether);
  }
}
