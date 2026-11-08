# Blur Pool ERC-20 `transfer` upgrade, simulated against forked mainnet.
#
# Configuration is loaded from `.env` and can be overridden by environment
# variables or on the command line (`make test FORK_BLOCK=...`).
#
# Usage:
#   make install   # Install Soldeer dependencies.
#   make test      # Prove the upgrade against a pinned mainnet fork.
#   make simulate  # Run the full deployment as real transactions on anvil.
#   make help      # Show all commands.

# Load configuration from `.env` if it exists.
-include .env

# An archive-capable mainnet RPC; the fork is pinned to a historical block.
# Defaults apply when a variable is unset or left empty in `.env`.
DEFAULT_MAINNET_RPC_URL = https://rpc.flashbots.net
ifeq ($(strip $(MAINNET_RPC_URL)),)
MAINNET_RPC_URL = $(DEFAULT_MAINNET_RPC_URL)
endif

# The pinned fork block. Keep in sync with `DEFAULT_FORK_BLOCK` in
# `contracts/test/BlurPoolFork.t.sol`.
DEFAULT_FORK_BLOCK = 26357000
ifeq ($(strip $(FORK_BLOCK)),)
FORK_BLOCK = $(DEFAULT_FORK_BLOCK)
endif

# The local anvil fork. The default port avoids sacristy's L1 on 8545.
ANVIL_PORT ?= 18545
ANVIL_RPC = http://127.0.0.1:$(ANVIL_PORT)

# `--auto-impersonate` lets the scripts broadcast as the Safe owners and
# splitter roles they simulate. The retry, backoff, and compute-unit throttle
# make a public RPC's rate limiting (HTTP 429) slow the fork down instead of
# failing a broadcast.
ANVIL_FLAGS = \
	--fork-url $(MAINNET_RPC_URL) \
	--fork-block-number $(FORK_BLOCK) \
	--auto-impersonate \
	--retries 10 \
	--fork-retry-backoff 1000 \
	--compute-units-per-second 100 \
	--port $(ANVIL_PORT)

# Anvil's first default development account, funded on the fork. It deploys
# the implementation and sends the permissionless rescue calls.
ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Mainnet actors impersonated on the fork.
BLUR_POOL = 0x0000000000A39bb272e79075ade125fd351887Ac
BLUR_POOL_OWNER = 0xFA9fB502534761dBDDAcf5B7e2Aa84684815F1bb
ROYALTIES_FLUSHER = 0xd7E5E1c0Cb9540669d8F22F71C9540460db23938
IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

# Royalty receivers holding Blur Pool balances they can only move with ERC-20
# `transfer` (see `contracts/script/StuckHolders.sol`).
STUCK_HOLDERS = \
	0x73464dfeAc74096a05604234b471412c73D5076F \
	0xB62638857FEBb2900BA5b3E5d296201f4E12E0C4 \
	0xBE36007bFbefE69F5e2F9B1438FC2A15AE99494F \
	0x8fE67eBcF516EfB408E537BD390dfde4Fae7448D \
	0x4C78656fAea93b5305c69064B5C40Fae62C9Ba73 \
	0x9906De9E0D9ef5960d02dF2261Ecaa78EC8CE45D \
	$(ASSET_VAULT)

# The `AssetVault`, its owning timelock, and the Safe administering the
# timelock (see `contracts/script/RescueAssetVault.s.sol`).
ASSET_VAULT = 0x7578425460C842CA077544FFe224Cf213c931241
ASSET_VAULT_TIMELOCK = 0xc9D59a09782cFD5a7E120EFBC73fB8F9725113aB
ASSET_VAULT_ADMIN = 0x43E2e78C8E6F2CE57FbD970C811E70e0044389AA

# Give every owner of the Safe $(1) gas money on the running fork. Their keys
# are never needed: anvil impersonates them and the Safe accepts on-chain
# approvals.
define fund_safe_owners
	@for OWNER in $$(cast call $(1) 'getOwners()(address[])' \
		--rpc-url $(ANVIL_RPC) | tr -d '[],'); do \
		cast rpc anvil_setBalance $$OWNER 0xde0b6b3a7640000 \
			--rpc-url $(ANVIL_RPC) > /dev/null; \
	done
endef

