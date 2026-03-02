# RepublicAI GPU Compute — Agent Operations Guide

> **Purpose**: Machine-readable runbook for AI agents to setup, operate, and troubleshoot RepublicAI GPU compute jobs.
> **Network**: `raitestnet_77701-1` (testnet)
> **Last verified**: 2026-03-02
> **Human guide**: See `GPU-COMPUTE-GUIDE.md` for user-facing documentation.

---

## Environment Variables (MUST resolve before any operation)

```bash
# Agent MUST resolve these values first — never use placeholders in actual commands
WALLET=$(republicd keys show my-wallet -a --home /root/.republicd --keyring-backend test 2>/dev/null)
VALOPER=$(republicd keys show my-wallet --bech val -a --home /root/.republicd --keyring-backend test 2>/dev/null)
KEY_NAME="my-wallet"
NODE="tcp://localhost:26657"
CHAIN_ID="raitestnet_77701-1"
JOBS_DIR="/var/lib/republic/jobs"
RESULT_BASE_URL=""  # Must be set after endpoint setup (Step 5)
```

**Resolution command**: Run this first to get all values:
```bash
echo "WALLET=$WALLET"
echo "VALOPER=$VALOPER"
echo "CHAIN_ID=$(curl -s http://localhost:26657/status | jq -r '.result.node_info.network')"
```

---

## Step 1: Validate Prerequisites

### 1.1 Check required binaries

```bash
# Run ALL checks. Every command must succeed (exit 0).
republicd version --long
docker --version
nvidia-smi
jq --version
python3 -c "import bech32; print('bech32 OK')"
python3 -c "import republic_core_utils; print('republic-core-utils OK')"
```

**Decision logic:**
- If `republicd` missing → STOP. Cannot proceed.
- If `docker` missing → STOP. Cannot proceed.
- If `nvidia-smi` fails → GPU jobs will fail. Warn user, but can proceed for CPU-only testing.
- If `jq` missing → `apt-get install -y jq`
- If `bech32` missing → `pip install bech32`
- If `republic_core_utils` missing → `pip install republic-core-utils`

### 1.2 Check Docker GPU access

```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

**Expected**: Exit 0, shows GPU info.
**If fails**: Install NVIDIA Container Toolkit:
```bash
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L "https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list" | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

---

## Step 2: Validate Node & Validator

### 2.1 Node sync status

```bash
CATCHING_UP=$(curl -s http://localhost:26657/status | jq -r '.result.sync_info.catching_up')
echo "catching_up=$CATCHING_UP"
```

**Gate**: If `catching_up=true` → STOP. Wait for sync. Do NOT proceed with any TX operations.

### 2.2 Validator bond status

```bash
BOND_STATUS=$(republicd query staking validator $VALOPER --node $NODE -o json 2>/dev/null | jq -r '.status')
echo "bond_status=$BOND_STATUS"
```

**Gate**: Must be `BOND_STATUS_BONDED`. If not → cannot receive or process compute jobs.

### 2.3 Wallet balance

```bash
BALANCE_ARAI=$(republicd query bank balances $WALLET --node $NODE -o json | jq -r '.balances[] | select(.denom=="arai") | .amount')
BALANCE_RAI=$(python3 -c "print(int('${BALANCE_ARAI:-0}') / 10**18)")
echo "balance=${BALANCE_RAI} RAI"
```

**Gate**: Need ≥ 2 RAI (1 RAI job fee + gas). If insufficient → warn user.

---

## Step 3: Build Docker Inference Image

### 3.1 Check if image already exists

```bash
IMAGE_EXISTS=$(docker images -q republic-llm-inference:latest 2>/dev/null)
echo "image_exists=${IMAGE_EXISTS:+yes}"
```

**Decision**: If image exists → skip to Step 4. If not → build.

### 3.2 Clone and build

```bash
# Clone devtools if not present
if [ ! -d "/root/devtools" ]; then
  git clone https://github.com/RepublicAI/devtools.git /root/devtools
fi

cd /root/devtools
pip install -e .

# Verify devtools
republic-dev --help

# Build Docker image (10-30 min first time — downloads LLM model)
cd /root/devtools/containers/llm-inference
docker build -t republic-llm-inference:latest .
```

