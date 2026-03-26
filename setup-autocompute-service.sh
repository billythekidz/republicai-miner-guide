#!/bin/bash
# Create auto-compute systemd service and start it

# Create the service file
cat > /etc/systemd/system/republic-autocompute.service << 'EOF'
[Unit]
Description=Republic Auto-Compute Job Processor
After=network-online.target republicd.service republic-http.service
Requires=republicd.service

[Service]
Type=simple
User=root
ExecStart=/root/auto-compute.sh
Restart=always
RestartSec=30
StandardOutput=append:/root/auto-compute.log
StandardError=append:/root/auto-compute.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable republic-autocompute.service
systemctl start republic-autocompute.service
sleep 3
echo "=== Service Status ==="
systemctl status republic-autocompute.service --no-pager
echo ""
echo "=== Log Output ==="
cat /root/auto-compute.log 2>/dev/null || echo "no log yet"
