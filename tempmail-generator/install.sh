#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo " Temp Mail Generator - Auto Installation"
echo "================================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}" 
   exit 1
fi

# Get domain from user
echo -e "${YELLOW}Enter your domain name (e.g., tempmail.example.com):${NC}"
read -r DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Domain cannot be empty!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Using domain: $DOMAIN${NC}"
echo ""

# Update system
echo -e "${YELLOW}[1/10] Updating system...${NC}"
apt update && apt upgrade -y

# Install required packages
echo -e "${YELLOW}[2/10] Installing required packages...${NC}"
apt install -y python3 python3-pip python3-venv nginx postfix mailutils certbot python3-certbot-nginx

# Create mail user
echo -e "${YELLOW}[3/10] Creating mail user...${NC}"
useradd -r -s /bin/false tempmailuser 2>/dev/null || true
touch /var/mail/tempmailuser
chown tempmailuser:mail /var/mail/tempmailuser
chmod 660 /var/mail/tempmailuser

# Setup Python virtual environment
echo -e "${YELLOW}[4/10] Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
echo -e "${YELLOW}[5/10] Installing Python packages...${NC}"
pip install --upgrade pip
pip install -r requirements.txt

# Create config.py
echo -e "${YELLOW}[6/10] Creating configuration file...${NC}"
cat > config.py << EOF
import os

# Flask secret key
SECRET_KEY = '$(openssl rand -hex 24)'

# Domain configuration
DOMAIN = '$DOMAIN'

# Rate limit for email creation (requests per minute)
RATE_LIMIT = 10

# Database path
DB_PATH = 'data/tempmail.db'

# Mailbox path (system mailbox location)
MAILBOX_PATH = '/var/mail/tempmailuser'

# Flask settings
DEBUG = False
HOST = '0.0.0.0'
PORT = 5000

# Gunicorn settings
WORKERS = $(nproc)
EOF

# Update frontend API URL
echo -e "${YELLOW}[7/10] Configuring frontend...${NC}"
sed -i "s|const API_URL = .*|const API_URL = 'http://$DOMAIN';|g" frontend/index.html

# Configure Postfix
echo -e "${YELLOW}[8/10] Configuring Postfix...${NC}"
postconf -e "myhostname = $DOMAIN"
postconf -e "mydestination = $DOMAIN, localhost.localdomain, localhost"
postconf -e "home_mailbox = Maildir/"
systemctl restart postfix

# Create systemd service
echo -e "${YELLOW}[9/10] Creating systemd service...${NC}"
cat > /etc/systemd/system/tempmail.service << EOF
[Unit]
Description=Temp Mail Generator
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$(pwd)
Environment="PATH=$(pwd)/venv/bin"
ExecStart=$(pwd)/venv/bin/gunicorn --workers $(nproc) \
    --bind 127.0.0.1:5000 \
    --access-logfile /var/log/tempmail/access.log \
    --error-logfile /var/log/tempmail/error.log \
    --log-level info \
    --timeout 120 \
    app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
mkdir -p /var/log/tempmail
touch /var/log/tempmail/access.log
touch /var/log/tempmail/error.log

# Configure Nginx
echo -e "${YELLOW}[10/10] Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/tempmail << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        root $(pwd)/frontend;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    client_max_body_size 10M;
}
EOF

ln -sf /etc/nginx/sites-available/tempmail /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# Start services
systemctl daemon-reload
systemctl enable tempmail
systemctl start tempmail

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Set up SSL certificate:"
echo "   sudo certbot --nginx -d $DOMAIN"
echo ""
echo "2. Access your tempmail at:"
echo "   http://$DOMAIN"
echo ""
echo "3. Check logs:"
echo "   sudo journalctl -u tempmail -f"
echo "   tail -f /var/log/tempmail/error.log"
echo ""
echo -e "${GREEN}================================================${NC}"