### 3.3 Verify build

```bash
docker images | grep republic-llm-inference
# Must show: republic-llm-inference   latest   <hash>   ...   ~5-10GB
```

**Gate**: Image must exist. If build fails → check Docker disk space, network.

---

## Step 4: Patch inference.py

### KNOWN BUG (verified 2026-03-02)
The official `inference.py` at `github.com/RepublicAI/devtools/main/containers/llm-inference/inference.py`
only writes to `stdout` via `print(json.dumps(result))`. It does NOT write `/output/result.bin`.
The Republic protocol REQUIRES `/output/result.bin` to exist after container execution.

### 4.1 Check if patch already applied

```bash
if [ -f "/root/inference.py" ]; then
  grep -q "result.bin" /root/inference.py && echo "PATCHED" || echo "NOT_PATCHED"
else
  echo "NOT_EXISTS"
fi
```

**Decision**:
- `PATCHED` → skip to Step 5
- `NOT_PATCHED` or `NOT_EXISTS` → apply patch

### 4.2 Extract and patch

```bash
# Extract official file
docker run --rm --entrypoint cat republic-llm-inference:latest /app/inference.py > /root/inference.py

# Apply patch: find the final print line and add file write after it
python3 << 'PATCH_EOF'
import re

with open('/root/inference.py', 'r') as f:
    content = f.read()

# Find: print(json.dumps(result, indent=2))
# Add file write block after the final JSON print
old = '    print(json.dumps(result, indent=2))'
new = '''    result_json = json.dumps(result, indent=2)
    print(result_json)

    # Write to /output/result.bin (Republic protocol requirement)
    output_path = os.getenv("OUTPUT_PATH", "/output/result.bin")
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            f.write(result_json)
        print(f"\\n✓ Result written to {output_path}")
    except Exception as e:
        import sys
        print(f"\\n⚠ Could not write to {output_path}: {e}", file=sys.stderr)'''

content = content.replace(old, new)

with open('/root/inference.py', 'w') as f:
    f.write(content)

print("✓ Patch applied successfully")
PATCH_EOF
```

### 4.3 Verify patch

```bash
grep -c "result.bin" /root/inference.py
# Expected: ≥ 2 (one for OUTPUT_PATH default, one for open())
```

### 4.4 Test patched inference

```bash
mkdir -p /tmp/test-inference
docker run --rm --gpus all \
  -v /tmp/test-inference:/output \
  -v /root/inference.py:/app/inference.py \
  republic-llm-inference:latest

# Validate output
test -f /tmp/test-inference/result.bin && echo "PASS" || echo "FAIL"

# Validate JSON content
python3 -c "import json; json.load(open('/tmp/test-inference/result.bin')); print('JSON_VALID')"

# Cleanup
rm -rf /tmp/test-inference
```

**Gate**: Both checks must return `PASS` and `JSON_VALID`.

---

## Step 5: Setup Result Endpoint

The result endpoint serves `/var/lib/republic/jobs/<JOB_ID>/result.bin` over HTTP.

### 5.1 Create jobs directory

```bash
mkdir -p /var/lib/republic/jobs
```

### 5.2 Get public IP

```bash
PUBLIC_IP=$(curl -s ifconfig.me)
echo "public_ip=$PUBLIC_IP"
```

### 5.3 Create HTTP server systemd service

```bash
cat > /etc/systemd/system/republic-http.service << 'EOF'
[Unit]
Description=Republic Jobs HTTP Server (port 8080)
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/republic/jobs
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now republic-http
```

### 5.4 Validate endpoint

```bash
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/)
echo "http_status=$HTTP_STATUS"
```

**Gate**: Must be `200`. If not → check `systemctl status republic-http`.

### 5.5 Set RESULT_BASE_URL

**Decision logic:**
- If Cloudflare Tunnel is configured → `RESULT_BASE_URL="https://<domain>"`
- If direct IP → `RESULT_BASE_URL="http://$PUBLIC_IP:8080"`

```bash
# For direct IP setup:
RESULT_BASE_URL="http://$PUBLIC_IP:8080"
echo "result_base_url=$RESULT_BASE_URL"
```

