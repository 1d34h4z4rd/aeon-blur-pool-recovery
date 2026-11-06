// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import {
  IPaymentConduit,
  IPaymentSplitter,
  ISplitMain,
  IUpdatableSplitter
} from "../src/interfaces/IStuckHolders.sol";
import { Deployment } from "./Deployment.sol";
import { StuckHolders } from "./StuckHolders.sol";
import { Script, console } from "forge-std/Script.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Rescue Stuck Funds
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  After the upgrade, drive each stuck royalty receiver through its own,
  unmodified ERC-20 distribution path. Each call fails against the current
  Blur Pool and succeeds against the patched one; recipients then hold plain
  Blur Pool balances that they can `withdraw` to Ether themselves. Every call
  here is permissionless except `RoyaltiesSplitter.flushToken`, which is made
  by the splitter's existing `FLUSHWORTHY` deployer.

  @custom:date November 6th, 2026.
*/
contract RescueStuckFunds is
  Script {

  /// The Blur Pool.
  IBlurPoolProxy private constant POOL = IBlurPoolProxy(Deployment.BLUR_POOL);

  /// Run the script, rescuing every stuck holder and logging the result.
  function run () external {
    address[6] memory _holders = holders();
    uint256 _stuck = 0;
    console.log("Rescue stuck Blur Pool balances");
    for (uint256 i = 0; i < _holders.length; i++) {
      uint256 _balance = POOL.balanceOf(_holders[i]);
      _stuck += _balance;
      console.log("  Stuck in %s: %s wei", _holders[i], _balance);
    }
    console.log("  Total stuck: %s wei", _stuck);

    // Rescue.
    rescueConduit(StuckHolders.MOONBIRDS_CONDUIT);
    rescueConduit(StuckHolders.ODDITIES_CONDUIT);
    rescueSplit();
    rescueRoyaltiesSplitter(StuckHolders.ROYALTIES_SPLITTER_A);
    rescueRoyaltiesSplitter(StuckHolders.ROYALTIES_SPLITTER_B);
    rescuePaymentSplitter();

    // Report what remains; splitters keep rounding dust by design.
    uint256 _remaining = 0;
    for (uint256 i = 0; i < _holders.length; i++) {
      _remaining += POOL.balanceOf(_holders[i]);
    }
    console.log("  Total remaining (rounding dust): %s wei", _remaining);
    console.log("  Total rescued: %s wei", _stuck - _remaining);
  }

  /**
    Return every stuck holder.

    @return _ The stuck holders.
  */
  function holders () public pure returns (address[6] memory) {
    return [
      StuckHolders.MOONBIRDS_CONDUIT,
      StuckHolders.ODDITIES_CONDUIT,
      StuckHolders.SPLIT_WALLET,
      StuckHolders.ROYALTIES_SPLITTER_A,
      StuckHolders.ROYALTIES_SPLITTER_B,
      StuckHolders.ROYALTY_PAYMENT_SPLITTER
    ];
  }

  /**
    Forward a PROOF `PaymentConduit`'s Blur Pool balance to its target.

    @param _conduit The conduit.
  */
  function rescueConduit (
    address _conduit
  ) public {
    vm.startBroadcast();
    IPaymentConduit(_conduit).forwardERC20(address(POOL));
    vm.stopBroadcast();
    console.log("  - Forwarded conduit:", _conduit);
  }

  /**
    Distribute the 0xSplits split wallet's Blur Pool balance and withdraw it
    from `SplitMain` to each recipient.
  */
  function rescueSplit () public {
    address[] memory _accounts = StuckHolders.splitAccounts();
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(POOL);
    vm.startBroadcast();
    ISplitMain(StuckHolders.SPLIT_MAIN).distributeERC20(
      StuckHolders.SPLIT_WALLET,
      address(POOL),
      _accounts,
      StuckHolders.splitAllocations(),
      0,
      address(0)
    );
    for (uint256 i = 0; i < _accounts.length; i++) {
      ISplitMain(StuckHolders.SPLIT_MAIN).withdraw(_accounts[i], 0, _tokens);
    }
    vm.stopBroadcast();
    console.log("  - Distributed split:", StuckHolders.SPLIT_WALLET);
  }

  /**
    Flush a `RoyaltiesSplitter`'s Blur Pool balance to its payees.

    @param _splitter The splitter.
  */
  function rescueRoyaltiesSplitter (
    address _splitter
  ) public {
    vm.startBroadcast(StuckHolders.ROYALTIES_FLUSHER);
    IUpdatableSplitter(_splitter).flushToken(address(POOL));
    vm.stopBroadcast();
    console.log("  - Flushed splitter:", _splitter);
  }

  /**
    Release every payee's share of the `RoyaltyPaymentSplitter`'s Blur Pool
    balance.
  */
  function rescuePaymentSplitter () public {
    IPaymentSplitter _splitter =
      IPaymentSplitter(StuckHolders.ROYALTY_PAYMENT_SPLITTER);
    address[] memory _payees = paymentSplitterPayees();
    vm.startBroadcast();
    for (uint256 i = 0; i < _payees.length; i++) {
      _splitter.release(address(POOL), _payees[i]);
    }
    vm.stopBroadcast();
    console.log("  - Released splitter:", address(_splitter));
  }

  /**
    Return the payees of the `RoyaltyPaymentSplitter`, which exposes no length
    getter, by reading until its `payee` array access reverts.

    @return _payees The payees.
  */
  function paymentSplitterPayees () public view returns (
    address[] memory _payees
  ) {
    IPaymentSplitter _splitter =
      IPaymentSplitter(StuckHolders.ROYALTY_PAYMENT_SPLITTER);
    uint256 _count = 0;
    while (true) {
      try _splitter.payee(_count) returns (address) {
        _count++;
      } catch {
        break;
      }
    }
    _payees = new address[](_count);
    for (uint256 i = 0; i < _count; i++) {
      _payees[i] = _splitter.payee(i);
    }
  }
}
