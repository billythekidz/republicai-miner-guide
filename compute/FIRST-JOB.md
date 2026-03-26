# Republic AI - Compute Job Guide

## Install DevTools
```bash
git clone https://github.com/RepublicAI/devtools.git
cd devtools
pip install -e .
```

## Check Node Status
```bash
republic-dev --rpc http://localhost:43657 --chain-id raitestnet_77701-1 node-status
```

## Import Wallet Key
```bash
# First export from republicd
republicd keys export wallet --unarmored-hex --unsafe --home $HOME/.republicd

# Import to devtools
republic-dev --rpc http://localhost:43657 --chain-id raitestnet_77701-1 keys import wallet YOUR_PRIVATE_KEY_HEX
```

## Build GPU Docker Image
```bash
cd devtools/containers/llm-inference
docker build -t republic-llm-inference:latest .
```

## Submit a Job
```bash
republicd tx computevalidation submit-job \
  YOUR_VALIDATOR_ADDRESS \
  republic-llm-inference:latest \
  http://YOUR_IP:8080/upload \
  http://YOUR_IP:8080/result \
  example-verification:latest \
  1000000000000000000arai \
  --from wallet \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  -y
```

## Run Inference (GPU)
```bash
mkdir -p /var/lib/republic/jobs/JOB_ID
docker run --rm --gpus all \
  -v /var/lib/republic/jobs/JOB_ID:/output \
  republic-llm-inference:latest
```

## Get Result Hash
```bash
SHA256=$(sha256sum /var/lib/republic/jobs/JOB_ID/result.bin | awk '{print $1}')
echo "Hash: $SHA256"
```

## Start HTTP Server for Result Upload
```bash
cd /var/lib/republic/jobs && python3 -m http.server 8080 &
```

## Submit Job Result
```bash
republicd tx computevalidation submit-job-result \
  JOB_ID \
  http://YOUR_IP:8080/JOB_ID/result.bin \
  example-verification:latest \
  YOUR_SHA256_HASH \
  --from wallet \
  --home $HOME/.republicd \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  -y
```

## Notes
- Validator must be BONDED to submit results
- Job fee: 1 RAI per job
- GPU inference: ~8 seconds (RTX 3090)
- CPU inference: ~77 seconds