### 5.6 (Optional) Cloudflare Tunnel setup

Only if user has a domain on Cloudflare. Agent should ASK user before proceeding.

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb

# Login (requires user interaction — opens browser URL)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create republicai
# Capture TUNNEL_ID from output

# Configure (agent must substitute TUNNEL_ID and DOMAIN)
cat > /root/.cloudflared/config.yml << EOF
tunnel: <TUNNEL_ID>
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: <DOMAIN>
    service: http://localhost:8080
  - service: http_status:404
EOF

# Route DNS
cloudflared tunnel route dns republicai <DOMAIN>

# Create systemd service
cat > /etc/systemd/system/cloudflared.service << 'EOF'
[Unit]
Description=Cloudflare Tunnel for RepublicAI Compute
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /root/.cloudflared/config.yml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudflared
```

---

## Step 6: Deploy Auto-Compute Service

### 6.1 Create auto-compute script

**IMPORTANT**: Agent MUST substitute ALL variables before writing. No placeholders allowed.

```bash
cat > /root/auto-compute.sh << SCRIPT_EOF
#!/bin/bash

WALLET="$WALLET"
VALOPER="$VALOPER"
NODE="$NODE"
CHAIN_ID="$CHAIN_ID"
PASSWORD=""
RESULT_BASE_URL="$RESULT_BASE_URL"
JOBS_DIR="/var/lib/republic/jobs"

echo "🚀 Auto-compute started at \$(date)..."

