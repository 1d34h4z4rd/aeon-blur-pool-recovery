// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title PROOF Payment Conduit Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The PROOF Holdings `PaymentConduit`, used as the royalty receiver for
  Moonbirds and Oddities. It can only forward its ERC-20 balance by calling
  `transfer` on the token, so Blur Pool balances are stuck.

  @custom:date November 6th, 2026.
*/
interface IPaymentConduit {

  /**
    Return the address all funds are forwarded to.

    @return _ The forwarding target.
  */
  function target () external view returns (address);

  /**
    Forward the conduit's entire balance of `_token` to the target via
    `SafeERC20.safeTransfer`.

    @param _token The ERC-20 token to forward.
  */
  function forwardERC20 (
    address _token
  ) external;
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title 0xSplits SplitMain Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The 0xSplits v1 `SplitMain`. Distributing a split's ERC-20 balance pulls it
  from the split wallet with `transfer`, and withdrawing pays recipients with
  `transfer`, so Blur Pool balances held by split wallets are stuck.

  @custom:date November 6th, 2026.
*/
interface ISplitMain {

  /**
    Return the hash of a split's recipients, allocations, and fee.

    @param _split The split wallet.

    @return _ The split hash.
  */
  function getHash (
    address _split
  ) external view returns (bytes32);

  /**
    Return the ERC-20 balance credited to `_account` within `SplitMain`.

    @param _account The account.
    @param _token The ERC-20 token.

    @return _ The credited balance.
  */
  function getERC20Balance (
    address _account,
    address _token
  ) external view returns (uint256);

  /**
    Distribute a split wallet's balance of `_token` to its recipients' credited
    balances within `SplitMain`. Permissionless for immutable splits.

    @param _split The split wallet.
    @param _token The ERC-20 token to distribute.
    @param _accounts The split's recipients, sorted ascending.
    @param _percentAllocations The recipients' allocations (1e6 = 100%).
    @param _distributorFee The distributor fee (1e6 = 100%).
    @param _distributorAddress The address receiving the distributor fee.
  */
  function distributeERC20 (
    address _split,
    address _token,
    address[] calldata _accounts,
    uint32[] calldata _percentAllocations,
    uint32 _distributorFee,
    address _distributorAddress
  ) external;

  /**
    Withdraw `_account`'s credited balances to `_account`. Permissionless.

    @param _account The account to withdraw for.
    @param _withdrawETH Nonzero to also withdraw Ether.
    @param _tokens The ERC-20 tokens to withdraw.
  */
  function withdraw (
    address _account,
    uint256 _withdrawETH,
    address[] calldata _tokens
  ) external;
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Updatable Splitter Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The `UpdatableSplitter` from the `mikker/contracts` package, deployed as
  `RoyaltiesSplitter`. Flushing an ERC-20 pays each payee with `transfer`, so
  Blur Pool balances are stuck.

  @custom:date November 6th, 2026.
*/
interface IUpdatableSplitter {

  /**
    Return the role permitted to flush.

    @return _ The `FLUSHWORTHY` role.
  */
  function FLUSHWORTHY () external view returns (bytes32);

  /**
    Return whether `_account` holds `_role`.

    @param _role The role.
    @param _account The account.

    @return _ Whether `_account` holds `_role`.
  */
  function hasRole (
    bytes32 _role,
    address _account
  ) external view returns (bool);

  /**
    Return the total shares across all payees.

    @return _ The total shares.
  */
  function totalShares () external view returns (uint256);

  /**
    Return the payee at `_index`.

    @param _index The payee index.

    @return _ The payee.
  */
  function payee (
    uint256 _index
  ) external view returns (address);

  /**
    Return the shares held by `_payee`.

    @param _payee The payee.

    @return _ The shares.
  */
  function shares (
    address _payee
  ) external view returns (uint256);

  /**
    Split the splitter's entire balance of `_token` among the payees via
    `SafeERC20.safeTransfer`; restricted to `FLUSHWORTHY`.

    @param _token The ERC-20 token to flush.
  */
  function flushToken (
    address _token
  ) external;
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title OpenZeppelin Payment Splitter Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  OpenZeppelin's v4.4.1 `PaymentSplitter`, deployed as `RoyaltyPaymentSplitter`.
  Releasing an ERC-20 pays a payee with `transfer`, so Blur Pool balances are
  stuck.

  @custom:date November 6th, 2026.
*/
interface IPaymentSplitter {

  /**
    Return the total shares across all payees.

    @return _ The total shares.
  */
  function totalShares () external view returns (uint256);

