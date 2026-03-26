# Republic AI Testnet - Troubleshooting Guide

## 1. GLIBC Version Error
**Error:** `version GLIBC_2.32 not found`

**Solution:** Use patchelf to fix binary compatibility
```bash
# Install GLIBC 2.39
wget http://ftp.gnu.org/gnu/glibc/glibc-2.39.tar.gz
tar -xzf glibc-2.39.tar.gz
cd glibc-2.39
mkdir build && cd build
../configure --prefix=/opt/glibc-2.39
make -j$(nproc)
sudo make install

# Patch binary
patchelf --set-interpreter /opt/glibc-2.39/lib/ld-linux-x86-64.so.2 republicd
patchelf --set-rpath /opt/glibc-2.39/lib republicd
```

## 2. Upgrade at Block 326,250 (v0.2.1 Skip)
**Error:** `UPGRADE "v0.3.0" NEEDED at height: 326250`

**Cause:** Chain skips v0.2.1 and goes directly to v0.3.0!
Cosmovisor panics because it can't find upgrade plan.

**Solution:** Manual symlink update
```bash
sudo systemctl stop republicd
rm -rf $HOME/.republicd/cosmovisor/current
ln -s $HOME/.republicd/cosmovisor/upgrades/v0.3.0 $HOME/.republicd/cosmovisor/current
sudo systemctl start republicd
```

## 3. Unjail - Insufficient Fee Error
**Error:** `provided fee < minimum global fee`

**Wrong (too low gas price):**
```bash
--gas-prices 250000000arai  # Too low!
```

**Correct:**
```bash
--gas-prices 1000000000arai  # Use this!
```

## 4. AppHash Mismatch
**Error:** `AppHash mismatch`

**Cause:** Snapshot corruption or wrong binary version

**Solution:** Fresh install from genesis
- Delete all data and reinstall from block 0
- Use v0.1.0 genesis binary
- Let it sync naturally through all upgrades

## 5. Validator Jailed
**Cause:** Node was down too long, missed blocks

**Solution:**
```bash
republicd tx slashing unjail \
  --from wallet \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 -y
```

## 6. TX Indexer Disabled
**Error:** `transaction indexing is disabled`

**Solution:**
```bash
sed -i -e "s/^indexer *=.*/indexer = \"kv\"/" $HOME/.republicd/config/config.toml
sudo systemctl restart republicd
```

## 7. Job Result Submit Error
**Error:** `hrp does not match bech32 prefix: expected 'raivaloper' got 'rai'`

**Cause:** Validator must be BONDED to submit job results.
Wait until validator is bonded, then retry.
