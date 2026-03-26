#!/bin/bash
VALOPER="raivaloper1vgjpdewsmvnrdqlk75pmhhae397wghfkfv8zr2"

echo "=== Jobs targeting YOUR validator ==="
republicd query computevalidation list-job --node http://localhost:26657 --output json 2>/dev/null | \
  jq --arg v "$VALOPER" '[.jobs[] | select(.target_validator==$v) | {id, status}]'

echo ""
echo "=== Auto-compute log ==="
tail -20 /root/auto-compute.log 2>/dev/null || echo "no log yet"

echo ""
echo "=== Service status ==="
systemctl is-active republic-autocompute.service
