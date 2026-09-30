FORGE ?= $(HOME)/.foundry/bin/forge
ANVIL ?= $(HOME)/.foundry/bin/anvil

NETWORK ?= arbitrum-sepolia
CHAIN_ID ?= 421614
ACCOUNT ?=

-include .env
export

RPC_URL ?= $(or $(ARBITRUM_SEPOLIA_RPC_URL),https://sepolia-rollup.arbitrum.io/rpc)

SIGN_ARGS = $(if $(ACCOUNT),--account $(ACCOUNT),$(if $(PRIVATE_KEY),--private-key $(PRIVATE_KEY),))

ifneq ($(strip $(ARBISCAN_API_KEY)),)
VERIFY_ARGS = --verify --verifier etherscan --chain $(CHAIN_ID) --etherscan-api-key $(ARBISCAN_API_KEY)
else
VERIFY_ARGS =
endif

.PHONY: all build sizes test test-v snapshot fmt coverage clean anvil deploy-dry-run deploy-sepolia export export-abi export-addresses

all: build

build:
	$(FORGE) build

sizes:
	$(FORGE) build --sizes

test:
	$(FORGE) test

test-v:
	$(FORGE) test -vvv

snapshot:
	$(FORGE) snapshot

fmt:
	$(FORGE) fmt

coverage:
	$(FORGE) coverage

clean:
	rm -rf cache out

anvil:
	$(ANVIL)

deploy-dry-run:
	$(FORGE) script script/Deploy.s.sol:Deploy --rpc-url $(RPC_URL) $(SIGN_ARGS)

deploy-sepolia:
	@test -n "$(ACCOUNT)$(PRIVATE_KEY)" || (echo "ERROR: set ACCOUNT=<keystore-name> or PRIVATE_KEY in .env (see .env.example)"; exit 1)
	$(FORGE) script script/Deploy.s.sol:Deploy --rpc-url $(RPC_URL) $(SIGN_ARGS) --broadcast $(VERIFY_ARGS) --slow

export: export-abi export-addresses

export-abi:
	mkdir -p exports/abi
	$(FORGE) inspect TreeRegistry abi --json > exports/abi/TreeRegistry.json
	$(FORGE) inspect TreeNFT abi --json > exports/abi/TreeNFT.json
	$(FORGE) inspect TreeBond abi --json > exports/abi/TreeBond.json
	$(FORGE) inspect VerificationRegistry abi --json > exports/abi/VerificationRegistry.json

export-addresses:
	@test -f deployments/$(NETWORK).json || (echo "ERROR: deployments/$(NETWORK).json not found; run 'make deploy-sepolia' first"; exit 1)
	DEPLOYMENT_NETWORK=$(NETWORK) $(FORGE) script script/Export.s.sol:Export
