// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { StuckHolders } from "../script/StuckHolders.sol";
import {
  IPaymentConduit,
  IPaymentSplitter,
  ISplitMain,
  IUpdatableSplitter
} from "../src/interfaces/IStuckHolders.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Rescue Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Real royalty receivers holding Blur Pool balances cannot distribute them
  today, and can after the upgrade, through their own unmodified code. Their
  recipients can then unwrap to Ether.

  @custom:date November 6th, 2026.
*/
contract RescueTest is
  BlurPoolForkTest {

  /**
    Return `_holder`'s Blur Pool balance, asserting that it is stuck there.

    @param _holder The holder.

    @return _balance The stuck balance.
  */
  function _stuck (
    address _holder
  ) internal view returns (uint256 _balance) {
    _balance = POOL.balanceOf(_holder);
    assertGt(_balance, 1 ether, "nothing stuck");
  }

  /**
    A PROOF conduit forwards its whole balance to the PROOF Safe, which can
    unwrap it.

    @param _conduit The conduit.
  */
  function _assertConduitRescue (
    address _conduit
  ) internal {
    uint256 _balance = _stuck(_conduit);
    assertEq(
      IPaymentConduit(_conduit).target(),
      StuckHolders.PROOF_TARGET
    );
    vm.expectRevert("SafeERC20: low-level call failed");
    IPaymentConduit(_conduit).forwardERC20(address(POOL));
    _upgrade();
    uint256 _targetBefore = POOL.balanceOf(StuckHolders.PROOF_TARGET);
    rescuer.rescueConduit(_conduit);
    assertEq(POOL.balanceOf(_conduit), 0);
    assertEq(
      POOL.balanceOf(StuckHolders.PROOF_TARGET),
      _targetBefore + _balance
    );
    _assertWithdraws(StuckHolders.PROOF_TARGET);
  }

  /// Moonbirds royalties held by its PROOF conduit are rescued.
  function test_rescueMoonbirdsConduit () public {
    _assertConduitRescue(StuckHolders.MOONBIRDS_CONDUIT);
  }

  /// Oddities royalties held by its PROOF conduit are rescued.
  function test_rescueOdditiesConduit () public {
    _assertConduitRescue(StuckHolders.ODDITIES_CONDUIT);
  }

  /**
    The 0xSplits split wallet distributes through `SplitMain`, and each
    recipient withdraws its allocation and unwraps it.
  */
  function test_rescueSplit () public {
    uint256 _balance = _stuck(StuckHolders.SPLIT_WALLET);
    address[] memory _accounts = StuckHolders.splitAccounts();
    uint32[] memory _allocations = StuckHolders.splitAllocations();
    assertEq(
      ISplitMain(StuckHolders.SPLIT_MAIN).getHash(StuckHolders.SPLIT_WALLET),
      keccak256(abi.encodePacked(_accounts, _allocations, uint32(0)))
    );
    // The split wallet's `transfer` call hits the missing selector, and its
    // early solmate `safeTransfer` bubbles the bare revert up with no data.
    vm.expectRevert(bytes(""));
    ISplitMain(StuckHolders.SPLIT_MAIN).distributeERC20(
      StuckHolders.SPLIT_WALLET,
      address(POOL),
      _accounts,
      _allocations,
      0,
      address(0)
    );
    _upgrade();
    uint256[] memory _before = new uint256[](_accounts.length);
    for (uint256 i = 0; i < _accounts.length; i++) {
      _before[i] = POOL.balanceOf(_accounts[i]);
    }
    rescuer.rescueSplit();

    // 0xSplits leaves one wei in the wallet and one in `SplitMain` per account
    // to keep storage warm, and rounds allocations down.
    assertEq(POOL.balanceOf(StuckHolders.SPLIT_WALLET), 1);
    for (uint256 i = 0; i < _accounts.length; i++) {
      uint256 _expected = (_balance - 1) * _allocations[i] / 1e6;
      assertApproxEqAbs(
        POOL.balanceOf(_accounts[i]) - _before[i],
        _expected,
        2
      );
      _assertWithdraws(_accounts[i]);
    }
  }

  /**
    A `RoyaltiesSplitter` flushes its balance to its payees by share, and each
    payee unwraps it.

    @param _splitter The splitter.
  */
  function _assertRoyaltiesSplitterRescue (
    address _splitter
  ) internal {
    uint256 _balance = _stuck(_splitter);
    IUpdatableSplitter _updatable = IUpdatableSplitter(_splitter);
    assertTrue(
      _updatable.hasRole(
        _updatable.FLUSHWORTHY(),
        StuckHolders.ROYALTIES_FLUSHER
      )
    );
    vm.prank(StuckHolders.ROYALTIES_FLUSHER);
    vm.expectRevert("SafeERC20: low-level call failed");
    _updatable.flushToken(address(POOL));
    _upgrade();
    uint256 _totalShares = _updatable.totalShares();
    uint256 _unit = _balance / _totalShares;
    address[] memory _payees = new address[](_totalShares);
    uint256[] memory _before = new uint256[](_totalShares);
    uint256 _count = 0;
    for (uint256 _shares = 0; _shares < _totalShares; _count++) {
      _payees[_count] = _updatable.payee(_count);
      _before[_count] = POOL.balanceOf(_payees[_count]);
      _shares += _updatable.shares(_payees[_count]);
    }
    rescuer.rescueRoyaltiesSplitter(_splitter);
    assertEq(POOL.balanceOf(_splitter), _balance - _unit * _totalShares);
    for (uint256 i = 0; i < _count; i++) {
      assertEq(
        POOL.balanceOf(_payees[i]) - _before[i],
        _unit * _updatable.shares(_payees[i])
      );
      _assertWithdraws(_payees[i]);
    }
  }

  /// The first `RoyaltiesSplitter` is rescued.
  function test_rescueRoyaltiesSplitterA () public {
    _assertRoyaltiesSplitterRescue(StuckHolders.ROYALTIES_SPLITTER_A);
  }

  /// The second `RoyaltiesSplitter` is rescued.
  function test_rescueRoyaltiesSplitterB () public {
    _assertRoyaltiesSplitterRescue(StuckHolders.ROYALTIES_SPLITTER_B);
  }

  /**
    The OpenZeppelin `RoyaltyPaymentSplitter` releases each payee's share, and
    each payee unwraps it.
  */
  function test_rescueRoyaltyPaymentSplitter () public {
    address _splitter = StuckHolders.ROYALTY_PAYMENT_SPLITTER;
    uint256 _balance = _stuck(_splitter);
    address[] memory _payees = rescuer.paymentSplitterPayees();
    assertGt(_payees.length, 0);
    vm.expectRevert("SafeERC20: low-level call failed");
    IPaymentSplitter(_splitter).release(address(POOL), _payees[0]);
    _upgrade();
    uint256 _totalShares = IPaymentSplitter(_splitter).totalShares();
    uint256[] memory _before = new uint256[](_payees.length);
    for (uint256 i = 0; i < _payees.length; i++) {
      _before[i] = POOL.balanceOf(_payees[i]);
    }
    rescuer.rescuePaymentSplitter();
    uint256 _released = 0;
    for (uint256 i = 0; i < _payees.length; i++) {
      uint256 _received = POOL.balanceOf(_payees[i]) - _before[i];
      assertEq(
        _received,
        _balance * IPaymentSplitter(_splitter).shares(_payees[i])
          / _totalShares
      );
      _released += _received;
      _assertWithdraws(_payees[i]);
    }
    assertEq(POOL.balanceOf(_splitter), _balance - _released);
  }

  /**
    The full rescue script frees every stuck holder, leaving only splitter
    rounding dust, and conserves the pool's Ether backing.
  */
  function test_rescueAll () public {
    address[6] memory _holders = rescuer.holders();
    uint256 _stuckTotal = 0;
    for (uint256 i = 0; i < _holders.length; i++) {
      _stuckTotal += _stuck(_holders[i]);
    }
    _upgrade();
    uint256 _supply = POOL.totalSupply();
    rescuer.run();
    uint256 _remaining = 0;
    for (uint256 i = 0; i < _holders.length; i++) {
      _remaining += POOL.balanceOf(_holders[i]);
    }
    assertLt(_remaining, 10, "more than dust remains");
    assertGt(_stuckTotal, 250 ether);
    assertEq(POOL.totalSupply(), _supply);
    assertEq(POOL.totalSupply(), address(POOL).balance);
  }
}
