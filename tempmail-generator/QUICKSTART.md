⚡ Quick Start Guide (5 Minutes)

Get your temp mail service running in just 5 minutes!

🚀 One-Command Installation

bashgit clone https://github.com/yourusername/tempmail.git

cd tempmail

chmod +x install.sh

./install.sh

The script will ask for your domain and automatically:



Install all dependencies

Configure mail server

Set up Nginx

Create systemd service

Start the application



📝 Manual Setup (If Script Fails)

Step 1: Install Dependencies (1 min)

bashsudo apt update

sudo apt install -y python3 python3-pip python3-venv nginx postfix

Step 2: Set Up Project (1 min)

bashpython3 -m venv venv

source venv/bin/activate

pip install -r requirements.txt

Step 3: Configure Domain (1 min)

Edit app.py line 266:

pythonreturn jsonify(\['yourdomain.com'])  # Your domain here

Edit frontend/index.html line 313:

javascriptconst API\_URL = 'https://yourdomain.com';  // Your domain here

Step 4: Run Application (1 min)

bashgunicorn -w 4 -b 0.0.0.0:5000 app:app

Visit: http://your-server-ip:5000

Step 5: Production Setup (Optional - 1 min)

bash# Set up SSL

sudo certbot --nginx -d yourdomain.com



\# Create systemd service (see README.md)

sudo systemctl enable tempmail

sudo systemctl start tempmail

✅ Verify Installation



Check if service is running:



bashsudo systemctl status tempmail



Test email reception:



bashecho "Test" | mail -s "Test" test@yourdomain.com



Check mailbox:



bashcat /var/mail/tempmailuser

🆘 Common Issues

Port 5000 already in use

bashsudo lsof -i :5000

sudo kill -9 <PID>

Emails not receiving

bashsudo tail -f /var/log/mail.log

Permission denied on mailbox

bashsudo chown tempmailuser:mail /var/mail/tempmailuser

sudo chmod 660 /var/mail/tempmailuser

🎉 Done!

Your temp mail service is now running at https://yourdomain.com

For detailed configuration, see README.md