# The pinned implementation address and its original constructor arguments
# (see `contracts/script/Deployment.sol`, which enforces the pin).
IMPLEMENTATION = 0xc74ACcF8939b29530CC54499661E5D57729243F1
EXCHANGE = 0x000000000000Ad05Ccc4F10045630fb830B95127
EXCHANGE_V2 = 0xb2ecfE4E4D61f8790bbb9DE2D1259B9e2410CEA5
SWAP = 0x39da41747a83aeE658334415666f3EF92DD0D541
BLEND = 0x29469395eAf6f95920E59F858042f0e28D98a20B

export MAINNET_RPC_URL
export FORK_BLOCK
export FOUNDRY_DISABLE_NIGHTLY_WARNING = 1

# Signing and verification secrets reach forge through the environment, never
# through a command line. Empty values, as left by `.env.example`, are not
# exported, so that `WithSigner` falls through to the next credential.
ifneq ($(strip $(PRIVATE_KEY)),)
export PRIVATE_KEY
else
unexport PRIVATE_KEY
endif
ifneq ($(strip $(MNEMONIC)),)
export MNEMONIC
else
unexport MNEMONIC
endif
ifneq ($(strip $(ETHERSCAN_API_KEY)),)
export ETHERSCAN_API_KEY
else
unexport ETHERSCAN_API_KEY
endif

# Fork runs use chain id 1, so keep their broadcast records apart from those
# of the real mainnet deployment.
simulate deploy-fork upgrade-fork rescue-fork rescue-vault-fork: \
	export FOUNDRY_BROADCAST = broadcast-fork

.PHONY: install
install:
	@cd contracts && forge soldeer install

.PHONY: build
build:
	@cd contracts && forge build

.PHONY: test
test:
	@echo "Testing against mainnet forked at block $(FORK_BLOCK) ..."
	@cd contracts && forge test $(ARGS)

.PHONY: diff
# The entire change Blur needs to review: the pristine verified source against
# the patched source. Exits 0 even though the files differ.
diff:
	@diff -ru contracts/src/upstream/pool contracts/src/pool || true

.PHONY: fork
# Run an anvil mainnet fork in the foreground.
fork:
	@echo "Forking mainnet at block $(FORK_BLOCK) on $(ANVIL_RPC) ..."
	@anvil $(ANVIL_FLAGS)

.PHONY: deploy-fork
# Deploy the patched implementation through CreateX on the running fork.
deploy-fork:
	@cd contracts && PRIVATE_KEY=$(ANVIL_PRIVATE_KEY) \
		forge script script/DeployBlurPool.s.sol \
		--rpc-url $(ANVIL_RPC) \
		--broadcast --slow

.PHONY: upgrade-fork
# Approve and execute the upgrade from the real Safe owners on the running
# fork.
upgrade-fork:
	$(call fund_safe_owners,$(BLUR_POOL_OWNER))
	@cd contracts && forge script script/UpgradeBlurPool.s.sol \
		--rpc-url $(ANVIL_RPC) \
		--broadcast --slow --unlocked \
		--sender $(ANVIL_ACCOUNT)

.PHONY: rescue-fork
# Drive each stuck royalty receiver through its own distribution path on the
# running fork.
rescue-fork:
	@cast rpc anvil_setBalance $(ROYALTIES_FLUSHER) 0xde0b6b3a7640000 \
		--rpc-url $(ANVIL_RPC) > /dev/null
	@cd contracts && forge script script/RescueStuckFunds.s.sol \
		--rpc-url $(ANVIL_RPC) \
		--broadcast --slow --unlocked \
		--sender $(ANVIL_ACCOUNT)

.PHONY: rescue-vault-fork
# Rescue the `AssetVault` through its own governance on the running fork: its
# admin Safe queues the rescue on the timelock, the fork's clock jumps past
# the timelock delay, and the Safe executes it. The ETA leaves an hour of
# margin over the later of the fork's clock and the wall clock, since anvil
# may stamp new blocks with either.
rescue-vault-fork:
	$(call fund_safe_owners,$(ASSET_VAULT_ADMIN))
	@set -e; \
	NOW=$$(date +%s); \
	LATEST=$$(cast block latest --field timestamp --rpc-url $(ANVIL_RPC)); \
	BASE=$$(( NOW > LATEST ? NOW : LATEST )); \
	DELAY=$$(cast call $(ASSET_VAULT_TIMELOCK) 'delay()(uint256)' \
		--rpc-url $(ANVIL_RPC) | cut -d' ' -f1); \
	ETA=$$(( BASE + DELAY + 3600 )); \
	AMOUNT=$$(cast call $(BLUR_POOL) 'balanceOf(address)(uint256)' \
		$(ASSET_VAULT) --rpc-url $(ANVIL_RPC) | cut -d' ' -f1); \
	cd contracts; \
	forge script script/RescueAssetVault.s.sol \
		--sig "queue(uint256,uint256)" $$ETA $$AMOUNT \
		--rpc-url $(ANVIL_RPC) \
		--broadcast --slow --unlocked \
		--sender $(ANVIL_ACCOUNT); \
	echo "Advancing the fork's clock to the ETA, $$ETA ..."; \
	cast rpc evm_setNextBlockTimestamp $$ETA \
		--rpc-url $(ANVIL_RPC) > /dev/null; \
	cast rpc evm_mine --rpc-url $(ANVIL_RPC) > /dev/null; \
	forge script script/RescueAssetVault.s.sol \
		--sig "execute(uint256,uint256)" $$ETA $$AMOUNT \
		--rpc-url $(ANVIL_RPC) \
		--broadcast --slow --unlocked \
		--sender $(ANVIL_ACCOUNT)

