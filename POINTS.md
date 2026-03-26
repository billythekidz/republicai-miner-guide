# Republic AI - Points Portal & Faucet

## Points Portal
https://points.republicai.io

## Get Testnet Tokens (Faucet)
1. Go to https://points.republicai.io
2. Login with your account
3. Request testnet RAI tokens
4. Provide your wallet address: `rai1...`

## Check Balance
```bash
republicd query bank balances YOUR_WALLET_ADDRESS --node tcp://localhost:43657
```

## Delegate to Validator
```bash
republicd tx staking delegate \
  YOUR_VALOPER_ADDRESS \
  AMOUNT_arai \
  --from wallet \
  --home $HOME/.republicd \
  --chain-id raitestnet_77701-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 1000000000arai \
  --node tcp://localhost:43657 \
  -y
```

## Active Set Requirements
- Check minimum bonded validator stake:
```bash
republicd query staking validators --node tcp://localhost:43657 -o json | \
  jq '.validators | map(select(.status=="BOND_STATUS_BONDED")) | sort_by(.tokens | tonumber) | first | {moniker: .description.moniker, tokens: .tokens}'
```
- Delegate enough to exceed the lowest bonded validator
