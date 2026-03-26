# fast-auto.sh — Republic AI Compute Job Script

Automated compute job submission script for Republic AI testnet validators.

## Prerequisites

- Running Republic AI node (synced)
- Inference server running on port 5555 (`docker ps | grep inference`)
- File server running on port 8080 (`ps aux | grep file-server`)
- Cloudflare tunnel or public IP for result serving

---

## Setup

### 1. Download the script
```bash
wget https://raw.githubusercontent.com/M4D2510/republic-ai-node/main/compute/fast-auto.sh
chmod +x fast-auto.sh
```

### 2. Edit your values

Open `fast-auto.sh` and fill in the **REQUIRED** section:
```bash
# Your validator operator address (raivaloper1...)
VALOPER="raivaloper1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Your wallet address (rai1...)
WALLET="rai1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Your wallet keyring password
PASSWORD="your_wallet_password_here"

# Your Cloudflare tunnel domain OR server IP:PORT
SERVER_IP="api.yourdomain.com"
```

### 3. Run
```bash
nohup ./fast-auto.sh > /root/fast-auto.log 2>&1 &
```

### 4. Monitor
```bash
# Live log
tail -f /root/fast-auto.log

# Hourly stats
cat /root/fast-auto-stats.log

# Quick performance check
echo "Completed: $(grep -c 'result submitted' /root/fast-auto.log)"
echo "Skipped:   $(grep -c 'not found' /root/fast-auto.log)"
```

### 5. Stop
```bash
pkill -f fast-auto.sh
```

---

## Performance Tuning

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TX_WAIT_SLEEP` | 6 | Seconds to wait after TX broadcast |
| `RETRY_COUNT` | 3 | Max retries if job ID not found |
| `RETRY_SLEEP` | 3 | Seconds between retries |
| `RESULT_SLEEP` | 2 | Seconds after result submission |

### Presets

| Mode | TX_WAIT | RETRY_COUNT | RETRY_SLEEP | Jobs/hr | Skip Rate |
|------|---------|-------------|-------------|---------|-----------|
| **Fast** | 4 | 3 | 2 | ~400 | High |
| **Balanced** ✅ | 6 | 3 | 3 | ~300 | Medium |
| **Safe** | 10 | 5 | 5 | ~180 | Low |
| **Very Safe** | 15 | 5 | 5 | ~120 | Very Low |

Start with **Balanced**. Switch to **Safe** if skip rate exceeds 50%.

---

## Reducing Skips

Skips happen for two reasons:

**1. REST API indexing delay** — TX is on chain but not yet queryable
- Fix: Increase `TX_WAIT_SLEEP` (6 → 8 or 10)

**2. TX dropped from mempool** — Chain-side issue, ~30-40% is normal
- Cannot be fully fixed, known chain behavior

### Step-by-step:
```bash
# Step 1: Increase TX wait time
TX_WAIT_SLEEP=10

# Step 2: If still skipping, increase retries
RETRY_COUNT=5
RETRY_SLEEP=5
```

---

## How It Works
```
[1] Submit job TX → chain
[2] Wait TX_WAIT_SLEEP seconds
[3] Query REST API for job ID
    └─ Not found? Retry RETRY_COUNT times with RETRY_SLEEP delay
    └─ Still not found? Skip, refresh sequence, continue
[4] Run inference (port 5555)
[5] Submit result TX → chain (with bech32 fix)
[6] Wait RESULT_SLEEP seconds → repeat
```

---

## Known Issues

### bech32 Bug
`submit-job-result` expects a valoper address but CLI sends a wallet address.
The script automatically fixes this with a Python bech32 conversion.

### Sequence Mismatch
Only run **one instance** at a time.
```bash
ps aux | grep fast-auto | grep -v grep
```

### Inference Server Not Running
```bash
docker ps | grep inference
docker restart inference-server
```

---

## Full Script

Copy below, fill in your values, save as `fast-auto.sh`:
```bash
#!/bin/bash
# =============================================================================
# fast-auto.sh — Republic AI Compute Job Submission Script
# Author: M4D2510 | github.com/M4D2510/republic-ai-node
# =============================================================================

# REQUIRED — replace with your own values
VALOPER="raivaloper1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
WALLET="rai1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
PASSWORD="your_wallet_password_here"
SERVER_IP="api.yourdomain.com"

# Fixed settings
NODE="tcp://localhost:43657"
CHAIN_ID="raitestnet_77701-1"
JOBS_DIR="/var/lib/republic/jobs"
JOB_FEE="1000000000000000arai"

# Performance tuning — see guide above
TX_WAIT_SLEEP=6
RETRY_COUNT=3
RETRY_SLEEP=3
RESULT_SLEEP=2

# Stats
STATS_COMPLETED=0
STATS_SKIPPED=0
STATS_START=$(date +%s)
STATS_LAST_LOG=$(date +%s)
STATS_FILE="/root/fast-auto-stats.log"

log_stats() {
  local now=$(date +%s)
  local elapsed=$(( (now - STATS_START) / 60 ))
  local total=$((STATS_COMPLETED + STATS_SKIPPED))
  local rate=0
  [ $total -gt 0 ] && rate=$((STATS_COMPLETED * 100 / total))
  local hourly=0
  [ $elapsed -gt 0 ] && hourly=$((STATS_COMPLETED * 60 / elapsed))
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${elapsed}m | Completed:$STATS_COMPLETED | Skipped:$STATS_SKIPPED | Rate:${rate}% | ${hourly}/hr" | tee -a "$STATS_FILE"
}

