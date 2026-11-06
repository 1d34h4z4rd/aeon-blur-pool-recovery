// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { ICreateX } from "../src/interfaces/ICreateX.sol";
import { Deployment } from "./Deployment.sol";
import { WithSigner } from "./WithSigner.s.sol";
import { console } from "forge-std/Script.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Deploy Blur Pool
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  Deploy the patched Blur Pool implementation, which adds ERC-20 `transfer`,
  through CreateX at its deterministic `CREATE2` address, constructed with
  exactly the four constructor arguments of the live implementation. Deployment is
  permissionless and idempotent: anyone may run this, and rerunning it after a
  deployment is a no-op.

  @custom:date November 6th, 2026.
*/
contract DeployBlurPool is
  WithSigner {

  /// This error is thrown if the built init code differs from the pinned one.
  error UnexpectedInitCode ();

  /// This error is thrown if CreateX deploys to an unexpected address.
  error UnexpectedAddress ();

  /// This error is thrown if the implementation is not a valid UUPS target.
  error NotProxiable ();

  /**
    Run the script, broadcasting from the signer selected by `WithSigner`.

    @return _ The implementation address.
  */
  function run () external withSignerIndex(0) returns (address) {
    return deploy();
  }

  /**
    Deploy the patched implementation unless it is already deployed.

    @return _implementation The implementation address.
  */
  function deploy () public returns (address _implementation) {
    bytes32 _initCodeHash = keccak256(Deployment.initCode());
    address _expected = Deployment.implementation();
    console.log("Deploy Blur Pool implementation");
    console.log("  CreateX:", Deployment.CREATEX);
    console.log("  Salt:");
    console.logBytes32(Deployment.SALT);
    console.log("  Init code hash:");
    console.logBytes32(_initCodeHash);
    console.log("  Expected implementation:", _expected);

    // Refuse to deploy anything but the pinned, reviewed build.
    if (_initCodeHash != Deployment.EXPECTED_INIT_CODE_HASH) {
      revert UnexpectedInitCode();
    }
    if (_expected != Deployment.EXPECTED_IMPLEMENTATION) {
      revert UnexpectedAddress();
    }

    // Deployment is idempotent; the address commits to the exact init code.
    if (_expected.code.length > 0) {
      console.log("  - Already deployed");
      return _expected;
    }

    // Deploy and verify.
    _implementation = ICreateX(Deployment.CREATEX).deployCreate2(
      Deployment.SALT,
      Deployment.initCode()
    );
    if (_implementation != _expected) {
      revert UnexpectedAddress();
    }
    if (
      IBlurPoolProxy(_implementation).proxiableUUID()
        != Deployment.IMPLEMENTATION_SLOT
    ) {
      revert NotProxiable();
    }
    console.log("  - Deployed:", _implementation);
  }
}
