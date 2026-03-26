#!/bin/bash
# List all jobs on-chain with their result endpoints
NODE="http://localhost:26657"
JOBS=$(republicd query computevalidation list-job --node $NODE -o json 2>/dev/null)

echo "$JOBS" | jq -r '.jobs[] | "Job \(.id) | \(.status) | validator: \(.target_validator) | fetch: \(.result_fetch_endpoint) | upload: \(.result_upload_endpoint)"'