while true; do
  JOB_IDS=\$(republicd query txs \\
    --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \\
    --node \$NODE -o json 2>/dev/null | \\
    jq -r '.txs[] | select(.tx.body.messages[0].target_validator=="'\$VALOPER'") |
    .events[] | select(.type=="job_submitted") |
    .attributes[] | select(.key=="job_id") | .value')

  for JOB_ID in \$JOB_IDS; do
    RESULT_FILE="\$JOBS_DIR/\$JOB_ID/result.bin"

    if [ -f "\$RESULT_FILE" ]; then
      continue
    fi

    echo "📦 New job found: \$JOB_ID at \$(date)"

    mkdir -p \$JOBS_DIR/\$JOB_ID
    docker run --rm --gpus all \\
      -v \$JOBS_DIR/\$JOB_ID:/output \\
      -v /root/inference.py:/app/inference.py \\
      republic-llm-inference:latest 2>/root/auto-compute-docker.log

    if [ ! -f "\$RESULT_FILE" ]; then
      echo "❌ Inference failed for job \$JOB_ID"
      continue
    fi

    echo "✅ Inference done for job \$JOB_ID"
    SHA256=\$(sha256sum \$RESULT_FILE | awk '{print \$1}')

    echo "\$PASSWORD" | republicd tx computevalidation submit-job-result \\
      \$JOB_ID \\
      \$RESULT_BASE_URL/\$JOB_ID/result.bin \\
      example-verification:latest \\
      \$SHA256 \\
      --from $KEY_NAME \\
      --home /root/.republicd \\
      --chain-id \$CHAIN_ID \\
      --gas 300000 --gas-prices 1000000000arai \\
      --node \$NODE --keyring-backend test \\
      --generate-only 2>/dev/null > /tmp/tx_unsigned.json

    python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('\$WALLET')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
"

    echo "\$PASSWORD" | republicd tx sign /tmp/tx_unsigned.json \\
      --from $KEY_NAME --home /root/.republicd \\
      --chain-id \$CHAIN_ID --node \$NODE \\
      --keyring-backend test \\
      --output-document /tmp/tx_signed.json 2>/dev/null

    TXHASH=\$(republicd tx broadcast /tmp/tx_signed.json \\
      --node \$NODE --chain-id \$CHAIN_ID | grep txhash | awk '{print \$2}')

    echo "🎉 Job \$JOB_ID submitted! TX: \$TXHASH"
  done

  sleep 30
done
SCRIPT_EOF

chmod +x /root/auto-compute.sh
```

### 6.2 Create systemd service

```bash
cat > /etc/systemd/system/republic-autocompute.service << 'EOF'
[Unit]
Description=Republic Auto-Compute Job Processor
After=network-online.target republicd.service
Requires=republicd.service

[Service]
Type=simple
User=root
ExecStart=/root/auto-compute.sh
Restart=always
RestartSec=10
StandardOutput=append:/root/auto-compute.log
StandardError=append:/root/auto-compute.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now republic-autocompute
```

### 6.3 Validate

```bash
systemctl is-active republic-autocompute
# Expected: active
```

---

## Step 7: Deploy Job Sidecar (Committee Verification)

```bash
cat > /etc/systemd/system/republic-sidecar.service << EOF
[Unit]
Description=Republic Compute Job Sidecar
After=network-online.target republicd.service
Requires=republicd.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/republicd tx computevalidation job-sidecar \
  --from $KEY_NAME \
  --work-dir /var/lib/republic/jobs \
  --poll-interval 10s \
  --home /root/.republicd \
  --node $NODE \
  --chain-id $CHAIN_ID \
  --gas auto --gas-adjustment 1.5 \
  --keyring-backend test
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now republic-sidecar
```

### Validate

```bash
systemctl is-active republic-sidecar
# Expected: active
```

---

## Step 8: Deploy Force-Compute Script

```bash
cat > /usr/local/bin/force-compute << SCRIPT_EOF
#!/bin/bash
set -e

JOB_ID=\${1:?Usage: force-compute <JOB_ID>}
WALLET="$WALLET"
NODE="$NODE"
CHAIN_ID="$CHAIN_ID"
RESULT_BASE_URL="$RESULT_BASE_URL"
JOBS_DIR="/var/lib/republic/jobs"
RESULT_FILE="\$JOBS_DIR/\$JOB_ID/result.bin"

echo "🚀 Force-computing job \$JOB_ID..."
mkdir -p "\$JOBS_DIR/\$JOB_ID"

docker run --rm --gpus all \\
  -v "\$JOBS_DIR/\$JOB_ID:/output" \\
  -v /root/inference.py:/app/inference.py \\
  republic-llm-inference:latest 2>/root/auto-compute-docker.log

if [ ! -f "\$RESULT_FILE" ]; then
  echo "❌ Inference failed — no result.bin"
  exit 1
fi

SHA256=\$(sha256sum "\$RESULT_FILE" | awk '{print \$1}')

echo "" | republicd tx computevalidation submit-job-result \\
  "\$JOB_ID" "\$RESULT_BASE_URL/\$JOB_ID/result.bin" \\
  example-verification:latest "\$SHA256" \\
  --from $KEY_NAME --home /root/.republicd \\
  --chain-id "\$CHAIN_ID" --gas 300000 --gas-prices 1000000000arai \\
  --node "\$NODE" --keyring-backend test \\
  --generate-only 2>/dev/null > /tmp/tx_unsigned.json

python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('\$WALLET')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
"

echo "" | republicd tx sign /tmp/tx_unsigned.json \\
  --from $KEY_NAME --home /root/.republicd \\
  --chain-id "\$CHAIN_ID" --node "\$NODE" \\
  --keyring-backend test \\
  --output-document /tmp/tx_signed.json 2>/dev/null

TXHASH=\$(republicd tx broadcast /tmp/tx_signed.json \\
  --node "\$NODE" --chain-id "\$CHAIN_ID" | grep txhash | awk '{print \$2}')

echo "🎉 Job \$JOB_ID submitted! TX: \$TXHASH"
echo "   Hash: \$SHA256"
echo "   URL: \$RESULT_BASE_URL/\$JOB_ID/result.bin"
SCRIPT_EOF

chmod +x /usr/local/bin/force-compute
```

---

## Operations: Submit a Job

### Submit job targeting your own validator

```bash
republicd tx computevalidation submit-job \
  $VALOPER \
  republic-llm-inference:latest \
  $RESULT_BASE_URL/upload \
  $RESULT_BASE_URL \
  example-verification:latest \
  1000000000000000000arai \
  --from $KEY_NAME \
  --home /root/.republicd \
  --chain-id $CHAIN_ID \
  --gas 300000 --gas-prices 1000000000arai \
  --node $NODE \
  --keyring-backend test -y
```

**Cost**: 1 RAI per job (escrowed, returned if job fails).

### Extract job ID from TX

```bash
TX_HASH="<from previous command output>"
JOB_ID=$(republicd query tx $TX_HASH --node $NODE -o json | jq -r '.events[] | select(.type=="job_submitted") | .attributes[] | select(.key=="job_id") | .value')
echo "job_id=$JOB_ID"
```

### Submit job to another validator

```bash
TARGET_VALOPER="<target raivaloper address>"
republicd tx computevalidation submit-job \
  $TARGET_VALOPER \
  republic-llm-inference:latest \
  $RESULT_BASE_URL/upload \
  $RESULT_BASE_URL \
  example-verification:latest \
  1000000000000000000arai \
  --from $KEY_NAME \
  --home /root/.republicd \
  --chain-id $CHAIN_ID \
  --gas auto --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node $NODE \
  --keyring-backend test -y
```

> Only the TARGET validator can process and submit results for that job.

---

## Operations: Query Jobs

### Jobs targeting YOUR validator

```bash
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node $NODE -o json | \
  jq '.txs[] | select(.tx.body.messages[0].target_validator=="'$VALOPER'") |
  .events[] | select(.type=="job_submitted") |
  .attributes[] | select(.key=="job_id") | .value'
```

### ALL jobs on the network

```bash
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node $NODE -o json | \
  jq '.txs[] | .events[] | select(.type=="job_submitted") |
  .attributes[] | select(.key=="job_id") | .value'
```

### Check specific job status

```bash
JOB_ID=<id>
republicd query computevalidation job $JOB_ID --node $NODE -o json | jq '{status, result_hash, result_fetch_endpoint}'
```

### Jobs already submitted (results posted)

```bash
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJobResult'" \
  --node $NODE -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_result_submitted") |
  .attributes[] | select(.key=="job_id") | .value]'
