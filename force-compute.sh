#!/bin/bash
# Force-compute a specific job and submit result
# Usage: force-compute.sh <JOB_ID>

set -e

JOB_ID=${1:?Usage: force-compute.sh <JOB_ID>}
WALLET="rai1vgjpdewsmvnrdqlk75pmhhae397wghfkwe8lgu"
NODE="tcp://localhost:26657"
CHAIN_ID="raitestnet_77701-1"
RESULT_BASE_URL="https://republicai.devn.cloud"
JOBS_DIR="/var/lib/republic/jobs"
RESULT_FILE="$JOBS_DIR/$JOB_ID/result.bin"

echo "🚀 Force-computing job $JOB_ID..."

# Step 1: Run inference
mkdir -p "$JOBS_DIR/$JOB_ID"
echo "⚙️  Running GPU inference..."
docker run --rm --gpus all \
  -v "$JOBS_DIR/$JOB_ID:/output" \
  -v /root/inference.py:/app/inference.py \
  republic-llm-inference:latest 2>/root/auto-compute-docker.log

if [ ! -f "$RESULT_FILE" ]; then
  echo "❌ Inference failed — no result.bin"
  exit 1
fi

echo "✅ Inference done!"
ls -la "$RESULT_FILE"

# Step 2: Calculate hash
SHA256=$(sha256sum "$RESULT_FILE" | awk '{print $1}')
echo "🔑 SHA256: $SHA256"

# Step 3: Submit result on-chain (with bech32 fix)
echo "📡 Submitting result on-chain..."

echo "" | republicd tx computevalidation submit-job-result \
  "$JOB_ID" \
  "$RESULT_BASE_URL/$JOB_ID/result.bin" \
  example-verification:latest \
  "$SHA256" \
  --from my-wallet \
  --home /root/.republicd \
  --chain-id "$CHAIN_ID" \
  --gas 300000 \
  --gas-prices 1000000000arai \
  --node "$NODE" \
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

echo "" | republicd tx sign /tmp/tx_unsigned.json \
  --from my-wallet \
  --home /root/.republicd \
  --chain-id "$CHAIN_ID" \
  --node "$NODE" \
  --keyring-backend test \
  --output-document /tmp/tx_signed.json 2>/dev/null

TXHASH=$(republicd tx broadcast /tmp/tx_signed.json \
  --node "$NODE" \
  --chain-id "$CHAIN_ID" | grep txhash | awk '{print $2}')

echo ""
echo "🎉 Job $JOB_ID submitted!"
echo "   TX: $TXHASH"
echo "   Hash: $SHA256"
echo "   URL: $RESULT_BASE_URL/$JOB_ID/result.bin"
