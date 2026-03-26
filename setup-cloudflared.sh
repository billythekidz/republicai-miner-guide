#!/bin/bash
# Setup cloudflared as native systemd service pointing to compute HTTP server

# Config file
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml << 'EOF'
tunnel: 2e2b208e-39bd-4144-a1af-fae539659149
ingress:
  - hostname: republicai.devn.cloud
    service: http://localhost:8081
  - service: http_status:404
EOF

# Systemd service
cat > /etc/systemd/system/cloudflared.service << 'EOF'
[Unit]
Description=Cloudflare Tunnel for RepublicAI Compute
After=network-online.target republic-http.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token eyJhIjoiNThjZTllYjg4MTg2NDNlMTA3YmIyNDI0ODdjMDkyZTciLCJ0IjoiMmUyYjIwOGUtMzliZC00MTQ0LWExYWYtZmFlNTM5NjU5MTQ5IiwicyI6Ik1tRXlPR1F4TURRdE1EQmhPUzAwT0dVd0xUazNPVFF0TWpReU9EZGlNV05pTkRNNCJ9
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared.service
systemctl start cloudflared.service
sleep 5
echo "=== Status ==="
systemctl status cloudflared.service --no-pager | head -10
echo ""
echo "=== Logs ==="
journalctl -u cloudflared.service -n 10 --no-pager
