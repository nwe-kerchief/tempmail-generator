#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Trap errors
trap 'echo -e "${RED}✗ Error on line $LINENO${NC}" >&2' ERR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "  Temp Mail Generator - Auto Installation"
echo "================================================"
echo ""

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
sudo apt update && sudo apt upgrade -y

# Install Python and required packages
echo -e "${YELLOW}[2/10] Installing Python and dependencies...${NC}"
sudo apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx postfix mailutils

# Create mail user
echo -e "${YELLOW}[3/10] Creating mail user...${NC}"
sudo useradd -m -s /bin/bash tempmailuser 2>/dev/null || echo "User already exists"
sudo mkdir -p /var/mail
sudo touch /var/mail/tempmailuser
sudo chown tempmailuser:mail /var/mail/tempmailuser
sudo chmod 660 /var/mail/tempmailuser

# Set up virtual environment
echo -e "${YELLOW}[4/10] Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
echo -e "${YELLOW}[5/10] Installing Python packages...${NC}"
pip install --upgrade pip
pip install -r requirements.txt

# Generate SECRET_KEY if not exists
echo -e "${YELLOW}[6/10] Configuring application...${NC}"
if [ ! -f config.py ]; then
    cp config.py.template config.py
    SECRET_KEY=$(openssl rand -base64 32)
    echo "" >> config.py
    echo "# Flask Secret Key (auto-generated)" >> config.py
    echo "SECRET_KEY = '$SECRET_KEY'" >> config.py
fi

# Update domain in config.py
sed -i "s|yourdomain\.com|$DOMAIN|g" config.py

# Configure Postfix
echo -e "${YELLOW}[7/10] Configuring Postfix...${NC}"

# Create virtual alias file
echo "@$DOMAIN tempmailuser" | sudo tee /etc/postfix/virtual > /dev/null

# Update main.cf
if ! sudo grep -q "virtual_alias_maps" /etc/postfix/main.cf; then
    echo "virtual_alias_maps = hash:/etc/postfix/virtual" | sudo tee -a /etc/postfix/main.cf > /dev/null
fi

if ! sudo grep -q "virtual_alias_domains" /etc/postfix/main.cf; then
    echo "virtual_alias_domains = $DOMAIN" | sudo tee -a /etc/postfix/main.cf > /dev/null
fi

# Security: Prevent backscatter spam
if ! sudo grep -q "smtpd_recipient_restrictions" /etc/postfix/main.cf; then
    cat <<EOF | sudo tee -a /etc/postfix/main.cf > /dev/null
smtpd_recipient_restrictions = 
    permit_mynetworks,
    reject_unauth_destination
EOF
fi

sudo postmap /etc/postfix/virtual
sudo systemctl restart postfix

# Create systemd service
echo -e "${YELLOW}[8/10] Creating systemd service...${NC}"
WORKERS=$((2 * $(nproc) + 1))
sudo tee /etc/systemd/system/tempmail.service > /dev/null <<EOF
[Unit]
Description=Temp Mail Generator
After=network.target

[Service]
User=$(whoami)
Group=$(whoami)
WorkingDirectory=$(pwd)
Environment="PATH=$(pwd)/venv/bin"
ExecStart=$(pwd)/venv/bin/gunicorn --workers $WORKERS \
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

# Setup logging directory
sudo mkdir -p /var/log/tempmail
sudo chown $(whoami):$(whoami) /var/log/tempmail

# Configure Nginx
echo -e "${YELLOW}[9/10] Configuring Nginx...${NC}"
sudo tee /etc/nginx/sites-available/tempmail > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 10M;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/tempmail /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# Start services
echo -e "${YELLOW}[10/10] Starting services...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable tempmail
sudo systemctl start tempmail

# Verify services
echo ""
echo -e "${YELLOW}Verifying services...${NC}"
sleep 2

if systemctl is-active --quiet postfix; then
    echo -e "${GREEN}✓ Postfix is running${NC}"
else
    echo -e "${RED}✗ Postfix failed to start${NC}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✓ Nginx is running${NC}"
else
    echo -e "${RED}✗ Nginx failed to start${NC}"
fi

if systemctl is-active --quiet tempmail; then
    echo -e "${GREEN}✓ Tempmail service is running${NC}"
else
    echo -e "${RED}✗ Tempmail service failed to start${NC}"
    echo "Check logs: sudo journalctl -u tempmail -n 50"
fi

# Test mail delivery
echo ""
echo -e "${YELLOW}Testing mail delivery...${NC}"
echo "Test email from install script" | mail -s "Installation Test" "test@$DOMAIN" 2>/dev/null || true
echo -e "${GREEN}Test email sent to test@$DOMAIN${NC}"
echo "Check /var/mail/tempmailuser in 5 seconds"

echo ""
echo "================================================"
echo -e "${GREEN}✓ Installation Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Set up SSL certificate:"
echo "   sudo certbot --nginx -d $DOMAIN"
echo ""
echo "2. Access your tempmail at:"
echo "   http://$DOMAIN (or https:// after SSL)"
echo ""
echo "3. Check logs:"
echo "   sudo journalctl -u tempmail -f"
echo "   tail -f /var/log/tempmail/error.log"
echo ""
echo "4. Update frontend domain:"
echo "   Edit frontend/index.html and change API URL to: https://$DOMAIN"
echo ""
echo "================================================"

