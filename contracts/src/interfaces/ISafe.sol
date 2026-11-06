// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Safe Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The subset of the Safe v1.3.0 multisignature wallet interface needed to
  propose, approve, and execute the Blur Pool upgrade from Blur's owning Safe.

  @custom:date November 6th, 2026.
*/
interface ISafe {

  /**
    The type of call a Safe transaction makes.

    @param Call A regular call.
    @param DelegateCall A delegate call.
  */
  enum Operation {
    Call,
    DelegateCall
  }

  /**
    Return the current Safe transaction nonce.

    @return _ The nonce.
  */
  function nonce () external view returns (uint256);

  /**
    Return the number of owner confirmations required to execute.

    @return _ The threshold.
  */
  function getThreshold () external view returns (uint256);

  /**
    Return the owners of the Safe.

    @return _ The owner addresses.
  */
  function getOwners () external view returns (address[] memory);

  /**
    Return whether `_owner` is an owner of the Safe.

    @param _owner The address to check.

    @return _ Whether `_owner` is an owner.
  */
  function isOwner (
    address _owner
  ) external view returns (bool);

  /**
    Read raw words of the Safe's storage. Used to check the transaction guard
    slot, since a nonzero guard could veto the upgrade transaction.

    @param _offset The first storage slot to read.
    @param _length The number of words to read.

    @return _ The raw storage words.
  */
  function getStorageAt (
    uint256 _offset,
    uint256 _length
  ) external view returns (bytes memory);

  /**
    Return the EIP-712 hash that owners sign for a Safe transaction.

    @param _to The destination of the transaction.
    @param _value The Ether value of the transaction.
    @param _data The calldata of the transaction.
    @param _operation The type of call.
    @param _safeTxGas The gas forwarded to the transaction.
    @param _baseGas The gas cost independent of the transaction execution.
    @param _gasPrice The gas price used for refunds.
    @param _gasToken The token used for refunds.
    @param _refundReceiver The receiver of refunds.
    @param _nonce The Safe transaction nonce.

    @return _ The Safe transaction hash.
  */
  function getTransactionHash (
    address _to,
    uint256 _value,
    bytes calldata _data,
    Operation _operation,
    uint256 _safeTxGas,
    uint256 _baseGas,
    uint256 _gasPrice,
    address _gasToken,
    address _refundReceiver,
    uint256 _nonce
  ) external view returns (bytes32);

  /**
    Mark a Safe transaction hash as approved by the caller, an owner. This is
    the on-chain equivalent of an owner's signature.

    @param _hashToApprove The Safe transaction hash to approve.
  */
  function approveHash (
    bytes32 _hashToApprove
  ) external;

  /**
    Return whether `_owner` approved `_hash` on-chain.

    @param _owner The owner.
    @param _hash The Safe transaction hash.

    @return _ Nonzero if approved.
  */
  function approvedHashes (
    address _owner,
    bytes32 _hash
  ) external view returns (uint256);

  /**
    Execute a Safe transaction once it has `threshold` valid signatures.

    @param _to The destination of the transaction.
    @param _value The Ether value of the transaction.
    @param _data The calldata of the transaction.
    @param _operation The type of call.
    @param _safeTxGas The gas forwarded to the transaction.
    @param _baseGas The gas cost independent of the transaction execution.
    @param _gasPrice The gas price used for refunds.
    @param _gasToken The token used for refunds.
    @param _refundReceiver The receiver of refunds.
    @param _signatures The packed owner signatures, sorted by owner address.

    @return _ Whether the inner transaction succeeded.
  */
  function execTransaction (
    address _to,
    uint256 _value,
    bytes calldata _data,
    Operation _operation,
    uint256 _safeTxGas,
    uint256 _baseGas,
    uint256 _gasPrice,
    address _gasToken,
    address payable _refundReceiver,
    bytes memory _signatures
  ) external payable returns (bool);
}
