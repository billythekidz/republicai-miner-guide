# Republic AI Validator Tips & Tricks

## Query Your Jobs from a Specific Offset

To query all your jobs from job ID 50000 onwards without missing any:

```bash
republicd query computevalidation list-job \
  --node tcp://YOUR_NODE_IP:26657 \
  --limit 100 --offset 50000 \
  -o json | python3 -c "
import sys,json
d=json.load(sys.stdin)
my_address = 'YOUR_WALLET_ADDRESS'
mine = [j for j in d.get('jobs',[]) if my_address in j.get('creator','')]
print('My jobs:', len(mine))
from collections import Counter
print(dict(Counter(j['status'] for j in mine)))
"
Replace YOUR_NODE_IP with your node IP and YOUR_WALLET_ADDRESS with your rai1... address. If running locally use localhost instead.
For the next page, use the next_key from pagination response with --page-key flag.
