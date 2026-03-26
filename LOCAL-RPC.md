# Running a Local RPC Node

Instead of relying on public RPC endpoints, we strongly recommend running your own local node.

## Why Local RPC?
- ✅ Faster — no network latency
- ✅ More reliable — not dependent on third parties
- ✅ Full control — your own data
- ✅ Required for compute job processing

## Prerequisites
Your node must be fully synced before using local RPC:
```bash
republicd status --node tcp://localhost:43657 | jq '.sync_info.catching_up'
```
Must return `false` before proceeding.

## Step 1: Enable TX Indexer
Required for querying transactions and job IDs:
```bash
sed -i -e "s/^indexer *=.*/indexer = \"kv\"/" $HOME/.republicd/config/config.toml
sudo systemctl restart republicd
```

Verify:
```bash
republicd status --node tcp://localhost:43657 | jq '.node_info.other.tx_index'
```
Must return `"on"`

## Step 2: Enable REST API
Required for compute job processing:
```bash
sed -i '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' $HOME/.republicd/config/app.toml
sudo systemctl restart republicd
```

Verify:
```bash
curl -s http://localhost:43317/cosmos/base/node/v1beta1/config | jq '.minimum_gas_price'
```
Must return a value like `"250000000.000000000000000000arai"`

## Step 3: Using Local RPC
Add `--node tcp://localhost:43657` to all commands:
```bash
# Check balance
republicd query bank balances YOUR_ADDRESS --node tcp://localhost:43657

# Check sync status
republicd status --node tcp://localhost:43657 | jq '.sync_info'

# Send transaction
republicd tx ... --node tcp://localhost:43657
```

## Step 4: Check Node is Running
```bash
sudo systemctl status republicd
```
```bash
# Check logs
sudo journalctl -u republicd -f
```

## Ports
| Port | Service |
|------|---------|
| 43657 | RPC (CometBFT) |
| 43317 | REST API |
| 43656 | P2P |

## Full Node Setup
If you haven't set up your node yet, follow:
[SETUP.md](SETUP.md) → [GETTING-STARTED.md](GETTING-STARTED.md)

## Notes
- Never expose your RPC publicly unless you know what you're doing
- Local RPC is only accessible from your own server
- If node is down, use public RPC as backup: `https://rpc.republicai.io`
