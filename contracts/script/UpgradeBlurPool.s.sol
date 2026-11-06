// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { ISafe } from "../src/interfaces/ISafe.sol";
import { Deployment } from "./Deployment.sol";
import { SafeTransactions } from "./SafeTransactions.sol";
import { console } from "forge-std/Script.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Upgrade Blur Pool
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Upgrade the Blur Pool proxy to the patched implementation through Blur's
  owning Safe, exactly as Blur's signers would. This builds the single Safe
  transaction (`upgradeTo(implementation)` on the proxy, a plain call with no
  value or refund), prints what the signers must verify, then approves and
  executes it through `SafeTransactions`.

  Against mainnet the broadcast is impossible without the owners, so the script
  doubles as the proposal: run it without `--broadcast` to print the Safe
  transaction and simulate its execution. Against a local fork it broadcasts
  from impersonated owners (`anvil --auto-impersonate` with `--unlocked`).

  @custom:date November 6th, 2026.
*/
contract UpgradeBlurPool is
  SafeTransactions {

  /// This error is thrown if the implementation has no code.
  error ImplementationMissing ();

  /// This error is thrown if the owning Safe has a transaction guard.
  error GuardInstalled ();

  /// This error is thrown if the proxy does not point at the implementation.
  error UpgradeFailed ();

  /**
    Run the script. The implementation defaults to the deterministic address
    of `DeployBlurPool` and may be overridden with `IMPLEMENTATION`.
  */
  function run () external {
    upgrade(vm.envOr("IMPLEMENTATION", Deployment.implementation()));
  }

  /**
    Print the Safe transaction Blur's signers must create and verify, without
    approving or executing it. This works before the implementation is
    deployed; the transaction hash depends on the Safe's nonce at signing.
  */
  function propose () external view {
    address _implementation =
      vm.envOr("IMPLEMENTATION", Deployment.implementation());
    _logProposal(_implementation);
    console.log(
      "  Implementation deployed:",
      _implementation.code.length > 0 ? "yes" : "no (run DeployBlurPool)"
    );
  }

  /**
    Return the calldata the Safe sends to the proxy.

    @param _implementation The new implementation.

    @return _ The `upgradeTo` calldata.
  */
  function upgradeCalldata (
    address _implementation
  ) public pure returns (bytes memory) {
    return abi.encodeCall(IBlurPoolProxy.upgradeTo, (_implementation));
  }

  /**
    Return the hash Safe owners sign to upgrade at the Safe's current nonce.

    @param _implementation The new implementation.

    @return _ The Safe transaction hash.
  */
  function safeTransactionHash (
    address _implementation
  ) public view returns (bytes32) {
    return _safeTransactionHash(
      ISafe(Deployment.BLUR_POOL_OWNER),
      Deployment.BLUR_POOL,
      upgradeCalldata(_implementation)
    );
  }

  /**
    Upgrade the Blur Pool through its owning Safe.

    @param _implementation The new implementation.
  */
  function upgrade (
    address _implementation
  ) public {
    if (_implementation.code.length == 0) {
      revert ImplementationMissing();
    }
    ISafe _safe = ISafe(Deployment.BLUR_POOL_OWNER);
    if (_guardOf(_safe) != address(0)) {
      revert GuardInstalled();
    }
    _logProposal(_implementation);
    _executeThroughSafe(
      _safe,
      Deployment.BLUR_POOL,
      upgradeCalldata(_implementation)
    );
    if (_liveImplementation() != _implementation) {
      revert UpgradeFailed();
    }
    console.log("  New implementation:", _implementation);
  }

  /**
    Print the Safe transaction that upgrades to `_implementation`.

    @param _implementation The new implementation.
  */
  function _logProposal (
    address _implementation
  ) internal view {
    ISafe _safe = ISafe(Deployment.BLUR_POOL_OWNER);
    console.log("Upgrade Blur Pool via Safe");
    console.log("  Safe:", address(_safe));
    console.log("  Threshold:", _safe.getThreshold());
    console.log("  Nonce:", _safe.nonce());
    console.log("  To:", Deployment.BLUR_POOL);
    console.log("  Value: 0");
    console.log("  Operation: 0 (CALL)");
    console.log("  Data (upgradeTo(%s)):", _implementation);
    console.logBytes(upgradeCalldata(_implementation));
    console.log("  Safe transaction hash at this nonce:");
    console.logBytes32(safeTransactionHash(_implementation));
    console.log("  Current implementation:", _liveImplementation());
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
}
