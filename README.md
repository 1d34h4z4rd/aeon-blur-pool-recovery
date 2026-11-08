# Project AEON Blur Pool Rescue

Project AEON's legacy MoneyPipe holds Blur Pool credit, but it has no function that can call Blur Pool to move or withdraw that balance. This patch extends TimTinkers' proposal with a recovery function for that MoneyPipe. [MoneyPipe contract](https://etherscan.io/address/0xf29a49bcf6135ecfbb3e3deacd6052fbe6b596c0#code) · [Upstream proposal](https://github.com/TimTinkers/blur_rescue)

## Proposed payout

The patch pays MoneyPipe's full Blur Pool balance to the Project AEON deployer, bypassing the original treasury and artist split. The artist and the developer are aligned on this solution. The deployer wallet would receive the recovered ETH first so Project AEON can transfer it to a new multisig in a separate transaction. [Project AEON deployer](https://etherscan.io/address/0x457D955eF9b1E942AE3D7185E69a3EcfBcDD625D)

Blur's 3-of-5 Safe can upgrade the pool and recover the balance in one transaction. The call checks that the balance matches the reviewed amount, and a failed payout reverts the upgrade. [Blur Pool Safe](https://etherscan.io/address/0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb) · [Deployment and Safe handoff](./DEPLOYMENT.md)

## Fork test

At Ethereum block 26,357,000, the fork test executed the upgrade through Blur's Safe, paid **2.43877 ETH** to the deployer and cleared MoneyPipe's Blur Pool balance. To reproduce it, use Foundry and an archive-capable mainnet RPC.

```sh
make install
make test ARGS='--match-contract MoneyPipeRescueTest'
```

[Recovery test](./contracts/test/MoneyPipeRescue.t.sol) · [Foundry installation](https://getfoundry.sh/introduction/installation/)

The Blur contract sources retain their MIT license. The scripts, tests and documentation retain the upstream licensing terms. [License](./LICENSE)
