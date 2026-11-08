# Project AEON Blur Pool Rescue

The [Blur Pool](https://etherscan.io/address/0x0000000000A39bb272e79075ade125fd351887Ac) is the wrapped Ether that Blur's marketplace pays royalties in. It is upgradeable but not ERC-20 compatible: it has no `transfer` function, so the only way out of it is calling `withdraw` from the holding address. Royalty receivers that are themselves contracts (splitters, conduits, and the like) can only move ERC-20 balances with `transfer`, so the Ether paid to them is stuck.

This proposal keeps standard `transfer` support for receivers that can call it and adds a recovery for a legacy Project AEON MoneyPipe that cannot. The fork tests cover both recovery paths. [Upstream proposal by TimTinkers](https://github.com/TimTinkers/blur_rescue)

## Proposed payout

On a mainnet fork, Blur's 3-of-5 Safe executed the upgrade and paid the Project AEON deployer 2.43877 ETH directly from MoneyPipe's Blur Pool credit. The payout bypasses MoneyPipe's usual split of two thirds to the Project AEON treasury and one third to the artist. Blur should confirm that the parties entitled to those payouts authorize the proposed destination before approving recovery. [MoneyPipe code](https://etherscan.io/address/0xf29A49bCf6135EcfBB3E3DEaCD6052FbE6b596C0#code) · [AEON deployer](https://etherscan.io/address/0x457D955eF9b1E942AE3D7185E69a3EcfBcDD625D) · [Blur Pool Safe](https://etherscan.io/address/0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb)

## Deployment status

The original implementation that adds `transfer` alone was deployed at [`0x5b52e91f718904B82b85F061A22615D686c5dC23`](https://etherscan.io/address/0x5b52e91f718904B82b85F061A22615D686c5dC23#code). The revised implementation's predicted CreateX address is `0xc74ACcF8939b29530CC54499661E5D57729243F1`. At block [26,365,445](https://etherscan.io/block/26365445) the address had no deployed code and the MoneyPipe held 2.43877 ETH of Blur Pool credit. See the [deployment and Safe handoff](./DEPLOYMENT.md) for the two staged transactions.

## The change

`make diff` prints the contract changes against Blur's verified source.

```solidity
function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);

    return true;
}
```

It reuses the contract's existing private `_transfer`, which already rejects the zero address and insufficient balances and emits `Transfer`. `transferFrom` is untouched: it remains callable only by Blur's four contracts, with no allowances. Storage layout, constructor arguments, ownership, and upgradeability are unchanged.

`recoverMoneyPipe(uint256 expectedAmount)` is restricted to the pool owner. It checks that the reviewed amount in wei equals the full nonzero Blur Pool balance of [the legacy MoneyPipe](https://etherscan.io/address/0xf29a49bcf6135ecfbb3e3deacd6052fbe6b596c0), clears that balance, and pays the same amount in native ETH to [the Project AEON deployer](https://etherscan.io/address/0x457D955eF9b1E942AE3D7185E69a3EcfBcDD625D). Both addresses are fixed in the code. If the ETH payment fails, the balance debit reverts. The payout bypasses MoneyPipe's original 2/3 treasury and 1/3 artist split. Any WETH held by MoneyPipe is outside the Blur Pool and cannot be moved by this patch.

## What Blur needs to do

1. **Review the destination and verify the deployed implementation.** A funded Ethereum wallet can deploy the reviewed implementation through CreateX. Blur should verify the code against the pinned build and confirm authorization for paying the deployer directly.
2. **Verify the current MoneyPipe balance in wei** using `balanceOf(address)` on the pool proxy. At fork block 26357000 the balance was `2438770000000000000` wei (2.43877 ETH). Use the reviewed current amount.
3. **Execute the upgrade and payout in one call** from the owner Safe [`0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb`](https://etherscan.io/address/0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb) (3-of-5). The target is the proxy `0x0000000000A39bb272e79075ade125fd351887Ac`, with value `0`. Encode the data below. The proxy upgrades to the reviewed implementation and then executes recovery as the Safe; a failed payout reverts the upgrade as well.

```sh
# Example calldata for the fork balance; replace AMOUNT_WEI with the reviewed live amount.
AMOUNT_WEI=2438770000000000000
RECOVERY_DATA=$(cast calldata 'recoverMoneyPipe(uint256)' "$AMOUNT_WEI")
cast calldata 'upgradeToAndCall(address,bytes)' \
  0xc74ACcF8939b29530CC54499661E5D57729243F1 "$RECOVERY_DATA"
```

`make propose` still prints a plain upgrade without a payout. Use `upgradeToAndCall` above to execute both together.

## Deploying the implementation

The revised address and init code hash are pinned in [`contracts/script/Deployment.sol`](./contracts/script/Deployment.sol). The deploy script checks the build against both pins. The [deployment handoff](./DEPLOYMENT.md) includes a staged unsigned transaction for signing with a hardware wallet or encrypted keystore.

1. Copy `.env.example` to `.env`. Set `MAINNET_RPC_URL` to your own RPC, `PRIVATE_KEY` (or `MNEMONIC`) for a funded deployer, and `ETHERSCAN_API_KEY`.
2. Run `make test`, then `make deploy-check`. The dry run simulates the deployment against live mainnet without broadcasting and prints the address, init code hash, and estimated cost.
3. Run `make deploy`. It deploys through CreateX, then verifies the source on Etherscan with Blur's exact compiler settings. If Etherscan has not indexed the contract yet, rerun `make verify`.

The real deployment's broadcast record is written to `contracts/broadcast/`; fork simulations write to `contracts/broadcast-fork/` instead. Both are ignored by git.

## Stuck receivers

These seven receivers are among the 50 largest Blur Pool holders. Each one's only exit for an ERC-20 is `transfer`. Balances are at the pinned fork block, 26357000.

| Holder | Receiver | Stuck (ETH) | Exit after the upgrade |
| --- | --- | ---: | --- |
| [`0x7346…076F`](https://etherscan.io/address/0x73464dfeAc74096a05604234b471412c73D5076F) | PROOF `PaymentConduit`, Moonbirds | 133.53 | `forwardERC20` to the PROOF Safe |
| [`0xB626…E0C4`](https://etherscan.io/address/0xB62638857FEBb2900BA5b3E5d296201f4E12E0C4) | PROOF `PaymentConduit`, Oddities | 33.46 | `forwardERC20` to the PROOF Safe |
| [`0xBE36…494F`](https://etherscan.io/address/0xBE36007bFbefE69F5e2F9B1438FC2A15AE99494F) | 0xSplits v1 split wallet | 44.08 | `SplitMain.distributeERC20` and `withdraw` |
| [`0x8fE6…448D`](https://etherscan.io/address/0x8fE67eBcF516EfB408E537BD390dfde4Fae7448D) | `RoyaltiesSplitter` (`UpdatableSplitter`) | 26.45 | `flushToken` by its `FLUSHWORTHY` deployer |
| [`0x4C78…Ba73`](https://etherscan.io/address/0x4C78656fAea93b5305c69064B5C40Fae62C9Ba73) | `RoyaltiesSplitter` (`UpdatableSplitter`) | 21.19 | `flushToken` by its `FLUSHWORTHY` deployer |
| [`0x9906…E45D`](https://etherscan.io/address/0x9906De9E0D9ef5960d02dF2261Ecaa78EC8CE45D) | OpenZeppelin `PaymentSplitter` | 16.01 | `release` to each payee |
| [`0x7578…1241`](https://etherscan.io/address/0x7578425460C842CA077544FFe224Cf213c931241) | `AssetVault` "One" | 85.01 | `send` by its timelock owner |
| | | **359.72** | |

The simulation frees all of it except 1 wei of rounding dust that 0xSplits keeps by design. The recipients (externally-owned accounts and Safes) can then `withdraw` to Ether themselves. These seven are examples only: the pool has over 125,000 holders.

### The asset vault

The `AssetVault` is unverified. Its selectors match version 2 of `AssetVault.sol` exactly, and its owner can move an ERC-20 out only with `send`, which calls `SafeERC20.safeTransfer`. Its governance is layered:

- The vault is owned by a Compound-style `Timelock` (`0xc9D5…13aB`) with a three-day delay.
- The timelock's admin is a 2-of-3 Safe (`0x43E2…89AA`).
- The Safe has a `ScopeGuard` that lets it call the timelock but not Blur Pool or the vault directly.

The guard means a rescued balance sent to the Safe would be stuck again. So the rescue keeps everything inside the vault's own governance and changes no guard, owner, or role:

1. The Safe queues two timelock calls with the same ETA:
   - `vault.send`, an ERC-20 send of the Blur Pool balance to the timelock.
   - `BlurPool.withdraw` of that balance from the timelock.
2. After the delay, the Safe executes both calls in order.

The 85.01 ETH ends as plain Ether in the same timelock. The test queues the rescue before the upgrade, shows that the very same queued `send` cannot execute (it reverts inside `SafeERC20` at Blur Pool's missing `transfer`), then executes it successfully after the upgrade.

## What the tests prove

`make test` runs against mainnet forked at block 26357000.

- **Fidelity.** The pristine upstream source in `contracts/src/upstream`, built with Blur's verified settings (solc 0.8.17, 20,000 optimizer runs, London, no metadata hash) and OpenZeppelin Contracts Upgradeable 4.8.3, reproduces the live implementation's runtime code byte for byte, immutables included. The patched contract has an identical storage layout and adds only `transfer` and `recoverMoneyPipe` to the external interface.
- **Upgrade.** The implementation lands at its precomputed address, cannot be initialized, and is a valid UUPS target. The real Safe approves and executes the upgrade at its live nonce, with a threshold of real owners. The upgrade writes exactly one storage slot of the proxy, the ERC-1967 implementation slot. Balances, supply, metadata, and ownership are unchanged, only the Safe can upgrade, and the Safe can still roll back.
- **Behavior.** `transfer` works as a standard ERC-20 transfer, including fuzzed amounts and the existing zero-address and balance checks. `deposit`, `deposit(user)`, `withdraw`, `withdrawFrom`, and `transferFrom` keep their exact behavior and authorization.
- **Rescue.** Each stuck receiver fails today, inside its own `transfer` call, and succeeds after the upgrade. Every recipient can then unwrap its share to Ether. The asset vault is rescued through its real Safe, guard, and timelock, with the delay enforced.
- **Project AEON.** The Blur Safe executes `upgradeToAndCall` on the fork, paying the deployer exactly 2.43877 ETH and clearing the MoneyPipe's pool balance. Tests cover unauthorized calls, amount mismatch, repeat withdrawal, and reversal if the deployer rejects payment. The existing splitter recipients and MoneyPipe's WETH balance are unchanged by recovery.

The upgrade runs through the same `DeployBlurPool` and `UpgradeBlurPool` script code in tests and in simulation, and the vault rescue through `RescueAssetVault`. The Safe's own threshold and signature verification is never bypassed: a threshold of the real owners (impersonated on the fork) approve the exact transaction hash on-chain with `approveHash`, which is the Safe's approved-hash signature type, and then the Safe's `execTransaction` verifies those approvals at its live nonce. No private keys are needed.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation), which provides `forge`, `cast`, and `anvil` and installs dependencies with Soldeer.
- An archive-capable mainnet RPC. The default, `https://rpc.flashbots.net`, works; set `MAINNET_RPC_URL` in `.env` to use your own.

## Quick Start

```sh
make install   # Install Soldeer dependencies.
make test      # Prove the upgrade against the pinned mainnet fork.
make simulate  # Fork with anvil and run deploy, upgrade, and rescue as real transactions.
make diff      # Show the patch.
make propose   # Print the Safe transaction against live mainnet.
```

`make simulate` starts anvil in the background on port 18545, broadcasts every step as a real transaction from the actual mainnet actors (impersonated), prints the implementation and stuck balances before and after, then stops anvil. To go step by step, run `make fork` in one terminal and then `make deploy-fork`, `make upgrade-fork`, `make rescue-fork`, `make rescue-vault-fork`, and `make stuck-balances` in another. `make rescue-vault-fork` jumps the fork's clock past the timelock delay between queueing and execution. You can see all commands with `make help`.

## Layout

- [`contracts/src/upstream/pool`](./contracts/src/upstream/pool): Blur's verified `BlurPool.sol` and `IBlurPool.sol`, verbatim.
- [`contracts/src/pool`](./contracts/src/pool): the patched copies; the only Blur code that changes.
- [`contracts/src/interfaces`](./contracts/src/interfaces): interfaces for the proxy, the Safe, CreateX, and the stuck receivers.
- [`contracts/script`](./contracts/script): the deployment constants, the CreateX deployment, the Safe upgrade, and the rescue.
- [`contracts/test`](./contracts/test): the fork tests.

# License

The Blur contracts in `contracts/src/pool` and `contracts/src/upstream` are Blur's code and keep their original MIT license, so that Blur can adopt the patch as-is.

The [license](./LICENSE) for all of our original work is `LicenseRef-VPL WITH AGPL-3.0-only`. This includes the scripts, tests, interfaces, Makefile, and documentation. You are licensed to use all of it so long as you maintain _maximum possible virality_ and our copyleft licenses. See the [Viral Public License](./licenses/LicenseRef-VPL) and the [GNU Affero General Public License v3.0](./licenses/AGPL-3.0-only).
