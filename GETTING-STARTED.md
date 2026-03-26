# Republic AI Testnet - Getting Started

## Step 1: Setup Node
Follow [SETUP.md](SETUP.md)
- Install prerequisites
- Install Go 1.22.3
- Install Cosmovisor
- Install binary with patchelf (GLIBC fix)
- Initialize node
- Configure peers
- Start node

## Step 2: Wait for Sync
```bash
watch -n 5 "republicd status --node tcp://localhost:43657 | jq '.sync_info.catching_up'"
```
Wait until `catching_up: false`

## Step 3: Enable TX Indexer
```bash
sed -i -e "s/^indexer *=.*/indexer = \"kv\"/" $HOME/.republicd/config/config.toml
sudo systemctl restart republicd
```

## Step 4: Enable REST API
```bash
sed -i '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' $HOME/.republicd/config/app.toml
sudo systemctl restart republicd
```

## Step 5: Get Testnet Tokens
Follow [POINTS.md](POINTS.md)
- Go to https://points.republicai.io
- Request testnet RAI tokens

## Step 6: Create Validator
```bash
republicd tx staking create-validator \
  --amount 1000000000000000000arai \
  --from wallet \
  --commission-rate 0.1 \
  --commission-max-rate 0.2 \
  --commission-max-change-rate 0.01 \
  --min-self-delegation 1 \
  --pubkey $(republicd tendermint show-validator --home $HOME/.republicd) \
  --moniker "YOUR_MONIKER" \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  -y
```

## Step 7: Enter Active Set
Delegate enough RAI to exceed lowest bonded validator:
```bash
republicd query staking validators --node tcp://localhost:43657 -o json | \
  jq '.validators | map(select(.status=="BOND_STATUS_BONDED")) | sort_by(.tokens | tonumber) | first | {moniker: .description.moniker, tokens: .tokens}'
```
```bash
republicd tx staking delegate \
  YOUR_VALOPER_ADDRESS \
  AMOUNT_arai \
  --from wallet \
  --home $HOME/.republicd \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  -y
```

## Step 8: Setup GPU Docker
Follow [compute/DOCKER-GPU.md](compute/DOCKER-GPU.md)
- Verify GPU with nvidia-smi
- Build CUDA Docker image

## Step 9: Install DevTools
Follow [compute/DEVTOOLS.md](compute/DEVTOOLS.md)
- Clone devtools
- Fix memo bug
- Import wallet key

## Step 10: Submit Your First Job
Follow [compute/FIRST-JOB.md](compute/FIRST-JOB.md)
- Submit job to chain
- Run GPU inference
- Submit result (use RESULT-SUBMIT-FIX.md workaround)

## Step 11: Enable Auto Compute
Follow [compute/AUTO-COMPUTE.md](compute/AUTO-COMPUTE.md)
- Setup auto-compute script
- Run in background

## Troubleshooting
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Migration to New VPS
See [MIGRATION.md](MIGRATION.md)
