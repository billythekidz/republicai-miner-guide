# Republic AI Testnet - Complete Setup Guide

## 1. Prerequisites
```bash
sudo apt install htop ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev \
libnss3-dev tmux iptables curl nvme-cli git wget make jq libleveldb-dev \
build-essential pkg-config ncdu tar clang bsdmainutils lsb-release libssl-dev \
libreadline-dev libffi-dev gcc screen file nano btop unzip lz4 patchelf -y
```

## 2. Install Go 1.22.3
```bash
cd $HOME && wget https://go.dev/dl/go1.22.3.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.3.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile
```

## 3. Install Cosmovisor
```bash
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
```

## 4. Install Binary with patchelf (GLIBC fix)
```bash
VERSION="v0.1.0"
mkdir -p $HOME/.republicd/cosmovisor/genesis/bin
curl -L "https://media.githubusercontent.com/media/RepublicAI/networks/main/testnet/releases/${VERSION}/republicd-linux-amd64" -o republicd
chmod +x republicd
patchelf --set-interpreter /opt/glibc-2.39/lib/ld-linux-x86-64.so.2 republicd
patchelf --set-rpath /opt/glibc-2.39/lib republicd
mv republicd $HOME/.republicd/cosmovisor/genesis/bin/
sudo ln -sf $HOME/.republicd/cosmovisor/genesis/bin/republicd /usr/local/bin/republicd
```

## 5. Upgrade Binaries (v0.2.1 & v0.3.0)
```bash
# Chain skips v0.2.1, goes directly to v0.3.0 at block 326,250
for VERSION in v0.2.1 v0.3.0; do
  mkdir -p $HOME/.republicd/cosmovisor/upgrades/${VERSION}/bin
  curl -L "https://media.githubusercontent.com/media/RepublicAI/networks/main/testnet/releases/${VERSION}/republicd-linux-amd64" -o republicd
  chmod +x republicd
  patchelf --set-interpreter /opt/glibc-2.39/lib/ld-linux-x86-64.so.2 republicd
  patchelf --set-rpath /opt/glibc-2.39/lib republicd
  mv republicd $HOME/.republicd/cosmovisor/upgrades/${VERSION}/bin/
done
```

## 6. Initialize Node
```bash
republicd init YOUR_MONIKER --chain-id raitestnet_77701-1 --home $HOME/.republicd
curl -s https://raw.githubusercontent.com/RepublicAI/networks/main/testnet/genesis.json > $HOME/.republicd/config/genesis.json
```

## 7. Configure Peers (RPCdotcom list - 26 peers)
```bash
PEERS="8567f9acbb313978a16b1626fe0e997bbcd97990@162.243.109.138:26656,a02d1c8e9f481f30127ce0ef89c9e490f61a4e2e@38.49.214.70:26656,7e483c0ab1cbf60a1056263903dc3a3269244141@38.49.214.94:26656,38fa0132bd791dddf5a4db7c440af494af9ee3b2@34.61.170.254:26656,67ecda5dfaf5aa5519afdac580c832f0118a730f@62.171.142.162:26656,90cabe6f1bd8bd4eafec781f224cfac725ae5391@152.53.230.81:47656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.republicd/config/config.toml
```

## 8. Configure Ports (prefix 43)
```bash
sed -i 's/:26657/:43657/g' $HOME/.republicd/config/config.toml
sed -i 's/:26656/:43656/g' $HOME/.republicd/config/config.toml
```

## 9. Systemd Service
```bash
sudo tee /etc/systemd/system/republicd.service > /dev/null << EOF2
[Unit]
Description=Republic AI Node
After=network-online.target

[Service]
User=$USER
Environment="DAEMON_NAME=republicd"
Environment="DAEMON_HOME=$HOME/.republicd"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
ExecStart=$HOME/go/bin/cosmovisor run start --home $HOME/.republicd --chain-id raitestnet_77701-1
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF2
sudo systemctl daemon-reload
sudo systemctl enable republicd
sudo systemctl start republicd
```

## 10. Important: Manual Upgrade at Block 326,250
Chain skips v0.2.1 and goes directly to v0.3.0!
```bash
sudo systemctl stop republicd
rm -rf $HOME/.republicd/cosmovisor/current
ln -s $HOME/.republicd/cosmovisor/upgrades/v0.3.0 $HOME/.republicd/cosmovisor/current
sudo systemctl start republicd
```

## 11. Useful Commands
```bash
# Check sync status
republicd status --node tcp://localhost:43657 | jq '.sync_info'

# Check validator status
republicd query staking validator $(republicd keys show wallet --bech val -a --home $HOME/.republicd) --node tcp://localhost:43657

# Unjail (use high gas price!)
republicd tx slashing unjail --from wallet --chain-id raitestnet_77701-1 \
  --gas auto --gas-adjustment 1.5 --gas-prices 1000000000arai \
  --node tcp://localhost:43657 -y
```
