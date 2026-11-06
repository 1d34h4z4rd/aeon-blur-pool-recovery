// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { Deployment } from "../script/Deployment.sol";
import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { ISafe } from "../src/interfaces/ISafe.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

/**
  @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVM MEVM
  @title Upgrade Test
  @author Tim Clancy <tim-clancy.gwei>
  @custom:terry "Is this too much voodoo for the next ten centuries?"

  The deterministic CreateX deployment and the Safe-executed upgrade leave the
  pool's state, ownership, and future upgradeability exactly as they were.

  @custom:date November 6th, 2026.
*/
contract UpgradeTest is
  BlurPoolForkTest {

  /// The Blur Pool owner Safe.
  ISafe internal constant SAFE = ISafe(Deployment.BLUR_POOL_OWNER);

  /**
    A sample of real holders, including large externally-owned accounts,
    Safes, and the stuck royalty receivers, whose balances must survive.

    @return _holders The holders.
  */
  function _sampleHolders () internal pure returns (
    address[8] memory _holders
  ) {
    _holders = [
      0xe65B6865DBCe299Ae6a20efcc7543362540741d8,
      0x40443dDFcaaaDB9de1B8B96cC21304AD8c1c4b14,
      0xbeb5825772B52811C23a1389A391934AE71808aC,
      0x73464dfeAc74096a05604234b471412c73D5076F,
      0xBE36007bFbefE69F5e2F9B1438FC2A15AE99494F,
      0x8fE67eBcF516EfB408E537BD390dfde4Fae7448D,
      0x9906De9E0D9ef5960d02dF2261Ecaa78EC8CE45D,
      Deployment.BLEND
    ];
  }

  /**
    The implementation lands at the address precomputed from its init code and
    is a valid UUPS upgrade target.
  */
  function test_deploymentIsDeterministic () public {
    address _expected = Deployment.implementation();
    assertEq(_expected, Deployment.EXPECTED_IMPLEMENTATION);
    assertEq(
      keccak256(Deployment.initCode()),
      Deployment.EXPECTED_INIT_CODE_HASH
    );

    // True at the pinned fork block; a `FORK_BLOCK` after the real mainnet
    // deployment will (correctly) fail here.
    assertEq(_expected.code.length, 0);
    address _implementation = deployer.deploy();
    assertEq(_implementation, _expected);
    assertEq(
      IBlurPoolProxy(_implementation).proxiableUUID(),
      Deployment.IMPLEMENTATION_SLOT
    );

    // Rerunning the deployment is a no-op.
    assertEq(deployer.deploy(), _implementation);
  }

  /// The bare implementation can never be initialized and so never owned.
  function test_implementationIsLocked () public {
    address _implementation = deployer.deploy();
    vm.expectRevert("Initializable: contract is already initialized");
    IBlurPoolProxy(_implementation).initialize();
    assertEq(IBlurPoolProxy(_implementation).owner(), address(0));
  }

  /**
    The Safe approves and executes the upgrade at its live nonce and threshold,
    and the proxy then points at the new implementation.
  */
  function test_upgradeThroughSafe () public {
    assertEq(_liveImplementation(), Deployment.CURRENT_IMPLEMENTATION);
    assertEq(POOL.owner(), address(SAFE));
    uint256 _nonce = SAFE.nonce();
    address _implementation = deployer.deploy();
    bytes32 _safeTxHash = upgrader.safeTransactionHash(_implementation);
    upgrader.upgrade(_implementation);
    assertEq(_liveImplementation(), _implementation);
    assertEq(SAFE.nonce(), _nonce + 1);
    assertEq(POOL.owner(), address(SAFE));

    // A threshold of real owners approved the exact hash that was executed.
    address[] memory _owners = SAFE.getOwners();
    uint256 _approvals = 0;
    for (uint256 i = 0; i < _owners.length; i++) {
      _approvals += SAFE.approvedHashes(_owners[i], _safeTxHash);
    }
    assertEq(_approvals, SAFE.getThreshold());
  }

  /**
    The upgrade writes exactly one storage slot of the proxy: the ERC-1967
    implementation slot. Every balance, the owner, and the initializer state
    are therefore untouched.
  */
  function test_upgradeWritesOnlyImplementationSlot () public {
    address _implementation = deployer.deploy();
    vm.record();
    upgrader.upgrade(_implementation);
    (, bytes32[] memory _writes) = vm.accesses(Deployment.BLUR_POOL);
    assertEq(_writes.length, 1);
    assertEq(_writes[0], Deployment.IMPLEMENTATION_SLOT);
  }

  /// Real balances, supply, metadata, and ownership read identically after.
  function test_stateSurvivesUpgrade () public {
    address[8] memory _holders = _sampleHolders();
    uint256[8] memory _balances;
    for (uint256 i = 0; i < _holders.length; i++) {
      _balances[i] = POOL.balanceOf(_holders[i]);
    }
    uint256 _supply = POOL.totalSupply();
    assertGt(_supply, 0);
    _upgrade();
    for (uint256 i = 0; i < _holders.length; i++) {
      assertEq(POOL.balanceOf(_holders[i]), _balances[i]);
    }
    assertEq(POOL.totalSupply(), _supply);
    assertEq(POOL.totalSupply(), address(POOL).balance);
    assertEq(POOL.name(), "Blur Pool");
    assertEq(POOL.decimals(), 18);
    assertEq(POOL.owner(), address(SAFE));
  }

  /// The proxy cannot be reinitialized after the upgrade.
  function test_cannotReinitialize () public {
    _upgrade();
    vm.expectRevert("Initializable: contract is already initialized");
    POOL.initialize();
  }

  /// Only the Safe can upgrade, before and after.
  function test_upgradeRequiresOwner () public {
    address _implementation = deployer.deploy();
    vm.expectRevert("Ownable: caller is not the owner");
    POOL.upgradeTo(_implementation);
    _upgrade();
    vm.expectRevert("Ownable: caller is not the owner");
    POOL.upgradeTo(Deployment.CURRENT_IMPLEMENTATION);
  }

  /**
    The new implementation keeps the pool upgradeable: the Safe can roll back
    to the original implementation if it ever needs to.
  */
  function test_upgradeIsReversible () public {
    _upgrade();
    upgrader.upgrade(Deployment.CURRENT_IMPLEMENTATION);
    assertEq(_liveImplementation(), Deployment.CURRENT_IMPLEMENTATION);
  }
}

