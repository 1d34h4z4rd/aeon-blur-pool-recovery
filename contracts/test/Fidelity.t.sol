// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { Deployment } from "../script/Deployment.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Fidelity Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The patch starts from Blur's exact contract. The pristine upstream source in
  `src/upstream` compiles to the byte-identical runtime code of the live
  implementation, and the patched source keeps its storage layout while adding
  nothing to its external interface beyond `transfer`.

  @custom:date November 6th, 2026.
*/
contract FidelityTest is
  BlurPoolForkTest {

  /// The artifact Forge writes for the patched `src/pool/BlurPool.sol`.
  string internal constant PATCHED_JSON = "out/BlurPool.sol/BlurPool.json";

  /// The artifact Forge writes for the pristine `src/upstream/...`. Forge
  /// disambiguates the duplicate file name with the parent directory.
  string internal constant UPSTREAM_JSON = "out/pool/BlurPool.sol/BlurPool.json";

  /**
    Read an artifact, asserting it was compiled from `_source` so that a change
    in Forge's output layout fails loudly instead of comparing the wrong files.

    @param _path The artifact path.
    @param _source The expected source path.

    @return _json The artifact.
  */
  function _artifact (
    string memory _path,
    string memory _source
  ) internal view returns (string memory _json) {
    _json = vm.readFile(_path);
    string[] memory _targets =
      vm.parseJsonKeys(_json, ".metadata.settings.compilationTarget");
    assertEq(_targets.length, 1);
    assertEq(_targets[0], _source);
  }

  /**
    Constructing the pristine upstream source with the live constructor
    arguments at the live implementation's address reproduces its runtime code
    exactly, immutables included. Running the constructor in place is what
    makes OpenZeppelin's `__self` immutable comparable.
  */
  function test_upstreamCompilesToLiveImplementation () public {
    bytes memory _live = Deployment.CURRENT_IMPLEMENTATION.code;
    assertEq(_live.length, 7001);
    deployCodeTo(
      Deployment.UPSTREAM_ARTIFACT,
      Deployment.constructorArgs(),
      Deployment.CURRENT_IMPLEMENTATION
    );
    assertEq(Deployment.CURRENT_IMPLEMENTATION.code, _live);
  }

  /// The live proxy points at that same implementation.
  function test_proxyUsesLiveImplementation () public view {
    assertEq(_liveImplementation(), Deployment.CURRENT_IMPLEMENTATION);
  }

  /// The patched contract's storage layout is identical to upstream.
  function test_storageLayoutUnchanged () public view {
    string memory _patched =
      _artifact(PATCHED_JSON, "src/pool/BlurPool.sol");
    string memory _upstream =
      _artifact(UPSTREAM_JSON, "src/upstream/pool/BlurPool.sol");
    uint256 _count = 0;
    while (true) {
      string memory _entry = string.concat(
        ".storageLayout.storage[",
        vm.toString(_count),
        "]"
      );
      bool _exists = vm.keyExistsJson(_upstream, _entry);
      assertEq(vm.keyExistsJson(_patched, _entry), _exists);
      if (!_exists) {
        break;
      }
      string[3] memory _fields = [".label", ".slot", ".type"];
      for (uint256 i = 0; i < _fields.length; i++) {
        string memory _key = string.concat(_entry, _fields[i]);
        assertEq(
          vm.parseJsonString(_patched, _key),
          vm.parseJsonString(_upstream, _key)
        );
      }
      string memory _offset = string.concat(_entry, ".offset");
      assertEq(
        vm.parseJsonUint(_patched, _offset),
        vm.parseJsonUint(_upstream, _offset)
      );
      _count++;
    }

    // Initializable, Context, Ownable, ERC1967Upgrade, UUPS, then balances.
    assertEq(_count, 8);
  }

  /// The patch adds `transfer` to the external interface and nothing else.
  function test_interfaceOnlyAddsTransfer () public view {
    string memory _patched =
      _artifact(PATCHED_JSON, "src/pool/BlurPool.sol");
    string memory _upstream =
      _artifact(UPSTREAM_JSON, "src/upstream/pool/BlurPool.sol");
    string[] memory _upstreamMethods =
      vm.parseJsonKeys(_upstream, ".methodIdentifiers");
    string[] memory _patchedMethods =
      vm.parseJsonKeys(_patched, ".methodIdentifiers");
    assertEq(_patchedMethods.length, _upstreamMethods.length + 1);
    for (uint256 i = 0; i < _upstreamMethods.length; i++) {
      assertTrue(
        vm.keyExistsJson(
          _patched,
          string.concat(".methodIdentifiers['", _upstreamMethods[i], "']")
        ),
        _upstreamMethods[i]
      );
    }
    string memory _transfer = ".methodIdentifiers['transfer(address,uint256)']";
    assertFalse(vm.keyExistsJson(_upstream, _transfer));
    assertEq(vm.parseJsonString(_patched, _transfer), "a9059cbb");
  }
}
