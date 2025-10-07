# Configuration file for Temp Mail
# Copy this to config.py and update with your settings
SECRET_KEY = os.urandom(24).hex()
# Your domain name (will be auto-configured by install.sh)
DOMAIN = 'yourdomain.com'

# API URL (should match your domain)
API_URL = f'https://{DOMAIN}'

# Email expiry time in seconds (default: 1 hour)
EMAIL_EXPIRY = 3600

# Session timeout in seconds (default: 5 minutes of inactivity)
SESSION_TIMEOUT = 300

# Cleanup interval in seconds (default: 60 seconds)
CLEANUP_INTERVAL = 60

# Mailbox check interval in seconds (default: 10 seconds)
MAILBOX_CHECK_INTERVAL = 10

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

# Gunicorn settings (workers will be auto-calculated by install.sh)
WORKERS = 4




