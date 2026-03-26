#!/bin/bash

WALLET="rai1vgjpdewsmvnrdqlk75pmhhae397wghfkwe8lgu"
VALOPER="raivaloper1vgjpdewsmvnrdqlk75pmhhae397wghfkfv8zr2"
NODE="tcp://localhost:26657"
CHAIN_ID="raitestnet_77701-1"
PASSWORD=""
RESULT_BASE_URL="https://republicai.devn.cloud"
JOBS_DIR="/var/lib/republic/jobs"

echo "🚀 Auto-compute started at $(date)..."

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

    echo "📦 New job found: $JOB_ID at $(date)"
    
    mkdir -p $JOBS_DIR/$JOB_ID
    # Mount external inference.py for easy adjustment (writes to /output/result.bin)
    docker run --rm --gpus all \
      -v $JOBS_DIR/$JOB_ID:/output \
      -v /root/inference.py:/app/inference.py \
      republic-llm-inference:latest 2>/root/auto-compute-docker.log
    
    if [ ! -f "$RESULT_FILE" ]; then
      echo "❌ Inference failed for job $JOB_ID"
      continue
    fi

    echo "✅ Inference done for job $JOB_ID"

    SHA256=$(sha256sum $RESULT_FILE | awk '{print $1}')

    echo "$PASSWORD" | republicd tx computevalidation submit-job-result \
      $JOB_ID \
      $RESULT_BASE_URL/$JOB_ID/result.bin \
      example-verification:latest \
      $SHA256 \
      --from my-wallet \
      --home /root/.republicd \
      --chain-id $CHAIN_ID \
      --gas 300000 \
      --gas-prices 1000000000arai \
      --node $NODE \
      --keyring-backend test \
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
      --from my-wallet \
      --home /root/.republicd \
      --chain-id $CHAIN_ID \
      --node $NODE \
      --keyring-backend test \
      --output-document /tmp/tx_signed.json 2>/dev/null

    TXHASH=$(republicd tx broadcast /tmp/tx_signed.json \
      --node $NODE \
      --chain-id $CHAIN_ID | grep txhash | awk '{print $2}')

    echo "🎉 Job $JOB_ID submitted! TX: $TXHASH"
  done

  sleep 30
done
