#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "   Temp Mail Generator - Auto Installation"
echo "================================================"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should NOT be run as root${NC}"
   echo "Please run as a normal user with sudo privileges"
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
echo -e "${YELLOW}[1/8] Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

# Install Python and required packages
echo -e "${YELLOW}[2/8] Installing Python and dependencies...${NC}"
sudo apt install -y python3 python3-pip python3-venv nginx certbot python3-certbot-nginx postfix

# Create mail user
echo -e "${YELLOW}[3/8] Creating mail user...${NC}"
sudo useradd -m -s /bin/bash tempmailuser || echo "User already exists"
sudo mkdir -p /var/mail
sudo chown tempmailuser:mail /var/mail/tempmailuser 2>/dev/null || true
sudo chmod 660 /var/mail/tempmailuser 2>/dev/null || true

# Set up virtual environment
echo -e "${YELLOW}[4/8] Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
echo -e "${YELLOW}[5/8] Installing Python packages...${NC}"
pip install -r requirements.txt

# Update domain in files
echo -e "${YELLOW}[6/8] Configuring domain...${NC}"
sed -i "s/yourdomain.com/$DOMAIN/g" frontend/index.html
sed -i "s/yourdomain.com/$DOMAIN/g" app.py
sed -i "s|https://aungmyomyatzaw.mooo.com|https://$DOMAIN|g" frontend/index.html

# Configure Postfix
echo -e "${YELLOW}[7/8] Configuring Postfix...${NC}"

# Create virtual alias file
echo "@$DOMAIN tempmailuser" | sudo tee /etc/postfix/virtual

# Update main.cf if not already configured
if ! sudo grep -q "virtual_alias_maps" /etc/postfix/main.cf; then
    echo "virtual_alias_maps = hash:/etc/postfix/virtual" | sudo tee -a /etc/postfix/main.cf
fi

sudo postmap /etc/postfix/virtual
sudo systemctl restart postfix

# Configure Nginx
echo -e "${YELLOW}[8/8] Configuring Nginx...${NC}"

sudo tee /etc/nginx/sites-available/tempmail > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/tempmail /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

# Create systemd service
CURRENT_DIR=$(pwd)
sudo tee /etc/systemd/system/tempmail.service > /dev/null <<EOF
[Unit]
Description=Temp Mail Service
After=network.target

[Service]
Type=simple
User=tempmailuser
WorkingDirectory=$CURRENT_DIR
Environment="PATH=$CURRENT_DIR/venv/bin"
ExecStart=$CURRENT_DIR/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tempmail
sudo systemctl start tempmail

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Set up SSL certificate:"
echo -e "   ${GREEN}sudo certbot --nginx -d $DOMAIN${NC}"
echo ""
echo "2. Configure DNS A record:"
echo "   Point $DOMAIN to your server IP"
echo ""
echo "3. Test mail delivery:"
echo -e "   ${GREEN}echo 'Test' | mail -s 'Test' test@$DOMAIN${NC}"
echo ""
echo "4. Check service status:"
echo -e "   ${GREEN}sudo systemctl status tempmail${NC}"
echo ""
echo "5. View logs:"
echo -e "   ${GREEN}sudo journalctl -u tempmail -f${NC}"
echo ""
echo "Your temp mail service should now be running at:"
echo -e "${GREEN}http://$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}After setting up SSL, it will be available at:${NC}"
echo -e "${GREEN}https://$DOMAIN${NC}"
echo ""
