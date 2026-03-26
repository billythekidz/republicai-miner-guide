# Republic AI - Job Result Submit Fix

## Problem
`republicd tx computevalidation submit-job-result` command fails with:
```
hrp does not match bech32 prefix: expected 'raivaloper' got 'rai'
```

This is a binary bug. The command internally tries to convert the `rai` address 
to `raivaloper` format but fails.

## Root Cause
The `MsgSubmitJobResult` message requires the `validator` field in `raivaloper` 
bech32 format, but the binary cannot handle this conversion automatically.

## Solution: Manual TX Sign & Broadcast

### Step 1: Generate unsigned TX
```bash
SHA256=$(sha256sum /var/lib/republic/jobs/JOB_ID/result.bin | awk '{print $1}')

echo "YOUR_KEYRING_PASSWORD" | republicd tx computevalidation submit-job-result \
  JOB_ID \
  http://YOUR_IP:8080/JOB_ID/result.bin \
  example-verification:latest \
  $SHA256 \
  --from wallet \
  --home $HOME/.republicd \
  --chain-id raitestnet_77701-1 \
  --gas 300000 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  --generate-only 2>/dev/null > /tmp/tx_unsigned.json
```

### Step 2: Fix validator address (rai → raivaloper)
```bash
python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('YOUR_RAI_ADDRESS')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
print('Fixed:', valoper)
"
```

### Step 3: Sign TX
```bash
echo "YOUR_KEYRING_PASSWORD" | republicd tx sign /tmp/tx_unsigned.json \
  --from wallet \
  --home $HOME/.republicd \
  --chain-id raitestnet_77701-1 \
  --node tcp://localhost:43657 \
  --output-document /tmp/tx_signed.json
```

### Step 4: Broadcast TX
```bash
republicd tx broadcast /tmp/tx_signed.json \
  --node tcp://localhost:43657 \
  --chain-id raitestnet_77701-1
```

## Batch Submit (Multiple Jobs)
```bash
for JOB_ID in 11 12 13 14 15; do
  echo "Processing Job $JOB_ID..."
  SHA256=$(sha256sum /var/lib/republic/jobs/$JOB_ID/result.bin | awk '{print $1}')
  
  echo "YOUR_PASSWORD" | republicd tx computevalidation submit-job-result \
    $JOB_ID \
    http://YOUR_IP:8080/$JOB_ID/result.bin \
    example-verification:latest \
    $SHA256 \
    --from wallet \
    --home $HOME/.republicd \
    --chain-id raitestnet_77701-1 \
    --gas 300000 \
    --gas-prices 1000000000arai \
    --node tcp://localhost:43657 \
    --generate-only 2>/dev/null > /tmp/tx_unsigned.json

  python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('YOUR_RAI_ADDRESS')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
"

  echo "YOUR_PASSWORD" | republicd tx sign /tmp/tx_unsigned.json \
    --from wallet \
    --home $HOME/.republicd \
    --chain-id raitestnet_77701-1 \
    --node tcp://localhost:43657 \
    --output-document /tmp/tx_signed.json 2>/dev/null

  republicd tx broadcast /tmp/tx_signed.json \
    --node tcp://localhost:43657 \
    --chain-id raitestnet_77701-1 | grep txhash

  echo "✅ Job $JOB_ID submitted!"
  sleep 5
done
```

## Also Required: Enable REST API
```bash
sed -i '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' $HOME/.republicd/config/app.toml
sudo systemctl restart republicd
```

## Expected Result
```yaml
status: PendingValidation
job_id: "16"
validator: raivaloper1...
action: /republic.computevalidation.v1.MsgSubmitJobResult
```

## Notes
- HTTP server must be running for result file access:
  `cd /var/lib/republic/jobs && python3 -m http.server 8080 &`
- Validator must be BONDED to submit results
- Gas: 300,000 is sufficient (actual used: ~90,000)
