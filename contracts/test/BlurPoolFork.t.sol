// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { DeployBlurPool } from "../script/DeployBlurPool.s.sol";
import { Deployment } from "../script/Deployment.sol";
import { RescueStuckFunds } from "../script/RescueStuckFunds.s.sol";
import { UpgradeBlurPool } from "../script/UpgradeBlurPool.s.sol";
import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { Test } from "forge-std/Test.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Blur Pool Fork Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The shared base for tests against a mainnet fork pinned to `FORK_BLOCK`. The
  upgrade is performed by the very same `DeployBlurPool` and `UpgradeBlurPool`
  script code used for the simulated deployment, so the tests exercise the
  real CreateX deployment and the real Safe approval and execution flow rather
  than pranking the Safe past its own signature checks.

  @custom:date November 6th, 2026.
*/
abstract contract BlurPoolForkTest is
  Test {

  /// The block to fork when `FORK_BLOCK` is unset; keep in sync with the
  /// Makefile.
  uint256 internal constant DEFAULT_FORK_BLOCK = 26_357_000;

  /// The Blur Pool proxy.
  IBlurPoolProxy internal constant POOL = IBlurPoolProxy(Deployment.BLUR_POOL);

  /// The deployment script.
  DeployBlurPool internal deployer;

  /// The upgrade script.
  UpgradeBlurPool internal upgrader;

  /// The rescue script.
  RescueStuckFunds internal rescuer;

  /// Fork mainnet and prepare the scripts.
  function setUp () public virtual {
    vm.createSelectFork("mainnet", vm.envOr("FORK_BLOCK", DEFAULT_FORK_BLOCK));
    deployer = new DeployBlurPool();
    upgrader = new UpgradeBlurPool();
    rescuer = new RescueStuckFunds();
  }

  /**
    Deploy the patched implementation and upgrade the proxy to it through the
    owning Safe.

    @return _implementation The new implementation.
  */
  function _upgrade () internal returns (address _implementation) {
    _implementation = deployer.deploy();
    upgrader.upgrade(_implementation);
  }

  /**
    Return the implementation the proxy currently points at.

    @return _ The implementation address.
  */
  function _liveImplementation () internal view returns (address) {
    return address(uint160(uint256(
      vm.load(Deployment.BLUR_POOL, Deployment.IMPLEMENTATION_SLOT)
    )));
  }

  /**
    Assert that `_holder` can unwrap its whole Blur Pool balance to Ether.

    @param _holder The holder, which must be able to make arbitrary calls.
  */
  function _assertWithdraws (
    address _holder
  ) internal {
    uint256 _balance = POOL.balanceOf(_holder);
    uint256 _ether = _holder.balance;
    vm.prank(_holder);
    POOL.withdraw(_balance);
    assertEq(POOL.balanceOf(_holder), 0, "pool balance not withdrawn");
    assertEq(_holder.balance, _ether + _balance, "ether not received");
  }
}