echo "🚀 Fast Auto started..."
echo "   Validator: $VALOPER"
echo "   Server:    https://$SERVER_IP"
echo "   Settings:  TX_WAIT=${TX_WAIT_SLEEP}s | RETRY=${RETRY_COUNT}x${RETRY_SLEEP}s"

SEQ=$(republicd query auth account $WALLET --node $NODE -o json 2>/dev/null | jq -r '.account.value.sequence // .account.sequence // "0"')
echo "Starting sequence: $SEQ"
log_stats

while true; do
  NOW=$(date +%s)
  [ $((NOW - STATS_LAST_LOG)) -ge 3600 ] && { log_stats; STATS_LAST_LOG=$NOW; }

  # Step 1: Submit job
  echo "📤 Submitting new job... (seq: $SEQ)"
  TX=$(echo "$PASSWORD" | republicd tx computevalidation submit-job \
    $VALOPER \
    republic-llm-inference:latest \
    https://$SERVER_IP/upload \
    https://$SERVER_IP/result \
    example-verification:latest \
    $JOB_FEE \
    --from wallet \
    --home $HOME/.republicd \
    --chain-id $CHAIN_ID \
    --gas 300000 \
    --gas-prices 2000000000arai \
    --sequence $SEQ \
    --node $NODE \
    -y | grep txhash | awk '{print $2}')
  echo "✅ TX: $TX"
  sleep $TX_WAIT_SLEEP

  # Step 2: Get job ID
  JOB_ID=""
  for i in $(seq 1 $RETRY_COUNT); do
    RESPONSE=$(curl -s "https://rest.republicai.io/cosmos/tx/v1beta1/txs/$TX" 2>/dev/null)
    JOB_ID=$(echo "$RESPONSE" | jq -r '.tx_response.events[] | select(.type=="job_submitted") | .attributes[] | select(.key=="job_id") | .value' 2>/dev/null)
    [ -n "$JOB_ID" ] && break
    echo "   Retry $i/$RETRY_COUNT..."
    sleep $RETRY_SLEEP
  done
  echo "📋 Job ID: $JOB_ID"

  if [ -z "$JOB_ID" ]; then
    echo "❌ Job ID not found, skipping..."
    STATS_SKIPPED=$((STATS_SKIPPED + 1))
    SEQ=$(republicd query auth account $WALLET --node $NODE -o json 2>/dev/null | jq -r '.account.value.sequence // .account.sequence // "0"')
    sleep 2
    continue
  fi
  SEQ=$((SEQ + 1))

  # Step 3: Run inference
  RESULT_FILE="$JOBS_DIR/$JOB_ID/result.bin"
  mkdir -p $JOBS_DIR/$JOB_ID
  echo "⚙️  Running inference..."
  curl -s -X POST http://localhost:5555/infer \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"What is the future of decentralized AI?\",\"output_path\":\"$RESULT_FILE\"}" > /dev/null

  if [ ! -f "$RESULT_FILE" ]; then
    echo "❌ Inference failed — check: docker ps | grep inference"
    sleep 2
    continue
  fi
  echo "✓  Inference done"

  # Step 4: Submit result (bech32 fix applied)
  SHA256=$(sha256sum $RESULT_FILE | awk '{print $1}')
  echo "$PASSWORD" | republicd tx computevalidation submit-job-result \
    $JOB_ID \
    https://$SERVER_IP/$JOB_ID/result.bin \
    example-verification:latest \
    $SHA256 \
    --from wallet \
    --home $HOME/.republicd \
    --chain-id $CHAIN_ID \
    --gas 300000 \
    --gas-prices 2000000000arai \
    --sequence $SEQ \
    --node $NODE \
    --generate-only 2>/dev/null > /tmp/tx_unsigned2.json

  python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned2.json'))
_, data = bech32.bech32_decode('$WALLET')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned2.json', 'w'))
"
  echo "$PASSWORD" | republicd tx sign /tmp/tx_unsigned2.json \
    --from wallet \
    --home $HOME/.republicd \
    --chain-id $CHAIN_ID \
    --node $NODE \
    --output-document /tmp/tx_signed2.json 2>/dev/null

  RESULT_OUT=$(republicd tx broadcast /tmp/tx_signed2.json \
    --node $NODE \
    --chain-id $CHAIN_ID 2>&1)

  echo "$RESULT_OUT" | tee -a /root/broadcast.log | grep txhash | \
    awk '{print "🎉 Job '$JOB_ID' result submitted! TX: "$2}'

  if echo "$RESULT_OUT" | grep -q txhash; then
    STATS_COMPLETED=$((STATS_COMPLETED + 1))
  fi
  SEQ=$((SEQ + 1))
  sleep $RESULT_SLEEP
done
```

---

## Support

- Republic AI Discord: [discord.gg/republicai](https://discord.gg/republicai)
- This repo: [M4D2510/republic-ai-node](https://github.com/M4D2510/republic-ai-node)
