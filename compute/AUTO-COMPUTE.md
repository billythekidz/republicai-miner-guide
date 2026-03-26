# Republic AI - Auto Compute Script

## Overview
Automatically detects new jobs targeting your validator, runs GPU inference, and submits results to the chain.

## Features
- ✅ Runs every 30 seconds to check for new jobs
- ✅ GPU accelerated inference (RTX 3090, ~8 seconds)
- ✅ Auto submit with binary bug workaround
- ✅ Skips already processed jobs

## Setup

### 1. Make sure HTTP server is running
```bash
cd /var/lib/republic/jobs && python3 -m http.server 8080 &
```

### 2. Create the script
```bash
cat > /root/auto-compute.sh << 'SCRIPT'
#!/bin/bash

WALLET="YOUR_RAI_ADDRESS"
VALOPER="YOUR_VALOPER_ADDRESS"
NODE="tcp://localhost:43657"
CHAIN_ID="raitestnet_77701-1"
PASSWORD="YOUR_KEYRING_PASSWORD"
SERVER_IP="YOUR_SERVER_IP"
JOBS_DIR="/var/lib/republic/jobs"

echo "🚀 Auto-compute started..."

while true; do
  JOB_IDS=$(republicd query txs \
    --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
    --node $NODE -o json 2>/dev/null | \
    jq -r '.txs[] | select(.tx.body.messages[0].target_validator=="'$VALOPER'") | 
    .events[] | select(.type=="job_submitted") | 
    .attributes[] | select(.key=="job_id") | .value')

  for JOB_ID in $JOB_IDS; do
    RESULT_FILE="$JOBS_DIR/$JOB_ID/result.bin"
    
    if [ -f "$RESULT_FILE" ]; then
      continue
    fi

    echo "📦 New job found: $JOB_ID"
    
    mkdir -p $JOBS_DIR/$JOB_ID
    docker run --rm --gpus all \
      -v $JOBS_DIR/$JOB_ID:/output \
      republic-llm-inference:latest
    
    if [ ! -f "$RESULT_FILE" ]; then
      echo "❌ Inference failed for job $JOB_ID"
      continue
    fi

    echo "✅ Inference done for job $JOB_ID"

    SHA256=$(sha256sum $RESULT_FILE | awk '{print $1}')

    echo "$PASSWORD" | republicd tx computevalidation submit-job-result \
      $JOB_ID \
      http://$SERVER_IP:8080/$JOB_ID/result.bin \
      example-verification:latest \
      $SHA256 \
      --from wallet \
      --home $HOME/.republicd \
      --chain-id $CHAIN_ID \
      --gas 300000 \
      --gas-prices 1000000000arai \
      --node $NODE \
      --generate-only 2>/dev/null > /tmp/tx_unsigned.json

    python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('$WALLET')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
"

    echo "$PASSWORD" | republicd tx sign /tmp/tx_unsigned.json \
      --from wallet \
      --home $HOME/.republicd \
      --chain-id $CHAIN_ID \
      --node $NODE \
      --output-document /tmp/tx_signed.json 2>/dev/null

    TXHASH=$(republicd tx broadcast /tmp/tx_signed.json \
      --node $NODE \
      --chain-id $CHAIN_ID | grep txhash | awk '{print $2}')

    echo "🎉 Job $JOB_ID submitted! TX: $TXHASH"
  done

  sleep 30
done
SCRIPT

chmod +x /root/auto-compute.sh
```

### 3. Run in background
```bash
nohup /root/auto-compute.sh > /root/auto-compute.log 2>&1 &
echo "Auto-compute PID: $!"
```

### 4. Monitor logs
```bash
tail -f /root/auto-compute.log
```

### 5. Stop script
```bash
pkill -f auto-compute.sh
```

## Example Output
```
🚀 Auto-compute started...
📦 New job found: 25
✅ Inference done for job 25
🎉 Job 25 submitted! TX: 2890757C5D2276152D6D599E78C5E1CBC0...
```

## Notes
- Edit WALLET, VALOPER, PASSWORD, SERVER_IP before running
- GPU Docker image must be built: `republic-llm-inference:latest`
- Validator must be BONDED
- See RESULT-SUBMIT-FIX.md for binary bug workaround details
