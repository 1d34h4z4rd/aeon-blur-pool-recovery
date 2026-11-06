// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { IBlurPool } from "../src/pool/interfaces/IBlurPool.sol";
import { ISafe } from "../src/interfaces/ISafe.sol";
import {
  IAssetVault,
  ITimelock
} from "../src/interfaces/IStuckHolders.sol";
import { Deployment } from "./Deployment.sol";
import { SafeTransactions } from "./SafeTransactions.sol";
import { StuckHolders } from "./StuckHolders.sol";
import { console } from "forge-std/Script.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Rescue Asset Vault
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Rescue the `AssetVault`'s Blur Pool balance through its own governance and
  nothing else: the vault is owned by a three-day `Timelock`, administered by a
  2-of-3 Safe whose `ScopeGuard` lets it call only the timelock. The Safe
  queues two timelock calls with the same ETA, and executes them in order once
  the delay has passed:

  1. `vault.send` an ERC-20 send of the Blur Pool balance to the timelock,
     which reaches Blur Pool `transfer`.
  2. `BlurPool.withdraw` that balance from the timelock to the timelock.

  The rescued value ends as plain Ether held by the same timelock, under the
  same admin, and no guard, owner, or role is changed. Queueing works before
  the upgrade; execution succeeds only after it.

  @custom:date November 6th, 2026.
*/
contract RescueAssetVault is
  SafeTransactions {

  /// The Blur Pool.
  IBlurPoolProxy private constant POOL = IBlurPoolProxy(Deployment.BLUR_POOL);

  /// The timelock owning the vault.
  ITimelock private constant TIMELOCK =
    ITimelock(StuckHolders.ASSET_VAULT_TIMELOCK);

  /// The Safe administering the timelock.
  ISafe private constant ADMIN = ISafe(StuckHolders.ASSET_VAULT_ADMIN);

  /**
    Return the two timelock calls that rescue `_amount`.

    @param _amount The Blur Pool amount to rescue.

    @return _targets The call targets, in execution order.
    @return _data The calldata, in execution order.
  */
  function rescueCalls (
    uint256 _amount
  ) public pure returns (address[2] memory _targets, bytes[2] memory _data) {
    IAssetVault.SendSpecification[] memory _sends =
      new IAssetVault.SendSpecification[](1);
    uint256[] memory _amounts = new uint256[](1);
    _amounts[0] = _amount;
    _sends[0] = IAssetVault.SendSpecification({
      assetType: IAssetVault.AssetType.ERC20,
      recipientAddress: StuckHolders.ASSET_VAULT_TIMELOCK,
      assetAddress: address(POOL),
      amounts: _amounts,
      ids: new uint256[](0)
    });
    _targets[0] = StuckHolders.ASSET_VAULT;
    _data[0] = abi.encodeCall(IAssetVault.send, (_sends));
    _targets[1] = address(POOL);
    _data[1] = abi.encodeCall(IBlurPool.withdraw, (_amount));
  }

  /**
    Return the timelock's hash of a rescue call.

    @param _target The call target.
    @param _data The calldata.
    @param _eta The queued execution time.

    @return _ The timelock call hash.
  */
  function timelockHash (
    address _target,
    bytes memory _data,
    uint256 _eta
  ) public pure returns (bytes32) {
    return keccak256(abi.encode(_target, uint256(0), "", _data, _eta));
  }

  /**
    Queue the rescue of `_amount` for execution at `_eta`.

    @param _eta The execution time; at least the timelock delay from now.
    @param _amount The Blur Pool amount to rescue.
  */
  function queue (
    uint256 _eta,
    uint256 _amount
  ) public {
    console.log("Queue asset vault rescue");
    console.log("  Vault:", StuckHolders.ASSET_VAULT);
    console.log("  Timelock:", address(TIMELOCK));
    console.log("  Admin Safe:", address(ADMIN));
    console.log("  Admin Safe guard:", _guardOf(ADMIN));
    console.log("  Amount: %s wei", _amount);
    console.log("  ETA:", _eta);
    (address[2] memory _targets, bytes[2] memory _data) = rescueCalls(_amount);
    for (uint256 i = 0; i < _targets.length; i++) {
      _executeThroughSafe(
        ADMIN,
        address(TIMELOCK),
        abi.encodeCall(
          ITimelock.queueTransaction,
          (_targets[i], 0, "", _data[i], _eta)
        )
      );
      console.log("  Queued call to:", _targets[i]);
    }
  }

  /**
    Execute the rescue of `_amount` queued for `_eta`.

    @param _eta The queued execution time.
    @param _amount The Blur Pool amount queued for rescue.
  */
  function execute (
    uint256 _eta,
    uint256 _amount
  ) public {
    console.log("Execute asset vault rescue");
    (address[2] memory _targets, bytes[2] memory _data) = rescueCalls(_amount);
    for (uint256 i = 0; i < _targets.length; i++) {
      _executeThroughSafe(
        ADMIN,
        address(TIMELOCK),
        abi.encodeCall(
          ITimelock.executeTransaction,
          (_targets[i], 0, "", _data[i], _eta)
        )
      );
      console.log("  Executed call to:", _targets[i]);
    }
    console.log(
      "  Vault Blur Pool balance: %s wei",
      POOL.balanceOf(StuckHolders.ASSET_VAULT)
    );
    console.log(
      "  Timelock Ether balance: %s wei",
      address(TIMELOCK).balance
    );
  }
}
