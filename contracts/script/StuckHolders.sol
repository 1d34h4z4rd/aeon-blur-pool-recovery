// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Stuck Holders
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Royalty-receiving contracts on mainnet that hold Blur Pool balances they can
  only move with ERC-20 `transfer`. Each is a deployed, widely-used receiver
  type whose only exit for an ERC-20 is `SafeERC20.safeTransfer` (or solmate's
  equivalent); none can make the arbitrary `withdraw` call Blur Pool requires.
  These were found among the largest Blur Pool holders.

  @custom:date November 6th, 2026.
*/
library StuckHolders {

  /// The PROOF `PaymentConduit` receiving Moonbirds royalties.
  address internal constant MOONBIRDS_CONDUIT =
    0x73464dfeAc74096a05604234b471412c73D5076F;

  /// The PROOF `PaymentConduit` receiving Oddities royalties.
  address internal constant ODDITIES_CONDUIT =
    0xB62638857FEBb2900BA5b3E5d296201f4E12E0C4;

  /// The forwarding target of both PROOF conduits; a Safe.
  address internal constant PROOF_TARGET =
    0x686BD755B9396e93Eb924Da11F78f3c92076494E;

  /// The 0xSplits v1 `SplitMain`.
  address internal constant SPLIT_MAIN =
    0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;

  /**
    An immutable 0xSplits v1 split wallet, created through a
    `RevenueModuleFactory`. Its recipients and allocations below were recovered
    from its creation transaction and match its on-chain split hash.
  */
  address internal constant SPLIT_WALLET =
    0xBE36007bFbefE69F5e2F9B1438FC2A15AE99494F;

  /// The first `SPLIT_WALLET` recipient, receiving 10%.
  address internal constant SPLIT_ACCOUNT_0 =
    0x0F4f0D655FaF4Dc5CbA991147aa3a29139e3B110;

  /// The second `SPLIT_WALLET` recipient, receiving 20%.
  address internal constant SPLIT_ACCOUNT_1 =
    0x6C0203B042A91CA94b9DFEDf72Adb1147D6f4aA2;

  /// The third `SPLIT_WALLET` recipient, receiving 70%.
  address internal constant SPLIT_ACCOUNT_2 =
    0xde21F729137C5Af1b01d73aF1dC21eFfa2B8a0d6;

  /// A `mikker/contracts` `UpdatableSplitter` deployed as `RoyaltiesSplitter`.
  address internal constant ROYALTIES_SPLITTER_A =
    0x8fE67eBcF516EfB408E537BD390dfde4Fae7448D;

  /// A second `UpdatableSplitter` deployed as `RoyaltiesSplitter`.
  address internal constant ROYALTIES_SPLITTER_B =
    0x4C78656fAea93b5305c69064B5C40Fae62C9Ba73;

  /// The deployer of both `RoyaltiesSplitter`s; it holds `FLUSHWORTHY`.
  address internal constant ROYALTIES_FLUSHER =
    0xd7E5E1c0Cb9540669d8F22F71C9540460db23938;

  /// An OpenZeppelin v4.4.1 `PaymentSplitter` deployed as
  /// `RoyaltyPaymentSplitter`.
  address internal constant ROYALTY_PAYMENT_SPLITTER =
    0x9906De9E0D9ef5960d02dF2261Ecaa78EC8CE45D;

  /// The version 2 `AssetVault` named "One".
  address internal constant ASSET_VAULT =
    0x7578425460C842CA077544FFe224Cf213c931241;

  /// The Compound-style `Timelock` (three-day delay) that owns `ASSET_VAULT`.
  address internal constant ASSET_VAULT_TIMELOCK =
    0xc9D59a09782cFD5a7E120EFBC73fB8F9725113aB;

  /// The 2-of-3 Safe v1.3.0 administering `ASSET_VAULT_TIMELOCK`.
  address internal constant ASSET_VAULT_ADMIN =
    0x43E2e78C8E6F2CE57FbD970C811E70e0044389AA;

  /**
    The `ScopeGuard` installed on `ASSET_VAULT_ADMIN`. It allows the admin to
    call `ASSET_VAULT_TIMELOCK` but not Blur Pool or the vault directly, so the
    rescued balance is sent to, and unwrapped by, the timelock.
  */
  address internal constant ASSET_VAULT_ADMIN_GUARD =
    0xFB63a1027e335AF40b031C44790582ac59A4fEE9;

  /**
    Return the `SPLIT_WALLET` recipients, sorted ascending as `SplitMain`
    requires.

    @return _accounts The recipients.
  */
  function splitAccounts () internal pure returns (
    address[] memory _accounts
  ) {
    _accounts = new address[](3);
    _accounts[0] = SPLIT_ACCOUNT_0;
    _accounts[1] = SPLIT_ACCOUNT_1;
    _accounts[2] = SPLIT_ACCOUNT_2;
  }

  /**
    Return the `SPLIT_WALLET` allocations, aligned with `splitAccounts()`.

    @return _allocations The allocations, where 1e6 is 100%.
  */
  function splitAllocations () internal pure returns (
    uint32[] memory _allocations
  ) {
    _allocations = new uint32[](3);
    _allocations[0] = 100_000;
    _allocations[1] = 200_000;
    _allocations[2] = 700_000;
  }
}