  /**
    Return the payee at `_index`.

    @param _index The payee index.

    @return _ The payee.
  */
  function payee (
    uint256 _index
  ) external view returns (address);

  /**
    Return the shares held by `_payee`.

    @param _payee The payee.

    @return _ The shares.
  */
  function shares (
    address _payee
  ) external view returns (uint256);

  /**
    Release `_account`'s owed share of `_token` via `SafeERC20.safeTransfer`.
    Permissionless.

    @param _token The ERC-20 token to release.
    @param _account The payee to pay.
  */
  function release (
    address _token,
    address _account
  ) external;
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Asset Vault Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The unverified version 2 `AssetVault` (its selectors match `src/AssetVault.sol`
  at commit `f58318a` of the vault repository). Its owner can only move an
  ERC-20 out with `send`, which calls `SafeERC20.safeTransfer`, so Blur Pool
  balances are stuck.

  @custom:date November 6th, 2026.
*/
interface IAssetVault {

  /**
    The type of asset a send moves.

    @param Ether Ether.
    @param ERC20 An ERC-20 token.
    @param ERC721 An ERC-721 item.
    @param ERC1155 An ERC-1155 item.
  */
  enum AssetType {
    Ether,
    ERC20,
    ERC721,
    ERC1155
  }

  /**
    A request to send one asset to one recipient.

    @param assetType The type of asset.
    @param recipientAddress The recipient.
    @param assetAddress The asset contract; ignored for Ether.
    @param amounts For Ether and ERC-20, a singleton array of the amount.
    @param ids For ERC-721 and ERC-1155, the item IDs.
  */
  struct SendSpecification {
    AssetType assetType;
    address recipientAddress;
    address assetAddress;
    uint256[] amounts;
    uint256[] ids;
  }

  /**
    Return the vault owner.

    @return _ The owner.
  */
  function owner () external view returns (address);

  /**
    Send assets out of the vault; restricted to the owner.

    @param _sends The sends to perform.
  */
  function send (
    SendSpecification[] calldata _sends
  ) external;
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Timelock Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The Compound-style `Timelock` that owns the `AssetVault`. Its admin queues a
  call, waits out the delay, and then executes it within the grace period.

  @custom:date November 6th, 2026.
*/
interface ITimelock {

  /**
    Return the admin permitted to queue and execute.

    @return _ The admin.
  */
  function admin () external view returns (address);

  /**
    Return the minimum time between queueing and execution.

    @return _ The delay in seconds.
  */
  function delay () external view returns (uint256);

  /**
    Return how long after its ETA a queued call remains executable.

    @return _ The grace period in seconds.
  */
  function GRACE_PERIOD () external view returns (uint256);

  /**
    Return whether a call is queued.

    @param _txHash The `keccak256(abi.encode(target, value, signature, data,
      eta))` hash of the call.

    @return _ Whether the call is queued.
  */
  function queuedTransactions (
    bytes32 _txHash
  ) external view returns (bool);

  /**
    Queue a call; restricted to the admin.

    @param _target The call target.
    @param _value The Ether value.
    @param _signature The function signature, or empty to use `_data` as is.
    @param _data The calldata.
    @param _eta The earliest execution time; at least `delay` from now.

    @return _ The call hash.
  */
  function queueTransaction (
    address _target,
    uint256 _value,
    string calldata _signature,
    bytes calldata _data,
    uint256 _eta
  ) external returns (bytes32);

  /**
    Execute a queued call; restricted to the admin.

    @param _target The call target.
    @param _value The Ether value.
    @param _signature The function signature, or empty to use `_data` as is.
    @param _data The calldata.
    @param _eta The queued execution time.

    @return _ The call's return data.
  */
  function executeTransaction (
    address _target,
    uint256 _value,
    string calldata _signature,
    bytes calldata _data,
    uint256 _eta
  ) external payable returns (bytes memory);
}

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Scope Guard Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The Zodiac-style `ScopeGuard` installed on the `AssetVault`'s admin Safe,
  which limits the Safe to allowlisted call targets and functions.

  @custom:date November 6th, 2026.
*/
interface IScopeGuard {

  /**
    Return whether the Safe may call `_target` at all.

    @param _target The call target.

    @return _ Whether `_target` is allowed.
  */
  function isAllowedTarget (
    address _target
  ) external view returns (bool);

  /**
    Return whether calls to `_target` are limited to allowlisted functions.

    @param _target The call target.

    @return _ Whether `_target` is scoped.
  */
  function isScoped (
    address _target
  ) external view returns (bool);
}
