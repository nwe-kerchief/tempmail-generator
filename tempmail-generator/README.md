🚀 Secure Temp Mail Generator

A modern, secure temporary email service with automatic 1-hour expiration. Built with Flask and SQLite.



Show Image

Show Image



✨ Features

Random Email Generator - 800,000+ unique combinations

1-Hour Auto-Expiry - Emails automatically delete after 60 minutes

Real-time Inbox - Auto-refresh every 10 seconds

Session Management - Secure session handling with keepalive

Mobile Responsive - Works perfectly on all devices

HTML Email Support - Extracts readable text from HTML emails

Clean UI - Modern glassmorphism design

📋 Prerequisites

Python 3.8 or higher

A domain name (e.g., yourdomain.com)

Mail server configured (Postfix, Exim, etc.)

Basic knowledge of Linux/server administration

🛠️ Installation

1\. Clone the Repository

bash

git clone https://github.com/yourusername/tempmail.git

cd tempmail

2\. Create Virtual Environment

bash

python3 -m venv venv

source venv/bin/activate  # On Windows: venv\\Scripts\\activate

3\. Install Dependencies

bash

pip install -r requirements.txt

4\. Configure Your Domain

Edit app.py and change the domain:



python

@app.route('/api/domains')

def get\_domains():

&nbsp;   return jsonify(\['yourdomain.com'])  # Change this to your domain

Edit frontend/index.html and update the API URL:



javascript

const API\_URL = 'https://yourdomain.com';  // Change to your domain

5\. Set Up Mail Server

Configure Postfix (Ubuntu/Debian)

bash

\# Install Postfix

sudo apt update

sudo apt install postfix



\# Create mail user

sudo useradd -m -s /bin/bash tempmailuser



\# Set mailbox permissions

sudo mkdir -p /var/mail

sudo chown tempmailuser:mail /var/mail/tempmailuser

sudo chmod 660 /var/mail/tempmailuser

Configure Mail Forwarding

Add to /etc/postfix/main.cf:



virtual\_alias\_maps = hash:/etc/postfix/virtual

Create /etc/postfix/virtual:



@yourdomain.com tempmailuser

Apply changes:



bash

sudo postmap /etc/postfix/virtual

sudo systemctl restart postfix

6\. Run the Application

Development Mode

bash

python app.py

Production Mode with Gunicorn

bash

pip install gunicorn

gunicorn -w 4 -b 0.0.0.0:5000 app:app

7\. Set Up Reverse Proxy (Nginx)

Create /etc/nginx/sites-available/tempmail:



nginx

server {

&nbsp;   listen 80;

&nbsp;   server\_name yourdomain.com;



&nbsp;   location / {

&nbsp;       proxy\_pass http://127.0.0.1:5000;

&nbsp;       proxy\_set\_header Host $host;

&nbsp;       proxy\_set\_header X-Real-IP $remote\_addr;

&nbsp;       proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for;

&nbsp;       proxy\_set\_header X-Forwarded-Proto $scheme;

&nbsp;   }

}

Enable site:



bash

sudo ln -s /etc/nginx/sites-available/tempmail /etc/nginx/sites-enabled/

sudo nginx -t

sudo systemctl restart nginx

8\. Set Up SSL (Let's Encrypt)

bash

sudo apt install certbot python3-certbot-nginx

sudo certbot --nginx -d yourdomain.com

9\. Create Systemd Service

Create /etc/systemd/system/tempmail.service:



ini

\[Unit]

Description=Temp Mail Service

After=network.target



\[Service]

Type=simple

User=tempmailuser

WorkingDirectory=/path/to/tempmail

Environment="PATH=/path/to/tempmail/venv/bin"

ExecStart=/path/to/tempmail/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app

Restart=always



\[Install]

WantedBy=multi-user.target

Enable and start:



bash

sudo systemctl daemon-reload

sudo systemctl enable tempmail

sudo systemctl start tempmail

sudo systemctl status tempmail

📁 Project Structure

tempmail/

├── app.py                 # Main Flask application

├── requirements.txt       # Python dependencies

├── frontend/

│   └── index.html        # Frontend UI

├── data/

│   └── tempmail.db       # SQLite database (auto-created)

└── README.md             # This file

🔧 Configuration Options

Change Email Expiry Time

In app.py, modify the create\_email method:



python

expires = now + 7200  # 2 hours instead of 1

Change Cleanup Interval

In app.py, modify the cleanup\_worker function:



python

time.sleep(30)  # Check every 30 seconds (default: 60)

Change Mailbox Check Interval

In app.py, modify the mailbox\_worker function:



python

time.sleep(5)  # Check every 5 seconds (default: 10)

🐛 Troubleshooting

Emails Not Receiving

Check mail server logs:

bash

sudo tail -f /var/log/mail.log

Test mail delivery:

bash

echo "Test" | mail -s "Test" test@yourdomain.com

Check mailbox permissions:

bash

ls -la /var/mail/tempmailuser

Database Locked Error

Ensure only one instance is running

Check file permissions on data/tempmail.db

Port Already in Use

bash

\# Find process using port 5000

sudo lsof -i :5000

\# Kill the process

sudo kill -9 PID

📊 API Endpoints

Endpoint	Method	Description

/api/domains	GET	Get available domains

/api/email/create	POST	Create new email

/api/email/check	GET	Check availability

/api/emails	GET	Get inbox messages

/api/session/end	POST	End session

/api/session/keepalive	POST	Keep session alive

🔐 Security Features

Secure session IDs using secrets module

SQLite with ACID guarantees

Rate limiting (10 requests/minute for creation)

Session ownership verification

Automatic cleanup of expired data

No permanent data storage

📝 License

MIT License - See LICENSE file for details



👤 Author

Aung Myo Myat Zaw (AMMZ)



🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.



Fork the repository

Create your feature branch (git checkout -b feature/AmazingFeature)

Commit your changes (git commit -m 'Add some AmazingFeature')

Push to the branch (git push origin feature/AmazingFeature)

Open a Pull Request

⭐ Support

If you find this project helpful, please give it a star!



📧 Contact

For questions or support, please open an issue on GitHub.



Note: This is a temporary email service. Do not use for important communications.





