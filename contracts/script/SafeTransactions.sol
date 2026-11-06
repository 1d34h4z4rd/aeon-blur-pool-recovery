// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { ISafe } from "../src/interfaces/ISafe.sol";
import { Script, console } from "forge-std/Script.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Safe Transactions
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Execute a plain call from a Safe v1.3.0 exactly as its signers would, without
  their private keys: `threshold` real owners each approve the Safe transaction
  hash on-chain with `approveHash` (the Safe's "approved hash" signature type,
  `v = 1`), and one of them executes it. Nothing about the Safe is bypassed;
  `execTransaction` verifies the approvals at the live nonce and runs any
  installed transaction guard. Against a local fork the approvals and the
  execution broadcast from impersonated owners (`anvil --auto-impersonate` with
  `--unlocked`); in tests they act as pranks.

  @custom:date November 6th, 2026.
*/
abstract contract SafeTransactions is
  Script {

  /**
    Return the hash a Safe's owners sign for a plain call at its current nonce.

    @param _safe The Safe.
    @param _to The call target.
    @param _data The calldata.

    @return _ The Safe transaction hash.
  */
  function _safeTransactionHash (
    ISafe _safe,
    address _to,
    bytes memory _data
  ) internal view returns (bytes32) {
    return _safe.getTransactionHash(
      _to,
      0,
      _data,
      ISafe.Operation.Call,
      0,
      0,
      0,
      address(0),
      address(0),
      _safe.nonce()
    );
  }

  /**
    Approve and execute a plain call from `_safe`.

    @param _safe The Safe.
    @param _to The call target.
    @param _data The calldata.

    @return _safeTxHash The executed Safe transaction hash.
  */
  function _executeThroughSafe (
    ISafe _safe,
    address _to,
    bytes memory _data
  ) internal returns (bytes32 _safeTxHash) {
    _safeTxHash = _safeTransactionHash(_safe, _to, _data);

    // Approve from `threshold` owners and pack their approved-hash signatures.
    address[] memory _signers = _sortedSigners(_safe);
    bytes memory _signatures;
    for (uint256 i = 0; i < _signers.length; i++) {
      vm.startBroadcast(_signers[i]);
      _safe.approveHash(_safeTxHash);
      vm.stopBroadcast();
      console.log("  - Approved by:", _signers[i]);
      _signatures = abi.encodePacked(
        _signatures,
        bytes32(uint256(uint160(_signers[i]))),
        bytes32(0),
        uint8(1)
      );
    }

    // Execute. With zero `safeTxGas` and `gasPrice` a failed inner call
    // reverts the whole transaction rather than consuming the nonce.
    vm.startBroadcast(_signers[0]);
    _safe.execTransaction(
      _to,
      0,
      _data,
      ISafe.Operation.Call,
      0,
      0,
      0,
      address(0),
      payable(address(0)),
      _signatures
    );
    vm.stopBroadcast();
    console.log("  - Executed by:", _signers[0]);
  }

  /**
    Return the transaction guard installed on `_safe`, if any.

    @param _safe The Safe.

    @return _ The guard, or the zero address.
  */
  function _guardOf (
    ISafe _safe
  ) internal view returns (address) {
    bytes32 _slot = keccak256("guard_manager.guard.address");
    return abi.decode(_safe.getStorageAt(uint256(_slot), 1), (address));
  }

  /**
    Return the first `threshold` Safe owners sorted ascending, which is the
    order the Safe requires signatures in.

    @param _safe The Safe.

    @return _signers The signing owners.
  */
  function _sortedSigners (
    ISafe _safe
  ) internal view returns (address[] memory _signers) {
    address[] memory _owners = _safe.getOwners();
    _signers = new address[](_safe.getThreshold());
    for (uint256 i = 0; i < _signers.length; i++) {
      _signers[i] = _owners[i];
    }
    for (uint256 i = 1; i < _signers.length; i++) {
      address _signer = _signers[i];
      uint256 j = i;
      while (j > 0 && _signers[j - 1] > _signer) {
        _signers[j] = _signers[j - 1];
        j--;
      }
      _signers[j] = _signer;
    }
  }
}