```

### Find UNPROCESSED jobs (not yet submitted)

```bash
# Get submitted results
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJobResult'" \
  --node $NODE -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_result_submitted") |
  .attributes[] | select(.key=="job_id") | .value] | map(tonumber)' > /tmp/submitted.json

# Get all jobs
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node $NODE -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_submitted") |
  .attributes[] | select(.key=="job_id") | .value] | map(tonumber)' > /tmp/all_jobs.json

# Diff
python3 -c "
import json
all_jobs = json.load(open('/tmp/all_jobs.json'))
submitted = json.load(open('/tmp/submitted.json'))
not_submitted = [j for j in all_jobs if j not in submitted]
print('Unprocessed jobs:', not_submitted)
"
```

### Batch-process unprocessed jobs

```bash
for JOB_ID in <space-separated IDs from above>; do
  if [ ! -f "/var/lib/republic/jobs/$JOB_ID/result.bin" ]; then
    echo "Processing Job $JOB_ID..."
    mkdir -p /var/lib/republic/jobs/$JOB_ID
    docker run --rm --gpus all \
      -v /var/lib/republic/jobs/$JOB_ID:/output \
      -v /root/inference.py:/app/inference.py \
      republic-llm-inference:latest
    echo "✅ Job $JOB_ID done!"
  else
    echo "⏭️ Job $JOB_ID already processed, skipping..."
  fi
done
```

---

## Operations: Health Check

Run this to validate the entire stack is operational:

```bash
echo "=== RepublicAI Health Check ==="

# 1. Node sync
SYNC=$(curl -s http://localhost:26657/status | jq -r '.result.sync_info.catching_up')
echo "Node synced: $([ "$SYNC" = "false" ] && echo "✅ YES" || echo "❌ NO")"

# 2. Validator bonded
BOND=$(republicd query staking validator $VALOPER --node $NODE -o json 2>/dev/null | jq -r '.status')
echo "Validator bonded: $([ "$BOND" = "BOND_STATUS_BONDED" ] && echo "✅ YES" || echo "❌ NO ($BOND)")"

# 3. Balance
BAL=$(republicd query bank balances $WALLET --node $NODE -o json | jq -r '.balances[] | select(.denom=="arai") | .amount')
BAL_RAI=$(python3 -c "print(f'{int(\"${BAL:-0}\") / 10**18:.2f}')")
echo "Balance: $BAL_RAI RAI $([ $(python3 -c "print(1 if int('${BAL:-0}') >= 2000000000000000000 else 0)") = "1" ] && echo "✅" || echo "⚠️ LOW")"

# 4. Services
for svc in republicd republic-autocompute republic-http republic-sidecar; do
  STATUS=$(systemctl is-active $svc 2>/dev/null || echo "not-found")
  echo "Service $svc: $([ "$STATUS" = "active" ] && echo "✅ active" || echo "❌ $STATUS")"
done

# 5. HTTP endpoint
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "failed")
echo "HTTP server: $([ "$HTTP" = "200" ] && echo "✅ OK" || echo "❌ HTTP $HTTP")"

