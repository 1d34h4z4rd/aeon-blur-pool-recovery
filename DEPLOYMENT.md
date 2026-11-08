# Deployment and Safe handoff

The first transaction deploys the reviewed implementation through CreateX. The second transaction is a separate decision for Blur's 3-of-5 Safe and performs the upgrade and recovery together. Both payloads are unsigned.

## 1. Deploy the implementation

- Network is Ethereum mainnet (chain ID 1).
- The transaction calls `deployCreate2(bytes32,bytes)` on CreateX at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` with zero ETH value. The wallet pays gas. [CreateX on Etherscan](https://etherscan.io/address/0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed#code)
- Expected implementation address is `0xc74ACcF8939b29530CC54499661E5D57729243F1`.
- Init code hash is `0x35a5742b5e2489a0bfd0ac6e33fb91b872aeb0b3e37319f49c25c6b1343dc1fe`.
- Deployment calldata hash is `0xebb81687e28c4e0b1dc64d509e64b6413ce53e9a689c168873164910ab6a58bd`. [Unsigned deployment transaction](./transactions/createx-deploy.json)

Reproduce the deployment from source with `make install`, `make test`, and `make deploy-check PRIVATE_KEY= MNEMONIC=`. The dry run uses Foundry's public development account for simulation. Its generated transaction input is at `contracts/broadcast/DeployBlurPool.s.sol/1/dry-run/run-latest.json` under `.transactions[0].transaction.input`. Compare that input with `.data` in the staged transaction.

Before broadcast, set `MAINNET_RPC_URL` to a mainnet RPC and `DEPLOYER_ADDRESS` to the selected wallet's public address. Run these read-only checks from the repo root. Use a nonzero sender so CreateX applies the same salt rules it will use at execution.

```sh
CREATE_X=$(jq -er '.to' transactions/createx-deploy.json)
DEPLOY_DATA=$(jq -er '.data' transactions/createx-deploy.json)
IMPLEMENTATION=0xc74ACcF8939b29530CC54499661E5D57729243F1

cast chain-id --rpc-url "$MAINNET_RPC_URL"
cast code "$IMPLEMENTATION" --rpc-url "$MAINNET_RPC_URL"
cast keccak "$DEPLOY_DATA"
cast call "$CREATE_X" --from "$DEPLOYER_ADDRESS" --data "$DEPLOY_DATA" \
  --rpc-url "$MAINNET_RPC_URL"
cast estimate "$CREATE_X" "$DEPLOY_DATA" --from "$DEPLOYER_ADDRESS" \
  --rpc-url "$MAINNET_RPC_URL"
```

Expect chain ID `1`, empty implementation code (`0x`), the calldata hash above, and a simulated return value that decodes to the expected address. If code is already present, verify it against the pinned build before proceeding. At block 26,365,445 the raw transaction estimated 1,781,712 gas. Recheck fees with the selected wallet before signing.

After approval, sign the deployment with a funded wallet. The command below uses an encrypted Foundry keystore selected by `FOUNDRY_ACCOUNT`. The proposed cap of 2,500,000 gas at 0.10 gwei gives a maximum fee of 0.00025 ETH. Review this cap against current fees. A hardware wallet can use the same transaction fields. [Foundry cast send](https://getfoundry.sh/cast/reference/send/)

```sh
cast send "$CREATE_X" --data "$DEPLOY_DATA" --value 0 --chain 1 \
  --from "$DEPLOYER_ADDRESS" --account "$FOUNDRY_ACCOUNT" \
  --gas-limit 2500000 --gas-price 100000000 --priority-gas-price 1000000 \
  --rpc-url "$MAINNET_RPC_URL"
```

Record the deployment transaction hash and confirm its receipt succeeded and the expected address has code. Run `make verify` with an Etherscan API key configured locally to publish and verify the source. If indexing delays verification, retry `make verify` using the existing deployment.

## 2. Hand off to Blur

Give Blur the repo commit, verified implementation address and deployment transaction hash. Ask its signers to confirm authorization for the direct payout because it bypasses the legacy treasury and artist split.

The review payload calls `upgradeToAndCall` on the Blur Pool proxy with a zero-value CALL. It contains `recoverMoneyPipe(2438770000000000000)`, the reviewed 2.43877 ETH at block 26,365,445. Blur should recheck the current balance before collecting signatures. If the balance differs, generate new calldata using the README. Use the fields in the review payload to assemble the proposal in Blur's Safe. [Unsigned Safe review payload](./transactions/blur-safe-review.json) · [Blur Pool Safe](https://etherscan.io/address/0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb)

After the Safe executes, verify that the proxy points to the reviewed implementation, the MoneyPipe's Blur Pool credit is zero, and the transaction trace shows the expected ETH payment to the deployer. [Blur Pool](https://etherscan.io/address/0x0000000000A39bb272e79075ade125fd351887Ac) · [AEON deployer](https://etherscan.io/address/0x457D955eF9b1E942AE3D7185E69a3EcfBcDD625D)
