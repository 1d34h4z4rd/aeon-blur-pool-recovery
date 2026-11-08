// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { ICreateX } from "../src/interfaces/ICreateX.sol";
import { Vm } from "forge-std/Vm.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Blur Pool Deployment
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The mainnet addresses and deterministic deployment parameters for the Blur
  Pool ERC-20 `transfer` upgrade, shared by every script and test so that the
  simulated deployment and the tested deployment are the same deployment.

  The replacement implementation is deployed through CreateX with `CREATE2`
  rather than `CREATE3`. A `CREATE2` address commits to the exact init code
  (the patched `BlurPool` creation code plus Blur's four original constructor
  arguments), so anyone may deploy it permissionlessly and Blur's signers can
  trust that the address they approve holds exactly the reviewed code. Under
  `CREATE3` the address commits only to the salt and an unprotected salt could
  be front-run with different code.

  @custom:date November 6th, 2026.
*/
library Deployment {

  /// The Foundry cheatcode address.
  Vm private constant VM =
    Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

  /// The Blur Pool ERC-1967 proxy; this is the token address.
  address internal constant BLUR_POOL =
    0x0000000000A39bb272e79075ade125fd351887Ac;

  /// The Blur Pool implementation live on mainnet before the upgrade.
  address internal constant CURRENT_IMPLEMENTATION =
    0x01a656024de4B89e2D0198BF4D468E8fd2358b17;

  /// The Blur Pool owner: a 3-of-5 Safe v1.3.0.
  address internal constant BLUR_POOL_OWNER =
    0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb;

  /// Blur Exchange; the first original `BlurPool` constructor argument.
  address internal constant EXCHANGE =
    0x000000000000Ad05Ccc4F10045630fb830B95127;

  /// Blur Exchange V2; the second original `BlurPool` constructor argument.
  address internal constant EXCHANGE_V2 =
    0xb2ecfE4E4D61f8790bbb9DE2D1259B9e2410CEA5;

  /// Blur Swap; the third original `BlurPool` constructor argument.
  address internal constant SWAP =
    0x39da41747a83aeE658334415666f3EF92DD0D541;

  /// Blend; the fourth original `BlurPool` constructor argument.
  address internal constant BLEND =
    0x29469395eAf6f95920E59F858042f0e28D98a20B;

  /// The CreateX factory.
  address internal constant CREATEX =
    0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

  /**
    The CreateX salt for the replacement implementation. The zero-address
    prefix and `0x00` flag byte select CreateX's unprotected mode (anyone may
    deploy, on any chain), which CreateX guards by hashing the salt; the tail
    is "BlurPoolFix" in ASCII.
  */
  bytes32 internal constant SALT =
    0x000000000000000000000000000000000000000000426c7572506f6f6c466978;

  /**
    The pinned hash of the patched implementation's init code. Any change to
    the patched source's bytecode, the compiler settings, or the constructor
    arguments changes this hash and so the deployment address; the deploy
    script refuses to run on a mismatch so that the address shared with Blur
    can only ever hold the reviewed code. Comments do not affect it, since
    the metadata hash is disabled.
  */
  bytes32 internal constant EXPECTED_INIT_CODE_HASH =
    0x35a5742b5e2489a0bfd0ac6e33fb91b872aeb0b3e37319f49c25c6b1343dc1fe;

  /// The pinned address of the patched implementation.
  address internal constant EXPECTED_IMPLEMENTATION =
    0xc74ACcF8939b29530CC54499661E5D57729243F1;

  /// The ERC-1967 implementation slot.
  bytes32 internal constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /// The artifact of the patched implementation.
  string internal constant PATCHED_ARTIFACT = "src/pool/BlurPool.sol:BlurPool";

  /// The artifact of the pristine upstream implementation.
  string internal constant UPSTREAM_ARTIFACT =
    "src/upstream/pool/BlurPool.sol:BlurPool";

  /**
    Return the original constructor arguments of the live implementation.

    @return _ The ABI-encoded `(exchange, exchangeV2, swap, blend)`.
  */
  function constructorArgs () internal pure returns (bytes memory) {
    return abi.encode(EXCHANGE, EXCHANGE_V2, SWAP, BLEND);
  }

  /**
    Return the init code of the patched implementation.

    @return _ The patched creation code with the original constructor
      arguments appended.
  */
  function initCode () internal view returns (bytes memory) {
    return abi.encodePacked(VM.getCode(PATCHED_ARTIFACT), constructorArgs());
  }

  /**
    Return the salt as CreateX will guard it for an unprotected `CREATE2`.

    @return _ The guarded salt.
  */
  function guardedSalt () internal pure returns (bytes32) {
    return keccak256(abi.encode(SALT));
  }

  /**
    Return the deterministic address of the patched implementation.

    @return _ The CreateX `CREATE2` address of `initCode()` under `SALT`.
  */
  function implementation () internal view returns (address) {
    return ICreateX(CREATEX).computeCreate2Address(
      guardedSalt(),
      keccak256(initCode())
    );
  }
}