# 6. Docker image
IMG=$(docker images -q republic-llm-inference:latest 2>/dev/null)
echo "Docker image: $([ -n "$IMG" ] && echo "✅ exists" || echo "❌ missing")"

# 7. Patched inference.py
PATCH=$(grep -c "result.bin" /root/inference.py 2>/dev/null || echo "0")
echo "inference.py patched: $([ "$PATCH" -ge 2 ] && echo "✅ YES" || echo "❌ NO")"

echo "=== End Health Check ==="
```

**Decision matrix after health check:**
| Check | If FAIL |
|-------|---------|
| Node sync | Wait. Do not proceed with any TX. |
| Validator bonded | Cannot receive jobs. User must bond validator. |
| Balance < 2 RAI | Cannot submit jobs. Need funds. |
| Service down | `systemctl restart <service>` then re-check. |
| HTTP server | Check port conflict: `ss -tlnp | grep 8080` |
| Docker image | Run Step 3 (build). |
| inference.py | Run Step 4 (patch). |

---

## Operations: Send RAI

```bash
# Convert RAI to arai: 1 RAI = 1000000000000000000 arai (10^18)
AMOUNT_RAI=<number>
AMOUNT_ARAI=$(python3 -c "print(int($AMOUNT_RAI * 10**18))")
RECIPIENT="<rai1...address>"

echo "" | republicd tx bank send $KEY_NAME $RECIPIENT ${AMOUNT_ARAI}arai \
  --from $KEY_NAME \
  --home /root/.republicd \
  --chain-id $CHAIN_ID \
  --node $NODE \
  --gas auto --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --keyring-backend test -y
```

### Verify TX

```bash
TX_HASH="<from output>"
sleep 6
republicd query tx $TX_HASH --node $NODE -o json | jq '{code: .code, height: .height}'
# code: 0 = success
```

---

## Troubleshooting Decision Tree

```
Problem: Docker GPU fails
  → Check: docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
  → Fix: Install nvidia-container-toolkit, restart docker

Problem: No result.bin after inference
  → Check: grep "result.bin" /root/inference.py
  → Fix: Re-run Step 4 patch

Problem: submit-job-result bech32 error
  → Cause: Known testnet bug (rai→raivaloper conversion)
  → Fix: Use generate-only → python bech32 fix → sign → broadcast
  → Note: auto-compute.sh handles this automatically

Problem: Job stuck at PendingValidation
  → Cause: Not enough committee members online
  → Action: Normal on testnet. No action needed.

Problem: TX "Out of Gas"
  → Fix: Use --gas auto --gas-adjustment 1.5

Problem: HTTP 404 on result URL
  → Check: ls /var/lib/republic/jobs/<JOB_ID>/result.bin
  → Fix: Run inference for that job first

Problem: Service keeps restarting
  → Check: journalctl -u <service> --no-pager -n 50
  → Common: Wrong KEY_NAME, wrong CHAIN_ID, node not synced
```

---

## Reference

- **Human guide**: `GPU-COMPUTE-GUIDE.md` (same directory)
- **Official docs**: `republicai/docs/compute-provisioning-guide.md` (submodule)
- **Official devtools**: `https://github.com/RepublicAI/devtools`
- **Community reference**: `https://github.com/M4D2510/republic-ai-node`
- **Denomination**: 1 RAI = 10^18 arai
- **Default RPC port**: 26657
- **Default HTTP port**: 8080
- **Docker image**: `republic-llm-inference:latest`
- **Work directory**: `/var/lib/republic/jobs/`
- **Patched file**: `/root/inference.py`
