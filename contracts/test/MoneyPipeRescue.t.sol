// SPDX-License-Identifier: LicenseRef-(SEPPUKU WITH VPL) WITH AGPL-3.0-only
pragma solidity 0.8.36;

import { Deployment } from "../script/Deployment.sol";
import { SafeTransactions } from "../script/SafeTransactions.sol";
import { IBlurPoolProxy } from "../src/interfaces/IBlurPoolProxy.sol";
import { ISafe } from "../src/interfaces/ISafe.sol";
import { IBlurPool } from "../src/pool/interfaces/IBlurPool.sol";
import { BlurPoolForkTest } from "./BlurPoolFork.t.sol";

interface IWethBalance {
  function balanceOf (address holder) external view returns (uint256);
}

contract RejectAeonPayout {
  receive () external payable { revert("reject ETH"); }
}

contract SafeRecoveryHarness is SafeTransactions {
  function upgradeAndRecover (address implementation, uint256 expectedAmount) external {
    _executeThroughSafe(
      ISafe(Deployment.BLUR_POOL_OWNER),
      Deployment.BLUR_POOL,
      abi.encodeCall(IBlurPoolProxy.upgradeToAndCall, (
        implementation, abi.encodeCall(IBlurPool.recoverMoneyPipe, (expectedAmount))
      ))
    );
  }
}

contract MoneyPipeRescueTest is BlurPoolForkTest {
  address internal constant MONEYPIPE = 0xf29A49bCf6135EcfBB3E3DEaCD6052FbE6b596C0;
  address internal constant AEON_DEPLOYER = 0x457D955eF9b1E942AE3D7185E69a3EcfBcDD625D;
  address internal constant TREASURY = 0x99c1Ee4a9f034277e88F9ac92E001E79D2dc0C79;
  address internal constant ARTIST = 0x203DDa129Ff7d54c3392758368F19E19B4Eaa367;
  IWethBalance internal constant WETH = IWethBalance(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  event Transfer (address indexed from, address indexed to, uint256 amount);

  function test_safePaysFullBalanceToAeonDeployer () public {
    address implementation = deployer.deploy();
    SafeRecoveryHarness recovery = new SafeRecoveryHarness();
    uint256 amount = POOL.balanceOf(MONEYPIPE);
    if (block.number == DEFAULT_FORK_BLOCK) {
      assertEq(amount, 2.43877 ether);
    }
    assertGt(amount, 0);
    uint256 deployerBefore = AEON_DEPLOYER.balance;
    uint256 treasuryBefore = TREASURY.balance;
    uint256 artistBefore = ARTIST.balance;
    uint256 pipeEtherBefore = MONEYPIPE.balance;
    uint256 wethBefore = WETH.balanceOf(MONEYPIPE);
    uint256 supplyBefore = POOL.totalSupply();

    vm.expectEmit(address(POOL));
    emit Transfer(MONEYPIPE, address(0), amount);
    recovery.upgradeAndRecover(implementation, amount);

    assertEq(_liveImplementation(), implementation);
    assertEq(POOL.balanceOf(MONEYPIPE), 0);
    assertEq(POOL.totalSupply(), supplyBefore - amount);
    assertEq(AEON_DEPLOYER.balance, deployerBefore + amount);
    assertEq(TREASURY.balance, treasuryBefore);
    assertEq(ARTIST.balance, artistBefore);
    assertEq(MONEYPIPE.balance, pipeEtherBefore);
    assertEq(WETH.balanceOf(MONEYPIPE), wethBefore);

    vm.prank(Deployment.BLUR_POOL_OWNER);
    vm.expectRevert("No MoneyPipe balance");
    POOL.recoverMoneyPipe(amount);
  }

  function test_aeonDeployerCannotAuthorizeRecovery () public {
    _upgrade();
    uint256 amount = POOL.balanceOf(MONEYPIPE);
    vm.prank(AEON_DEPLOYER);
    vm.expectRevert("Ownable: caller is not the owner");
    POOL.recoverMoneyPipe(amount);
    assertEq(POOL.balanceOf(MONEYPIPE), amount);
  }

  function test_ownerCannotRecoverIfBalanceChanged () public {
    _upgrade();
    uint256 amount = POOL.balanceOf(MONEYPIPE);
    uint256 deployerBefore = AEON_DEPLOYER.balance;
    vm.prank(Deployment.BLUR_POOL_OWNER);
    vm.expectRevert("MoneyPipe balance changed");
    POOL.recoverMoneyPipe(amount + 1);
    assertEq(POOL.balanceOf(MONEYPIPE), amount);
    assertEq(AEON_DEPLOYER.balance, deployerBefore);
  }

  function test_rejectedPayoutRevertsUpgradeAndPreservesBalance () public {
    address previousImplementation = _liveImplementation();
    address implementation = deployer.deploy();
    uint256 amount = POOL.balanceOf(MONEYPIPE);
    uint256 supplyBefore = POOL.totalSupply();
    RejectAeonPayout reject = new RejectAeonPayout();
    vm.etch(AEON_DEPLOYER, address(reject).code);
    vm.prank(Deployment.BLUR_POOL_OWNER);
    vm.expectRevert("AEON payout failed");
    POOL.upgradeToAndCall(
      implementation,
      abi.encodeCall(IBlurPool.recoverMoneyPipe, (amount))
    );
    assertEq(_liveImplementation(), previousImplementation);
    assertEq(POOL.balanceOf(MONEYPIPE), amount);
    assertEq(POOL.totalSupply(), supplyBefore);
  }
}