.PHONY: simulate
# Start a fresh fork in the background, run the full deployment against it as
# real transactions, show the result, and tear the fork down.
simulate:
	@if cast chain-id --rpc-url $(ANVIL_RPC) > /dev/null 2>&1; then \
		echo "Error: something is already listening on $(ANVIL_RPC)."; \
		echo "Stop it, or use 'make deploy-fork upgrade-fork rescue-fork rescue-vault-fork'."; \
		exit 1; \
	fi
	@set -e; \
	echo "Forking mainnet at block $(FORK_BLOCK) on $(ANVIL_RPC) ..."; \
	anvil $(ANVIL_FLAGS) > anvil.log 2>&1 & \
	ANVIL_PID=$$!; \
	trap 'kill $$ANVIL_PID 2> /dev/null || true' EXIT; \
	for i in $$(seq 1 60); do \
		cast chain-id --rpc-url $(ANVIL_RPC) > /dev/null 2>&1 && break; \
		if ! kill -0 $$ANVIL_PID 2> /dev/null; then \
			echo "Error: anvil exited; see anvil.log."; exit 1; \
		fi; \
		sleep 1; \
	done; \
	echo ""; \
	echo "Implementation before: $$(cast storage $(BLUR_POOL) \
		$(IMPLEMENTATION_SLOT) --rpc-url $(ANVIL_RPC))"; \
	$(MAKE) --no-print-directory stuck-balances; \
	echo ""; \
	$(MAKE) --no-print-directory deploy-fork; \
	$(MAKE) --no-print-directory upgrade-fork; \
	$(MAKE) --no-print-directory rescue-fork; \
	$(MAKE) --no-print-directory rescue-vault-fork; \
	echo ""; \
	echo "Implementation after: $$(cast storage $(BLUR_POOL) \
		$(IMPLEMENTATION_SLOT) --rpc-url $(ANVIL_RPC))"; \
	echo "Blur Pool owner after: $$(cast call $(BLUR_POOL) \
		'owner()(address)' --rpc-url $(ANVIL_RPC))"; \
	$(MAKE) --no-print-directory stuck-balances; \
	echo ""; \
	echo "Simulation complete."

.PHONY: stuck-balances
# Read the stuck holders' Blur Pool balances from the running fork.
stuck-balances:
	@echo "Stuck holder Blur Pool balances on $(ANVIL_RPC):"
	@for HOLDER in $(STUCK_HOLDERS); do \
		echo "  $$HOLDER: $$(cast call $(BLUR_POOL) \
			'balanceOf(address)(uint256)' $$HOLDER \
			--rpc-url $(ANVIL_RPC) | cut -d' ' -f1) wei"; \
	done
	@echo "Asset vault timelock Ether balance: $$(cast balance \
		$(ASSET_VAULT_TIMELOCK) --rpc-url $(ANVIL_RPC)) wei"

.PHONY: propose
# Print the Safe transaction for Blur's signers against live mainnet.
propose:
	@cd contracts && forge script script/UpgradeBlurPool.s.sol \
		--sig "propose()" \
		--rpc-url $(MAINNET_RPC_URL)

.PHONY: deploy-check
# Simulate the mainnet deployment against live mainnet state without
# broadcasting: shows the pinned address, the init code hash, and whether the
# implementation already exists. Uses your signer when configured, otherwise
# anvil's public development key (the deployer does not affect the address).
deploy-check:
	@cd contracts && \
		$(if $(strip $(PRIVATE_KEY)$(MNEMONIC)),,PRIVATE_KEY=$(ANVIL_PRIVATE_KEY)) \
		forge script script/DeployBlurPool.s.sol \
		--rpc-url $(MAINNET_RPC_URL)

