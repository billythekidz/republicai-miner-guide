# Republic AI - DevTools Setup

## Prerequisites
Before installing DevTools, make sure:
- ✅ Node is fully synced (catching_up: false)
- ✅ TX indexer is enabled
- ✅ GPU Docker image is built

## Note
Validator must be BONDED only for submitting job results. DevTools can be installed at any time.

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
# Export private key from republicd
republicd keys export wallet --unarmored-hex --unsafe --home $HOME/.republicd

# Import to devtools
republic-dev --rpc http://localhost:43657 --chain-id raitestnet_77701-1 keys import wallet YOUR_PRIVATE_KEY_HEX
```

## Fix: memo parameter bug in CLI
Edit /root/devtools/republic_devtools/cli.py and add memo="" parameter to submit_job() call:
```python
fees=fees,
memo=""
```

## Submit LLM Job
```bash
republic-dev --rpc http://localhost:43657 --chain-id raitestnet_77ול-1 submit-llm \
  --validator YOUR_VALOPER_ADDRESS \
  --from wallet
```

## Notes
- DevTools CLI has a memo parameter bug, fix before using
- TX indexer must be enabled: see TROUBLESHOOTING.md
- For result submission use RESULT-SUBMIT-FIX.md workaround
