// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { IBlurPool } from "../pool/interfaces/IBlurPool.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Blur Pool Proxy Interface
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The full external surface of the Blur Pool behind its ERC-1967 proxy: Blur's
  own `IBlurPool` (including the added `transfer`) plus the public functions it
  inherits from OpenZeppelin's `OwnableUpgradeable` and `UUPSUpgradeable`.
  Tests and scripts use this so that they never import the
  `pragma solidity 0.8.17` implementation itself.

  @custom:date November 6th, 2026.
*/
interface IBlurPoolProxy is
  IBlurPool {

  /**
    Return the pool name.

    @return _ The name, "Blur Pool".
  */
  function name () external view returns (string memory);

  /**
    Return the owner permitted to upgrade the pool.

    @return _ The owner.
  */
  function owner () external view returns (address);

  /**
    Return the ERC-1822 storage slot this UUPS implementation upgrades.

    @return _ The ERC-1967 implementation slot.
  */
  function proxiableUUID () external view returns (bytes32);

  /**
    Upgrade the proxy to `_newImplementation`; restricted to the owner.

    @param _newImplementation The new implementation.
  */
  function upgradeTo (
    address _newImplementation
  ) external;
}