.PHONY: deploy
# Deploy the patched implementation to mainnet for real, then verify it on
# Etherscan. Permissionless and idempotent; signs with PRIVATE_KEY, or MNEMONIC
# at index 0 (see `contracts/script/WithSigner.s.sol`). The script refuses to
# deploy unless the build matches the pinned init code hash and address.
deploy:
	@if [ "$(MAINNET_RPC_URL)" = "$(DEFAULT_MAINNET_RPC_URL)" ]; then \
		echo "Error: set MAINNET_RPC_URL to your own mainnet RPC to deploy;"; \
		echo "the public default is fine for forking but not for broadcasting."; \
		exit 1; \
	fi
	@test -n "$(strip $(PRIVATE_KEY)$(MNEMONIC))" || { \
		echo "Error: set PRIVATE_KEY or MNEMONIC (see .env.example)."; \
		exit 1; \
	}
	@test -n "$(strip $(ETHERSCAN_API_KEY))" || { \
		echo "Error: set ETHERSCAN_API_KEY (see .env.example)."; \
		exit 1; \
	}
	@cd contracts && forge script script/DeployBlurPool.s.sol \
		--rpc-url $(MAINNET_RPC_URL) \
		--broadcast --slow
	@$(MAKE) --no-print-directory verify

.PHONY: verify
# Verify the deployed implementation on Etherscan. Forge submits the patched
# source with Blur's exact compiler settings (solc 0.8.17, 20,000 runs,
# London, no metadata hash) and the original constructor arguments. Safe to
# rerun; an already verified contract is skipped. Building first gives forge
# the compiler version and settings to submit, even after `make clean`.
verify: build
	@test -n "$(strip $(ETHERSCAN_API_KEY))" || { \
		echo "Error: set ETHERSCAN_API_KEY (see .env.example)."; \
		exit 1; \
	}
	@cd contracts && forge verify-contract $(IMPLEMENTATION) \
		src/pool/BlurPool.sol:BlurPool \
		--constructor-args $$(cast abi-encode \
			'constructor(address,address,address,address)' \
			$(EXCHANGE) $(EXCHANGE_V2) $(SWAP) $(BLEND)) \
		--chain mainnet \
		--watch --retries 10 --delay 15

.PHONY: clean
clean:
	@cd contracts && forge clean
	@rm -rf contracts/broadcast contracts/broadcast-fork anvil.log

.PHONY: help
help:
	@echo "Blur Pool ERC-20 transfer upgrade"
	@echo ""
	@echo "  install          Install Soldeer dependencies."
	@echo "  build            Compile contracts."
	@echo "  test             Run the fork test suite (ARGS=... passes through to forge test)."
	@echo "  diff             Show the patch against Blur's verified source."
	@echo ""
	@echo "  simulate         Fork mainnet with anvil and run deploy, upgrade, and rescue as real transactions."
	@echo "  fork             Run an anvil mainnet fork in the foreground."
	@echo "  deploy-fork      Deploy the implementation via CreateX on the running fork."
	@echo "  upgrade-fork     Approve and execute the upgrade from the Safe owners on the running fork."
	@echo "  rescue-fork      Drive the stuck royalty receivers on the running fork."
	@echo "  rescue-vault-fork  Queue, time-travel, and execute the asset vault rescue on the running fork."
	@echo "  stuck-balances   Show the stuck receivers' Blur Pool balances on the running fork."
	@echo ""
	@echo "  propose          Print the Safe transaction for Blur's signers against live mainnet."
	@echo "  deploy-check     Simulate the mainnet deployment without broadcasting."
	@echo "  deploy           Deploy the implementation to mainnet and verify it (permissionless, idempotent)."
	@echo "  verify           Verify the deployed implementation on Etherscan (safe to rerun)."
	@echo ""
	@echo "  clean            Remove build artifacts."
	@echo "  help             Show this help message."
	@echo ""
	@echo "Configuration (.env or environment):"
	@echo "  MAINNET_RPC_URL  Archive-capable mainnet RPC (default: $(DEFAULT_MAINNET_RPC_URL))."
	@echo "  FORK_BLOCK       Pinned fork block (default: $(DEFAULT_FORK_BLOCK))."
	@echo "  ANVIL_PORT       Local fork port (default: $(ANVIL_PORT))."
	@echo ""

.DEFAULT_GOAL := help
