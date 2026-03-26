# Migrating Republic AI Node to New VPS

## Step 1: Backup on Old Server
```bash
# Backup validator key (CRITICAL!)
cp $HOME/.republicd/config/priv_validator_key.json $HOME/priv_validator_key_BACKUP.json

# Note your node info
republicd status --node tcp://localhost:43657 | jq '.sync_info.latest_block_height'
```

## Step 2: Copy Key to New Server
```bash
# From old server
scp $HOME/priv_validator_key_BACKUP.json root@NEW_SERVER_IP:~/
```

## Step 3: Setup New Server
Follow SETUP.md completely on new server.

## Step 4: Restore Validator Key
```bash
# Before starting node, replace key
cp $HOME/priv_validator_key_BACKUP.json $HOME/.republicd/config/priv_validator_key.json
```

## Step 5: Start Node and Wait for Sync
```bash
sudo systemctl start republicd
# Wait for catching_up: false
watch -n 5 "republicd status --node tcp://localhost:43657 | jq '.sync_info.catching_up'"
```

## Step 6: Stop Old Server
Only stop old server AFTER new server is fully synced!
```bash
# On old server
sudo systemctl stop republicd
```

## Important Notes
- NEVER run two nodes with same validator key simultaneously → double sign = permanent jail!
- Always wait for new server to sync before stopping old one
- priv_validator_key.json = your validator identity, keep it safe!
