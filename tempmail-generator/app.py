# ===========================
# app.py - Main Flask Application
# ===========================
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import os
import sqlite3
import secrets
import time
from datetime import datetime
import threading
import mailbox
import email
from email.header import decode_header
import re
import html as html_lib
from contextlib import contextmanager
from werkzeug.middleware.proxy_fix import ProxyFix

# Import configuration
try:
    import config
    DOMAIN = config.DOMAIN
    DB_PATH = config.DB_PATH
    MAILBOX_PATH = config.MAILBOX_PATH
    SECRET_KEY = config.SECRET_KEY
except ImportError:
    print("⚠ Warning: config.py not found, using defaults")
    DOMAIN = 'yourdomain.com'
    DB_PATH = 'data/tempmail.db'
    MAILBOX_PATH = '/var/mail/tempmailuser'
    SECRET_KEY = secrets.token_hex(32)

app = Flask(__name__)
app.secret_key = SECRET_KEY
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
CORS(app)

# Rate limiting
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per hour"],
    storage_uri="memory://"
)


# ===========================
# Database Manager
# ===========================
class Database:
    def __init__(self):
        self.db_path = DB_PATH
        os.makedirs(os.path.dirname(self.db_path) if os.path.dirname(self.db_path) else 'data', exist_ok=True)
        self.init_database()

    @contextmanager
    def connection(self):
        conn = sqlite3.connect(self.db_path, timeout=10.0)
        conn.row_factory = sqlite3.Row
        conn.execute('PRAGMA foreign_keys = ON')
        conn.execute('PRAGMA journal_mode = WAL')  # Better concurrency
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def init_database(self):
        with self.connection() as conn:
            # Emails table
            conn.execute('''
            CREATE TABLE IF NOT EXISTS emails (
                email_address TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                domain TEXT NOT NULL,
                session_id TEXT UNIQUE NOT NULL,
                created_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                last_activity REAL NOT NULL,
                is_active INTEGER DEFAULT 1
            )
            ''')

            # Messages table
            conn.execute('''
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email_address TEXT NOT NULL,
                message_id TEXT UNIQUE NOT NULL,
                subject TEXT,
                sender TEXT,
                body TEXT,
                received_at REAL NOT NULL,
                FOREIGN KEY (email_address) REFERENCES emails(email_address) ON DELETE CASCADE
            )
            ''')

            # Indexes
            conn.execute('CREATE INDEX IF NOT EXISTS idx_email ON messages(email_address)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_session ON emails(session_id)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_expires ON emails(expires_at)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_received ON messages(received_at)')


