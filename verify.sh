#!/bin/bash
echo "=== FINAL VERIFICATION ==="
echo "1. Node:"
systemctl is-active republicd.service

echo "2. Validator:"
republicd query staking validator raivaloper1vgjpdewsmvnrdqlk75pmhhae397wghfkfv8zr2 --node http://localhost:26657 --output json 2>/dev/null | jq -r '.validator.status'

echo "3. Docker Image:"
docker images republic-llm-inference --format '{{.Repository}}:{{.Tag}} ({{.Size}})'

echo "4. HTTP Server (8081):"
curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/
echo

echo "5. bech32:"
python3 -c "import bech32; print('OK')"

echo "6. Old sidecar:"
systemctl is-active republic-sidecar.service 2>/dev/null || echo "stopped"

echo "=== ALL CHECKS DONE ==="
