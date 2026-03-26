#!/bin/bash
# Submit a test compute job to your own validator

VALOPER="raivaloper1vgjpdewsmvnrdqlk75pmhhae397wghfkfv8zr2"
NODE="tcp://localhost:26657"
CHAIN_ID="raitestnet_77701-1"

echo "=== Submitting test job ==="
republicd tx computevalidation submit-job \
  $VALOPER \
  republic-llm-inference:latest \
  https://republicai.devn.cloud/upload \
  https://republicai.devn.cloud/result \
  example-verification:latest \
  1000000000000000000arai \
  --from my-wallet \
  --home /root/.republicd \
  --chain-id $CHAIN_ID \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node $NODE \
  --keyring-backend test \
  -y

echo ""
echo "=== Done ==="