# ===========================
# Email Manager
# ===========================
class EmailManager:
    def __init__(self, database):
        self.db = database

    def create_email(self, username, domain):
        email_addr = f"{username}@{domain}"
        session_id = secrets.token_urlsafe(32)
        now = time.time()
        expires = now + 3600  # 1 hour

        with self.db.connection() as conn:
            # Check if exists
            existing = conn.execute(
                'SELECT expires_at, is_active FROM emails WHERE email_address = ?',
                (email_addr,)
            ).fetchone()

            if existing and existing['is_active'] and now < existing['expires_at']:
                return None  # Already taken

            # Clean old data if exists
            if existing:
                conn.execute('DELETE FROM emails WHERE email_address = ?', (email_addr,))

            # Create new
            conn.execute('''
            INSERT INTO emails VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ''', (email_addr, username, domain, session_id, now, expires, now))

            print(f"✓ Created: {email_addr}")
            return {'email': email_addr, 'session_id': session_id, 'expires_at': expires}

    def check_available(self, username, domain):
        email_addr = f"{username}@{domain}"
        with self.db.connection() as conn:
            result = conn.execute(
                'SELECT expires_at, is_active FROM emails WHERE email_address = ?',
                (email_addr,)
            ).fetchone()

            if not result:
                return True
            return not (result['is_active'] and time.time() < result['expires_at'])

    def get_messages(self, email_addr, session_id):
        with self.db.connection() as conn:
            # Verify session
            email_data = conn.execute(
                'SELECT session_id, expires_at, is_active FROM emails WHERE email_address = ?',
                (email_addr,)
            ).fetchone()

            if not email_data:
                return []

            if email_data['session_id'] != session_id:
                print(f"✗ Session mismatch for {email_addr}")
                return []

            if not email_data['is_active'] or time.time() > email_data['expires_at']:
                return []

            # Update activity
            conn.execute(
                'UPDATE emails SET last_activity = ? WHERE email_address = ?',
                (time.time(), email_addr)
            )

            # Get messages
            messages = conn.execute('''
            SELECT message_id as id, subject, sender as "from",
                   body, received_at,
                   datetime(received_at, 'unixepoch', 'localtime') as received
            FROM messages
            WHERE email_address = ?
            ORDER BY received_at DESC
            ''', (email_addr,)).fetchall()

            return [dict(msg) for msg in messages]

    def add_message(self, email_addr, msg_data):
        with self.db.connection() as conn:
            # Check if email exists
            email_exists = conn.execute(
                'SELECT 1 FROM emails WHERE email_address = ? AND is_active = 1',
                (email_addr,)
            ).fetchone()

            if not email_exists:
                return False

            # Check duplicate
            exists = conn.execute(
                'SELECT 1 FROM messages WHERE message_id = ?',
                (msg_data['message_id'],)
            ).fetchone()

            if exists:
                return False

            # Insert message
            conn.execute('''
            INSERT INTO messages (email_address, message_id, subject, sender, body, received_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                email_addr,
                msg_data['message_id'],
                msg_data['subject'],
                msg_data['from'],
                msg_data['body'],
                time.time()
            ))

            print(f"✓ Message added: {msg_data['subject'][:50]}")
            return True

    def end_session(self, email_addr, session_id):
        with self.db.connection() as conn:
            # Verify session
            result = conn.execute(
                'SELECT session_id FROM emails WHERE email_address = ?',
                (email_addr,)
            ).fetchone()

            if not result or result['session_id'] != session_id:
                return False

            # Delete everything
            conn.execute('DELETE FROM emails WHERE email_address = ?', (email_addr,))
            print(f"✓ Session ended: {email_addr}")
            return True

    def cleanup_expired(self):
        now = time.time()
        with self.db.connection() as conn:
            # Delete expired emails and inactive sessions
            deleted = conn.execute(
                'DELETE FROM emails WHERE expires_at < ? OR (is_active = 0 AND last_activity < ?)',
                (now, now - 300)
            )
            return deleted.rowcount


# ===========================
# Mailbox Reader
# ===========================
class MailboxReader:
    def __init__(self, email_manager):
        self.em = email_manager
        self.mailbox_path = MAILBOX_PATH

    def read_and_import(self):
        if not os.path.exists(self.mailbox_path):
            return 0

        if os.path.getsize(self.mailbox_path) == 0:
            return 0

        try:
            mbox = mailbox.mbox(self.mailbox_path, create=False)
            imported = 0

            for key in list(mbox.keys()):
                try:
                    msg = mbox[key]

                    # Parse email
                    to_addr = self._extract_email(msg.get('To', ''))
                    from_addr = msg.get('From', '')
                    subject = self._decode_header(msg.get('Subject', 'No Subject'))
                    message_id = msg.get('Message-ID', secrets.token_urlsafe(16))
                    body = self._extract_body(msg)

                    # Add to database
                    if self.em.add_message(to_addr, {
                        'message_id': message_id,
                        'subject': subject,
                        'from': from_addr,
                        'body': body
                    }):
                        imported += 1

                    mbox.discard(key)

                except Exception as e:
                    print(f"✗ Error processing message: {e}")
                    continue

            mbox.close()

            # Clear mailbox
            if imported > 0:
                open(self.mailbox_path, 'w').close()

            return imported

        except Exception as e:
            print(f"✗ Mailbox read error: {e}")
            return 0

    def _extract_email(self, header):
        if '<' in header and '>' in header:
            return header.split('<')[1].split('>')[0].strip()
        return header.strip().replace('"', '').replace("'", '')

    def _decode_header(self, header):
        try:
            decoded = decode_header(header)
            if decoded:
                text, encoding = decoded[0]
                if isinstance(text, bytes):
                    return text.decode(encoding or 'utf-8', errors='ignore')
                return str(text)
        except Exception:
            pass
        return header

    def _extract_body(self, msg):
        body = ''
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode('utf-8', errors='ignore')
                        break
                elif part.get_content_type() == "text/html" and not body:
                    payload = part.get_payload(decode=True)
                    if payload:
                        html = payload.decode('utf-8', errors='ignore')
                        body = self._html_to_text(html)
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                body = payload.decode('utf-8', errors='ignore')

        return body or "No content"

    def _html_to_text(self, html):
        # Remove tags and decode entities
        text = re.sub(r'<[^>]+>', ' ', html)
        text = html_lib.unescape(text)
        text = re.sub(r'\s+', ' ', text).strip()
        return text


# ===========================
# Background Workers
# ===========================
def cleanup_worker(email_manager):
    while True:
        try:
            count = email_manager.cleanup_expired()
            if count > 0:
                print(f"🧹 Cleaned {count} expired items")
            time.sleep(60)
        except Exception as e:
            print(f"✗ Cleanup error: {e}")
            time.sleep(120)


def mailbox_worker(mailbox_reader):
    while True:
        try:
            count = mailbox_reader.read_and_import()
            if count > 0:
                print(f"📧 Imported {count} emails")
            time.sleep(10)
        except Exception as e:
            print(f"✗ Mailbox error: {e}")
            time.sleep(30)


# ===========================
# Initialize
# ===========================
db = Database()
email_manager = EmailManager(db)
mailbox_reader = MailboxReader(email_manager)

# Frontend directory
frontend_dir = os.path.join(os.path.dirname(__file__), 'frontend')


# ===========================
# Routes - Frontend
# ===========================
@app.route('/')
def index():
    return send_from_directory(frontend_dir, 'index.html')


@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(frontend_dir, path)


# ===========================
# Routes - API
# ===========================
@app.route('/api/domains')
def get_domains():
    return jsonify([DOMAIN])


@app.route('/api/email/create', methods=['POST'])
@limiter.limit("10 per minute")
def create_email():
    data = request.get_json()
    username = data.get('username', '').strip()
    domain = data.get('domain', '').strip()

    if not username or not domain:
        return jsonify({'error': 'Username and domain required'}), 400

    if not re.match(r'^[a-zA-Z0-9-]+$', username):
        return jsonify({'error': 'Invalid username format'}), 400

    result = email_manager.create_email(username, domain)
    if not result:
        return jsonify({'error': 'Email already taken'}), 409

    return jsonify({'success': True, **result})


@app.route('/api/email/check')
def check_email():
    username = request.args.get('username', '').strip()
    domain = request.args.get('domain', '').strip()

    if not username or not domain:
        return jsonify({'available': False})

    available = email_manager.check_available(username, domain)
    return jsonify({'available': available})


@app.route('/api/emails')
def get_emails():
    email_addr = request.args.get('address', '').strip()
    session_id = request.args.get('session_id', '')

    if not email_addr:
        return jsonify([])

    messages = email_manager.get_messages(email_addr, session_id)
    return jsonify(messages)


@app.route('/api/session/end', methods=['POST'])
def end_session():
    data = request.get_json()
    email_addr = data.get('email', '').strip()
    session_id = data.get('session_id', '')

    if not email_addr or not session_id:
        return jsonify({'error': 'Email and session required'}), 400

    success = email_manager.end_session(email_addr, session_id)
    if success:
        return jsonify({'success': True})
    return jsonify({'error': 'Session not found'}), 403


@app.route('/api/session/keepalive', methods=['POST'])
def keepalive():
    data = request.get_json()
    session_id = data.get('session_id', '')

    if not session_id:
        return jsonify({'error': 'Session required'}), 400

    # Just acknowledge - activity updated when fetching emails
    return jsonify({'success': True})


@app.route('/api/health')
def health():
    return jsonify({'status': 'ok', 'domain': DOMAIN})


# ===========================
# Start Application
# ===========================
if __name__ == '__main__':
    # Start background threads
    threading.Thread(target=cleanup_worker, args=(email_manager,), daemon=True).start()
    threading.Thread(target=mailbox_worker, args=(mailbox_reader,), daemon=True).start()

    print("=" * 50)
    print("🚀 Temp Mail Server Starting")
    print("=" * 50)
    print(f"📍 Domain: {DOMAIN}")
    print("🌐 Port: 5000")
    print("=" * 50)

    app.run(host='0.0.0.0', port=5000, debug=False)
