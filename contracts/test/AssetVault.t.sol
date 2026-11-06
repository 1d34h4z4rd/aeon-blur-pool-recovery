// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { RescueAssetVault } from "../script/RescueAssetVault.s.sol";
import { StuckHolders } from "../script/StuckHolders.sol";
import { ISafe } from "../src/interfaces/ISafe.sol";
import {
  IAssetVault,
  IScopeGuard,
  ITimelock
} from "../src/interfaces/IStuckHolders.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Asset Vault Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The `AssetVault` "One" holds Blur Pool that even its full governance (a
  2-of-3 Safe, behind a `ScopeGuard`, administering a three-day `Timelock`
  that owns the vault) cannot move today. The very same queued governance
  calls fail before the upgrade and succeed after it, leaving the value as
  plain Ether under the same timelock.

  @custom:date November 6th, 2026.
*/
contract AssetVaultTest is
  BlurPoolForkTest {

  /// The vault.
  IAssetVault internal constant VAULT = IAssetVault(StuckHolders.ASSET_VAULT);

  /// The timelock owning the vault.
  ITimelock internal constant TIMELOCK =
    ITimelock(StuckHolders.ASSET_VAULT_TIMELOCK);

  /// The Safe administering the timelock.
  ISafe internal constant ADMIN = ISafe(StuckHolders.ASSET_VAULT_ADMIN);

  /// The guard on the admin Safe.
  IScopeGuard internal constant GUARD =
    IScopeGuard(StuckHolders.ASSET_VAULT_ADMIN_GUARD);

  /// The vault rescue script.
  RescueAssetVault internal vaultRescuer;

  /// Fork and prepare the vault rescue script.
  function setUp () public override {
    super.setUp();
    vaultRescuer = new RescueAssetVault();
  }

  /**
    Return the guard installed on the admin Safe.

    @return _ The guard.
  */
  function _adminGuard () internal view returns (address) {
    bytes32 _slot = keccak256("guard_manager.guard.address");
    return abi.decode(ADMIN.getStorageAt(uint256(_slot), 1), (address));
  }

  /**
    The governance chain and guard are as the rescue assumes: the timelock owns
    the vault, the Safe administers the timelock, and the Safe's guard allows
    any timelock call but no direct call to Blur Pool or the vault. That is why
    the rescued balance goes to, and is unwrapped by, the timelock.
  */
  function test_governance () public view {
    assertEq(VAULT.owner(), address(TIMELOCK));
    assertEq(TIMELOCK.admin(), address(ADMIN));
    assertEq(ADMIN.getThreshold(), 2);
    assertEq(_adminGuard(), address(GUARD));
    assertTrue(GUARD.isAllowedTarget(address(TIMELOCK)));
    assertFalse(GUARD.isScoped(address(TIMELOCK)));
    assertFalse(GUARD.isAllowedTarget(address(POOL)));
    assertFalse(GUARD.isAllowedTarget(address(VAULT)));
  }

  /**
    The Safe queues the rescue through the timelock before the upgrade. Once
    the delay passes, executing it reverts inside the vault's `send`, because
    Blur Pool has no `transfer`. After the upgrade the same queued calls
    execute: the vault's whole balance moves to the timelock and is unwrapped
    to Ether there.
  */
  function test_rescueAssetVault () public {
    uint256 _balance = POOL.balanceOf(address(VAULT));
    assertGt(_balance, 85 ether);
    uint256 _eta = block.timestamp + TIMELOCK.delay();
    uint256 _nonce = ADMIN.nonce();
    vaultRescuer.queue(_eta, _balance);
    assertEq(ADMIN.nonce(), _nonce + 2);
    (address[2] memory _targets, bytes[2] memory _data) =
      vaultRescuer.rescueCalls(_balance);
    for (uint256 i = 0; i < _targets.length; i++) {
      assertTrue(
        TIMELOCK.queuedTransactions(
          vaultRescuer.timelockHash(_targets[i], _data[i], _eta)
        )
      );
    }

    // Before the upgrade the queued `send` cannot execute.
    vm.warp(_eta);
    vm.prank(address(ADMIN));
    vm.expectRevert(
      "Timelock::executeTransaction: Transaction execution reverted."
    );
    TIMELOCK.executeTransaction(_targets[0], 0, "", _data[0], _eta);

    // The cause is the vault's ERC-20 send reaching the missing `transfer`.
    vm.prank(address(TIMELOCK));
    (bool _success, bytes memory _revert) = address(VAULT).call(_data[0]);
    assertFalse(_success);
    assertEq(
      _revert,
      abi.encodeWithSignature("Error(string)", "SafeERC20: low-level call failed")
    );

    // After the upgrade the very same queued calls execute.
    _upgrade();
    uint256 _supply = POOL.totalSupply();
    uint256 _ether = address(TIMELOCK).balance;
    vaultRescuer.execute(_eta, _balance);
    assertEq(POOL.balanceOf(address(VAULT)), 0);
    assertEq(POOL.balanceOf(address(TIMELOCK)), 0);
    assertEq(address(TIMELOCK).balance, _ether + _balance);
    assertEq(POOL.totalSupply(), _supply - _balance);
    assertEq(POOL.totalSupply(), address(POOL).balance);
    assertEq(ADMIN.nonce(), _nonce + 4);
    for (uint256 i = 0; i < _targets.length; i++) {
      assertFalse(
        TIMELOCK.queuedTransactions(
          vaultRescuer.timelockHash(_targets[i], _data[i], _eta)
        )
      );
    }

    // Nothing about the vault's governance changed.
    assertEq(VAULT.owner(), address(TIMELOCK));
    assertEq(TIMELOCK.admin(), address(ADMIN));
    assertEq(_adminGuard(), address(GUARD));
  }
}
