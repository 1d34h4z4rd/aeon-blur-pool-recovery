# Blur Pool ERC-20 Upgrade

> Let my people go.

The [Blur Pool](https://etherscan.io/address/0x0000000000A39bb272e79075ade125fd351887Ac) is the wrapped Ether that Blur's marketplace pays royalties in. It is upgradeable but not ERC-20 compatible: it has no `transfer` function, so the only way out of it is calling `withdraw` from the holding address. Royalty receivers that are themselves contracts (splitters, conduits, and the like) can only move ERC-20 balances with `transfer`, so the Ether paid to them is stuck.

This repository demonstrates that the fix is small and safe. It starts from Blur's exact verified contract, adds a standard `transfer`, and simulates the complete upgrade against forked mainnet: the CreateX deployment, Blur's Safe approving and executing the upgrade, and real stuck receivers distributing their balances through their own unmodified code.

## The change

`make diff` prints the entire patch against Blur's verified source: one function, one interface line, and one updated doc comment.

```solidity
function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);

    return true;
}
```

It reuses the contract's existing private `_transfer`, which already rejects the zero address and insufficient balances and emits `Transfer`. `transferFrom` is untouched: it remains callable only by Blur's four contracts, with no allowances. Storage layout, constructor arguments, ownership, and upgradeability are unchanged.

## What Blur needs to do

1. **Deploy the implementation.** Anyone can do this, permissionlessly, with `make deploy` (see [Deploying the implementation](#deploying-the-implementation)). CreateX places it at `0x5b52e91f718904B82b85F061A22615D686c5dC23` via `CREATE2`, so the address commits to the exact init code (hash `0x28c7955ddb9cf8d002a00be93e72692d30175d045ce423c1840ba4077dcd857f`): whoever deploys it, that address can only ever hold the reviewed code.
2. **Execute one Safe transaction** from the owner Safe [`0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb`](https://etherscan.io/address/0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb) (3-of-5):
   - **To:** `0x0000000000A39bb272e79075ade125fd351887Ac`
   - **Value:** `0`
   - **Data:** `0x3659cfe60000000000000000000000005b52e91f718904b82b85f061a22615d686c5dc23` (`upgradeTo(0x5b52…dC23)`)

   `make propose` prints this transaction and its Safe transaction hash at the Safe's live nonce for signers to check against their wallets.

## Deploying the implementation

The address and init code hash are pinned in [`contracts/script/Deployment.sol`](./contracts/script/Deployment.sol). The deploy script refuses to run if the build differs, so it can only ever deploy the reviewed code to the address shared above.

1. Copy `.env.example` to `.env`. Set `MAINNET_RPC_URL` to your own RPC, `PRIVATE_KEY` (or `MNEMONIC`) for a funded deployer, and `ETHERSCAN_API_KEY`.
2. Run `make test`, then `make deploy-check`. The dry run simulates the deployment against live mainnet without broadcasting, and prints the address, the init code hash, and the estimated cost (about 2.24 million gas).
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

- **Fidelity.** The pristine upstream source in `contracts/src/upstream`, built with Blur's verified settings (solc 0.8.17, 20,000 optimizer runs, London, no metadata hash) and OpenZeppelin Contracts Upgradeable 4.8.3, reproduces the live implementation's runtime code byte for byte, immutables included. The patched contract has an identical storage layout, and its external interface differs only by `transfer`.
- **Upgrade.** The implementation lands at its precomputed address, cannot be initialized, and is a valid UUPS target. The real Safe approves and executes the upgrade at its live nonce, with a threshold of real owners. The upgrade writes exactly one storage slot of the proxy, the ERC-1967 implementation slot. Balances, supply, metadata, and ownership are unchanged, only the Safe can upgrade, and the Safe can still roll back.
- **Behavior.** `transfer` works as a standard ERC-20 transfer, including fuzzed amounts and the existing zero-address and balance checks. `deposit`, `deposit(user)`, `withdraw`, `withdrawFrom`, and `transferFrom` keep their exact behavior and authorization.
- **Rescue.** Each stuck receiver fails today, inside its own `transfer` call, and succeeds after the upgrade. Every recipient can then unwrap its share to Ether. The asset vault is rescued through its real Safe, guard, and timelock, with the delay enforced.

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
