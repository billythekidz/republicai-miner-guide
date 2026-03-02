# RepublicAI GPU Compute Job — Complete Setup Guide

> 🤖 **Using an AI agent (Claude, ChatGPT, Cursor, Antigravity, etc.) to set up your miner?**  
> 👉 Follow [**AGENT-COMPUTE-GUIDE.md**](AGENT-COMPUTE-GUIDE.md) instead — it's optimized for agents with auto-resolved variables, validation gates, decision logic, and zero placeholders.

> **Tested & verified on testnet `raitestnet_77701-1`**  
> Last updated: 2026-03-02

This guide walks you through setting up GPU compute jobs for your RepublicAI validator, from scratch to submitting your first job on-chain.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Check Validator Status](#2-check-validator-status)
3. [Build Docker Inference Image](#3-build-docker-inference-image)
4. [Fix inference.py Bug](#4-fix-inferencepy-bug)
5. [Setup Result Endpoint](#5-setup-result-endpoint)
   - [Option A: Direct IP (No Domain)](#option-a-direct-ip-no-domain-needed)
   - [Option B: Cloudflare Tunnel (Recommended)](#option-b-cloudflare-tunnel-recommended)
6. [Setup Auto-Compute Service](#6-setup-auto-compute-service)
7. [Setup Job Sidecar (Committee Verification)](#7-setup-job-sidecar-committee-verification)
8. [Setup Management Scripts](#8-setup-management-scripts)
9. [Submit & Compute Your First Job](#9-submit--compute-your-first-job)
10. [Job Monitoring & Queries](#10-job-monitoring--queries)
11. [Send Job to Another Validator](#11-send-job-to-another-validator)
12. [Troubleshooting](#12-troubleshooting)

---

## Variables — Replace With Your Own

Throughout this guide, replace these placeholders with your values:

| Placeholder | Example | How to find |
|-------------|---------|-------------|
| `<YOUR_WALLET>` | `rai1abc...xyz` | `republicd keys show my-wallet -a` |
| `<YOUR_VALOPER>` | `raivaloper1abc...xyz` | `republicd keys show my-wallet --bech val -a` |
| `<YOUR_RESULT_URL>` | `https://your-domain.com` or `http://YOUR_IP:8080` | Your endpoint (see Step 5) |
| `<YOUR_KEY_NAME>` | `my-wallet` | Name used when creating key |
| `<YOUR_CHAIN_ID>` | `raitestnet_77701-1` | Check with `republicd status` |

---

## 1. Prerequisites

### Software (must be installed)

- **OS**: Ubuntu 22.04 LTS or higher (recommended)
- **Docker Engine**: Version 20.10+ (sidecar uses Docker Socket `/var/run/docker.sock`)
- **NVIDIA GPU & CUDA**: CUDA 11.8+ drivers with `nvidia-container-toolkit`
- **Republic Core Utils**: `pip install republic-core-utils`

```bash
# Verify each
republicd version --long     # Republic node binary
docker --version             # Docker 20.10+
nvidia-smi                   # NVIDIA driver + CUDA
jq --version                 # JSON processor
pip install bech32           # Bech32 encoding library (for TX workaround)
pip install republic-core-utils  # Capacity benchmarking
```

### NVIDIA Docker Runtime
```bash
# Test GPU access in Docker
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

If this fails, install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).

---

## 2. Check Validator Status

> **Validator Status & Capabilities:**
>
> | Status | Submit Jobs | Run Compute | Submit Results On-Chain |
> |--------|:-----------:|:-----------:|:----------------------:|
> | **Bonded** | ✅ | ✅ | ✅ |
> | **Unbonded** | ✅ | ✅ | ❌ |
>
> You can add jobs and run GPU compute with **any validator status** (just need 1 RAI per job).
> However, **only bonded validators** (top 100 by delegated RAI) can submit compute results to the chain.
> Bonded status is determined by delegation ranking, not a validator setting.

```bash
# Check your validator status
republicd query staking validator <YOUR_VALOPER> \
  --node http://localhost:26657 -o json | jq '.status'
# BOND_STATUS_BONDED = can submit results on-chain
# BOND_STATUS_UNBONDED = can add jobs & compute, but cannot submit results

# Check if node is synced
curl -s http://localhost:26657/status | jq '.result.sync_info.catching_up'
# Expected: false

# Check wallet balance (need RAI for gas + job fees)
republicd query bank balances <YOUR_WALLET> \
  --node http://localhost:26657 -o json | jq '.balances'
# Need at least 2 RAI (1 RAI per job fee + gas)
```

> ⚠️ **To submit results on-chain**, your validator must be bonded:
> ```bash
> republicd tx staking create-validator ... # See Republic validator docs
> ```

---

## 3. Build Docker Inference Image

### Install Republic DevTools

```bash
git clone https://github.com/RepublicAI/devtools.git
cd devtools
pip install -e .

# Verify devtools
republic-dev --help
```

### Build the Docker image

```bash
cd devtools/containers/llm-inference

# Build (this downloads the LLM model — may take 10-30 min first time)
docker build -t republic-llm-inference:latest .

# Verify image exists
docker images | grep republic-llm-inference
# Expected: republic-llm-inference   latest   abc123   ...   ~5-10GB
```

### Test Docker run (without mount)

```bash
# Create a test output directory
mkdir -p /tmp/test-docker

# Run inference with GPU
docker run --rm --gpus all \
  -v /tmp/test-docker:/output \
  republic-llm-inference:latest

# Check output — with the original image, result.bin will NOT exist
# (this is the known bug we fix in Step 4)
ls -la /tmp/test-docker/
# You'll see nothing in /output — only stdout has the JSON result

# Cleanup
rm -rf /tmp/test-docker
```

> ⏱ **Performance**: GPU inference takes ~8 seconds on RTX 3090, ~77 seconds on CPU.

---

## 4. Fix inference.py Bug & Mount into Container

> **Known Bug**: The official Docker image's [inference.py](https://github.com/RepublicAI/devtools/blob/main/containers/llm-inference/inference.py) only writes output to stdout, not to `/output/result.bin` as the protocol expects.
>
> **Solution**: Extract → patch → mount the fixed file into the container at runtime.
>
> **Official source**: [RepublicAI/devtools/containers/llm-inference](https://github.com/RepublicAI/devtools/tree/main/containers/llm-inference)

### Option 1: Auto-patch (recommended)

Use the included `patch-inference.sh` script:

```bash
# From the scripts/ folder of this guide
bash scripts/patch-inference.sh
```

This will:
1. Extract the official `inference.py` from the Docker image
2. Auto-apply the `/output/result.bin` write patch
3. Save the patched file to `/root/inference.py`

### Option 2: Manual patch

```bash
# Step 1: Extract official file from Docker image
docker run --rm --entrypoint cat republic-llm-inference:latest /app/inference.py > /root/inference.py
```

Then edit `/root/inference.py` — find this line near the end:
```python
    print(json.dumps(result, indent=2))
```

Replace it with:
```python
    result_json = json.dumps(result, indent=2)
    print(result_json)
    
    # Write to /output/result.bin (for sidecar compatibility)
    output_path = os.getenv("OUTPUT_PATH", "/output/result.bin")
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            f.write(result_json)
        print(f"\n✓ Result written to {output_path}")
    except Exception as e:
        import sys
        print(f"\n⚠ Could not write to {output_path}: {e}", file=sys.stderr)
```

### How mounting works

Instead of rebuilding the Docker image, we mount our patched file **over** the original:

```bash
docker run --rm --gpus all \
  -v /var/lib/republic/jobs/<JOB_ID>:/output \
  -v /root/inference.py:/app/inference.py \
  republic-llm-inference:latest
```

**Breakdown of flags:**
| Flag | Purpose |
|------|---------|
| `--rm` | Auto-remove container after it exits |
| `--gpus all` | Give container access to all NVIDIA GPUs |
| `-v /var/lib/republic/jobs/<JOB_ID>:/output` | Mount host job directory → container's `/output` (where `result.bin` gets written) |
| `-v /root/inference.py:/app/inference.py` | Mount patched inference.py over the original inside the container |

> **Why mount instead of rebuild?** Mounting `/root/inference.py:/app/inference.py` lets you adjust the inference script (change model, params, prompts) without rebuilding the Docker image each time.

### Test the fix

```bash
mkdir -p /tmp/test-inference
docker run --rm --gpus all \
  -v /tmp/test-inference:/output \
  -v /root/inference.py:/app/inference.py \
  republic-llm-inference:latest

# Verify output file was created
ls -la /tmp/test-inference/result.bin
# Should show a file ~1-3KB with JSON content

cat /tmp/test-inference/result.bin
# Should show JSON like: {"choices": [{"text": "..."}], ...}

# Cleanup
rm -rf /tmp/test-inference
```

---

## 5. Setup Result Endpoint

The `submit-job-result` TX requires a `result_fetch_endpoint` URL. Start a simple HTTP file server:

```bash
mkdir -p /var/lib/republic/jobs

# Find your public IP
curl -s ifconfig.me
# Or visit: https://whatismyip.com

# Start HTTP file server
cd /var/lib/republic/jobs && python3 -m http.server 8080

# Or install as service (see scripts/setup-http-server.sh)
```

Your result URL: `http://<YOUR_PUBLIC_IP>:8080/<JOB_ID>/result.bin`

> **Note**: Port `8080` is the default. If it conflicts with another service, change it to any available port (e.g., `8081`, `9090`) in all configs.

> **For public access**, you'll need the endpoint reachable from the internet. See [Appendix A: Endpoint Setup Details](#appendix-a-endpoint-setup-details) for:
> - **Option A**: Direct IP — port forwarding, firewall, NAT (free, no domain)
> - **Option B**: Cloudflare Tunnel — free HTTPS, no port forwarding (recommended)

---

## 6. Setup Auto-Compute Service

The auto-compute script polls for new jobs, runs GPU inference, and submits results on-chain automatically.

> **Why auto-compute instead of the official sidecar?**  
> The official `job-sidecar` has two known testnet bugs:
> 1. `inference.py` doesn't write to `/output/result.bin` (fix in Step 4)
> 2. `submit-job-result` crashes on `rai → raivaloper` bech32 conversion
>
> Auto-compute works around both issues.

### Create the script

Create `/root/auto-compute.sh`:

```bash
#!/bin/bash

WALLET="<YOUR_WALLET>"
VALOPER="<YOUR_VALOPER>"
NODE="tcp://localhost:26657"
CHAIN_ID="<YOUR_CHAIN_ID>"
PASSWORD=""
RESULT_BASE_URL="<YOUR_RESULT_URL>"
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
    # Mount external inference.py for easy adjustment
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

    # Generate unsigned TX
    echo "$PASSWORD" | republicd tx computevalidation submit-job-result \
      $JOB_ID \
      $RESULT_BASE_URL/$JOB_ID/result.bin \
      example-verification:latest \
      $SHA256 \
      --from <YOUR_KEY_NAME> \
      --home /root/.republicd \
      --chain-id $CHAIN_ID \
      --gas 300000 \
      --gas-prices 1000000000arai \
      --node $NODE \
      --keyring-backend test \
      --generate-only 2>/dev/null > /tmp/tx_unsigned.json

    # Fix bech32 validator address bug
    python3 -c "
import bech32, json
tx = json.load(open('/tmp/tx_unsigned.json'))
_, data = bech32.bech32_decode('$WALLET')
valoper = bech32.bech32_encode('raivaloper', data)
tx['body']['messages'][0]['validator'] = valoper
json.dump(tx, open('/tmp/tx_unsigned.json', 'w'))
"

    # Sign TX
    echo "$PASSWORD" | republicd tx sign /tmp/tx_unsigned.json \
      --from <YOUR_KEY_NAME> \
      --home /root/.republicd \
      --chain-id $CHAIN_ID \
      --node $NODE \
      --keyring-backend test \
      --output-document /tmp/tx_signed.json 2>/dev/null

    # Broadcast TX
    TXHASH=$(republicd tx broadcast /tmp/tx_signed.json \
      --node $NODE \
      --chain-id $CHAIN_ID | grep txhash | awk '{print $2}')

    echo "🎉 Job $JOB_ID submitted! TX: $TXHASH"
  done

  sleep 30
done
```

### Create systemd service

```bash
chmod +x /root/auto-compute.sh

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

### Create HTTP server service

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

---

## 7. Setup Job Sidecar (Committee Verification)

The official sidecar handles **committee verification** — voting on other validators' jobs. Run it alongside auto-compute:

```bash
cat > /etc/systemd/system/republic-sidecar.service << 'EOF'
[Unit]
Description=Republic Compute Job Sidecar
After=network-online.target republicd.service
Requires=republicd.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/republicd tx computevalidation job-sidecar \
  --from <YOUR_KEY_NAME> \
  --work-dir /var/lib/republic/jobs \
  --poll-interval 10s \
  --home /root/.republicd \
  --node tcp://localhost:26657 \
  --chain-id <YOUR_CHAIN_ID> \
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

**Critical flags** (from [official guide](https://github.com/RepublicAI/networks/blob/main/docs/compute-provisioning-guide.md)):
- `--work-dir`: Where containers mount results. Use fast NVMe storage — HDD will bottleneck throughput.
- `--poll-interval`: How often to check for new jobs. Setting >60s may cause missed jobs in high traffic.
- `--node`: Point to a low-latency RPC (local node or `https://rpc.republicai.io`).

### How both work together:

| Service | Role | Handles |
|---------|------|---------|
| **auto-compute** | Mining | YOUR jobs → GPU inference → submit result |
| **sidecar** | Committee | OTHER validators' jobs → download → verify → vote |

---

## 8. Setup Management Scripts

### Force-Compute Script

For manually computing a specific job immediately (no waiting for auto-compute poll):

Create `/usr/local/bin/force-compute`:

```bash
#!/bin/bash
# Usage: force-compute <JOB_ID>

set -e

JOB_ID=${1:?Usage: force-compute <JOB_ID>}
WALLET="<YOUR_WALLET>"
NODE="tcp://localhost:26657"
CHAIN_ID="<YOUR_CHAIN_ID>"
RESULT_BASE_URL="<YOUR_RESULT_URL>"
JOBS_DIR="/var/lib/republic/jobs"
RESULT_FILE="$JOBS_DIR/$JOB_ID/result.bin"

echo "🚀 Force-computing job $JOB_ID..."

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
SHA256=$(sha256sum "$RESULT_FILE" | awk '{print $1}')
echo "🔑 SHA256: $SHA256"
echo "📡 Submitting result on-chain..."

echo "" | republicd tx computevalidation submit-job-result \
  "$JOB_ID" "$RESULT_BASE_URL/$JOB_ID/result.bin" \
  example-verification:latest "$SHA256" \
  --from <YOUR_KEY_NAME> --home /root/.republicd \
  --chain-id "$CHAIN_ID" --gas 300000 --gas-prices 1000000000arai \
  --node "$NODE" --keyring-backend test \
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
  --from <YOUR_KEY_NAME> --home /root/.republicd \
  --chain-id "$CHAIN_ID" --node "$NODE" \
  --keyring-backend test \
  --output-document /tmp/tx_signed.json 2>/dev/null

TXHASH=$(republicd tx broadcast /tmp/tx_signed.json \
  --node "$NODE" --chain-id "$CHAIN_ID" | grep txhash | awk '{print $2}')

echo ""
echo "🎉 Job $JOB_ID submitted!"
echo "   TX: $TXHASH"
echo "   Hash: $SHA256"
echo "   URL: $RESULT_BASE_URL/$JOB_ID/result.bin"
```

```bash
chmod +x /usr/local/bin/force-compute
```

---

## 9. Submit & Compute Your First Job

### Step 1: Submit a job targeting yourself

```bash
republicd tx computevalidation submit-job \
  <YOUR_VALOPER> \
  republic-llm-inference:latest \
  <YOUR_RESULT_URL>/upload \
  <YOUR_RESULT_URL> \
  example-verification:latest \
  1000000000000000000arai \
  --from <YOUR_KEY_NAME> \
  --home /root/.republicd \
  --chain-id <YOUR_CHAIN_ID> \
  --gas 300000 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:26657 \
  --keyring-backend test -y
```

> 💰 **Cost**: 1 RAI per job (escrowed, returned if job fails)

### Step 2: Find your job ID

```bash
# From the TX hash in the output
republicd query tx <TX_HASH> --node http://localhost:26657 | grep -A1 job_id
```

### Step 3: Force-compute it (or wait for auto-compute)

```bash
# Option 1: Force-compute immediately
force-compute <JOB_ID>

# Option 2: Wait for auto-compute (polls every 30s)
tail -f /root/auto-compute.log
```

### Step 4: Batch-process multiple jobs at once

If you have several unprocessed jobs, process them in a loop:

```bash
for JOB_ID in 10 11 12 13; do
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

> **Tip**: Replace the hardcoded IDs with unprocessed job IDs from Section 10 queries below.

---

## 10. Job Monitoring & Queries

### Verify a specific job on-chain

```bash
# Check job status
republicd query computevalidation job <JOB_ID> --node http://localhost:26657

# Expected fields:
#   status: PendingValidation  (result submitted, waiting for committee)
#   result_hash: <sha256>      (matches your result.bin)
#   result_fetch_endpoint: <your_url>/<JOB_ID>/result.bin

# Verify result is accessible
curl -s -o /dev/null -w "HTTP %{http_code}" <YOUR_RESULT_URL>/<JOB_ID>/result.bin
# Expected: HTTP 200
```

### Find jobs targeting YOUR validator

```bash
# Jobs targeting you (both self-submitted and from others)
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node tcp://localhost:26657 -o json | \
  jq '.txs[] | select(.tx.body.messages[0].target_validator=="<YOUR_VALOPER>") | 
  .events[] | select(.type=="job_submitted") | 
  .attributes[] | select(.key=="job_id") | .value'
```

### See ALL jobs on the network

```bash
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node tcp://localhost:26657 -o json | \
  jq '.txs[] | .events[] | select(.type=="job_submitted") | 
  .attributes[] | select(.key=="job_id") | .value'
```

### Check all jobs targeting you (via module query)

```bash
republicd query computevalidation list-job \
  --node http://localhost:26657 -o json | \
  jq '.jobs[] | select(.target_validator=="<YOUR_VALOPER>") | {id, status}'
```

### Check if a job result has been submitted already

```bash
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJobResult'" \
  --node tcp://localhost:26657 -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_result_submitted") | 
  .attributes[] | select(.key=="job_id") | .value]'
```

### Find unprocessed jobs (not yet submitted)

This compares all submitted jobs vs all jobs to find what's still pending:

```bash
# Get list of already-submitted job results
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJobResult'" \
  --node tcp://localhost:26657 -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_result_submitted") | 
  .attributes[] | select(.key=="job_id") | .value] | map(tonumber)' > /tmp/submitted.json

# Get list of all jobs
republicd query txs \
  --query "message.action='/republic.computevalidation.v1.MsgSubmitJob'" \
  --node tcp://localhost:26657 -o json | \
  jq '[.txs[] | .events[] | select(.type=="job_submitted") | 
  .attributes[] | select(.key=="job_id") | .value] | map(tonumber)' > /tmp/all_jobs.json

# Compare to find unprocessed
python3 -c "
import json
all_jobs = json.load(open('/tmp/all_jobs.json'))
submitted = json.load(open('/tmp/submitted.json'))
not_submitted = [j for j in all_jobs if j not in submitted]
print('Unprocessed jobs:', not_submitted)
"
```

> **Tip**: Use the unprocessed job IDs with the batch-process loop in Step 9.4 above.

---

## 11. Send Job to Another Validator

You can send a compute job to **any validator** on the network by using their `raivaloper` address:

```bash
republicd tx computevalidation submit-job \
  <TARGET_VALOPER_ADDRESS> \
  republic-llm-inference:latest \
  <YOUR_RESULT_URL>/upload \
  <YOUR_RESULT_URL> \
  example-verification:latest \
  1000000000000000000arai \
  --from <YOUR_KEY_NAME> \
  --home /root/.republicd \
  --chain-id <YOUR_CHAIN_ID> \
  --gas auto --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:26657 \
  --keyring-backend test -y
```

> **Important notes:**
> - Replace `<TARGET_VALOPER_ADDRESS>` with the target validator's `raivaloper...` address
> - The upload and fetch endpoints must be hosted on **YOUR** server
> - Only the **target validator** can process and submit the result for that job
> - Fee: **1 RAI** per job (escrowed on-chain)
> - The target validator can be bonded or unbonded to receive and compute jobs, but must be **BONDED** to submit results on-chain

---

## 12. Troubleshooting

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `docker: Error response from daemon: could not select device driver "" with capabilities: [[gpu]]` | NVIDIA Container Toolkit not installed | Install [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) |
| Inference completes but no `result.bin` | Original `inference.py` bug | Mount patched version (Step 4) |
| `submit-job-result` fails with bech32 error | Known testnet bug | Use generate-only → fix → sign → broadcast workaround (auto-compute handles this) |
| Job stuck at `PendingValidation` | No committee assigned | Normal if few active validators on the network |
| `dial tcp <IP>:8080: i/o timeout` in sidecar logs | Other validator's endpoint is down | Not your fault — their file server is offline |
| HTTP 404 on result URL | Job directory doesn't exist | Check `/var/lib/republic/jobs/<JOB_ID>/result.bin` exists |
| "Image not found" | Execution image is in a private registry or not pushed | Ensure you can manually `docker pull` the image on your server |
| "Verification Mismatch (Hash Error)" | File corrupted during upload or wrong hashing | Check `work-dir` logs — sidecar logs computed hash vs on-chain hash |
| "Non-Deterministic Verification" | Verification image uses `time.now()`, random seeds, or network calls | Verification images **MUST** be deterministic — same input = same output |
| "Out of Gas" | Network busy, gas too low | Use `--gas auto --gas-adjustment 1.5` in sidecar flags |

### Quick Health Check

```bash
# Node synced?
curl -s http://localhost:26657/status | jq '.result.sync_info.catching_up'

# HTTP server running?
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/

# Auto-compute running?
systemctl is-active republic-autocompute

# Latest auto-compute log
tail -20 /root/auto-compute.log

# Wallet balance
republicd query bank balances <YOUR_WALLET> \
  --node http://localhost:26657 -o json | jq '.balances'
```

### Service Management

```bash
# Check all services
systemctl is-active republicd republic-sidecar republic-autocompute republic-http cloudflared

# Restart a service
systemctl restart republic-autocompute

# View logs
journalctl -u republic-autocompute --no-pager -n 50
journalctl -u republic-sidecar --no-pager -n 50
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   RepublicAI Node                       │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │republicd │    │ auto-compute │    │  job-sidecar  │  │
│  │ (chain)  │◄───│  (mining)    │    │ (committee)   │  │
│  └──────────┘    └──────┬───────┘    └──────────────┘  │
│                         │                               │
│                   ┌─────▼─────┐                        │
│                   │  Docker   │                        │
│                   │  GPU      │                        │
│                   │ inference │                        │
│                   └─────┬─────┘                        │
│                         │                               │
│                   ┌─────▼─────┐    ┌──────────────┐    │
│                   │ /var/lib/ │    │ HTTP Server  │    │
│                   │ republic/ │───►│   :8080      │    │
│                   │ jobs/     │    └──────┬───────┘    │
│                   └───────────┘           │            │
│                                    ┌─────▼─────┐      │
│                                    │ Cloudflare │      │
│                                    │  Tunnel    │      │
│                                    │  (HTTPS)   │      │
│                                    └───────────┘      │
└─────────────────────────────────────────────────────────┘
```

---

## Job Lifecycle

```
Phase 1: Submission (On-Chain)
  → Requester broadcasts MsgSubmitJob
  → Fee escrowed, Job ID assigned
  → Status: PendingExecution

Phase 2: Discovery & Execution (Off-Chain)
  → Sidecar/auto-compute detects job targeting your validator
  → Pulls execution container, maps /output to NVMe storage
  → Container runs and produces /output/result.bin

Phase 3: Reporting & Commitment (On-Chain)
  → Upload result.bin to ResultUploadEndpoint
  → Compute SHA-256 hash (the "commitment")
  → Submit MsgSubmitJobResult → Status: PendingValidation

Phase 4: Verification (Off-Chain)
  → Committee members download result.bin from ResultFetchEndpoint
  → Verify hash matches → Run VerificationImage
  → If stdout emits "True" → vote true

Phase 5: Settlement (On-Chain)
  → If true votes win  → Fee released to miner (Succeeded)
  → If false votes win → Fee refunded to requester (Failed)
  → Job archived, committee released
```

---

## References

- [Republic Compute Provisioning Guide](https://github.com/RepublicAI/networks/blob/main/docs/compute-provisioning-guide.md)
- [Republic Devtools (Docker images)](https://github.com/RepublicAI/devtools)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

---
---

# Appendix A: Endpoint Setup Details

When committee verification goes live, your `result.bin` must be downloadable from the internet. Two options:

## Option A: Direct IP (No Domain Needed)

**Pros**: Free, no domain needed  
**Cons**: Complex setup (port forwarding, firewall, NAT), HTTP only (no HTTPS), prone to errors

### Step 1: Open ports on your machine

```bash
# UFW firewall (Ubuntu)
sudo ufw allow 8080/tcp

# OR iptables
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

### Step 2: Port forwarding on router/modem

1. Login to your router admin panel (usually `192.168.1.1`)
2. Find **Port Forwarding** / **NAT** / **Virtual Server** settings
3. Add rule:
   - **External Port**: 8080
   - **Internal IP**: Your machine's LAN IP (e.g., `192.168.1.100`)
   - **Internal Port**: 8080
   - **Protocol**: TCP
4. Save and restart router if needed

### Step 3: Verify external access

```bash
# Find your public IP
curl ifconfig.me

# Test from outside your network (use phone data or ask a friend)
curl http://<YOUR_PUBLIC_IP>:8080/
```

> ⚠️ **Warning**: Your IP may change if you don't have a static IP. Consider using DDNS.  
> ⚠️ **Security**: `python3 -m http.server` is READ-ONLY — no one can upload/delete files.

**Your result URL format**: `http://<YOUR_PUBLIC_IP>:8080/<JOB_ID>/result.bin`

---

## Option B: Cloudflare Tunnel (Recommended)

**Pros**: Free HTTPS, no port forwarding needed, DDoS protection, works behind any NAT  
**Cons**: Requires a domain on Cloudflare

### Step 1: Install cloudflared

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb
cloudflared --version
```

### Step 2: Login to Cloudflare

```bash
cloudflared tunnel login
# Opens a browser URL — click to authorize your domain
# Certificate saved to ~/.cloudflared/cert.pem
```

### Step 3: Create tunnel

```bash
cloudflared tunnel create republicai
# Note the tunnel ID (UUID) from output
```

### Step 4: Configure tunnel

```bash
cat > /root/.cloudflared/config.yml << 'EOF'
tunnel: <YOUR_TUNNEL_ID>
credentials-file: /root/.cloudflared/<YOUR_TUNNEL_ID>.json

ingress:
  - hostname: compute.yourdomain.com
    service: http://localhost:8080
  - service: http_status:404
EOF
```

### Step 5: Route DNS

```bash
cloudflared tunnel route dns republicai compute.yourdomain.com
```

### Step 6: Create systemd service

```bash
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

### Step 7: Verify

```bash
systemctl status cloudflared
curl https://compute.yourdomain.com/
```

**Your result URL format**: `https://compute.yourdomain.com/<JOB_ID>/result.bin`

> Or use the interactive setup script: `bash scripts/setup-cloudflared.sh`
