#!/usr/bin/env python3
"""Encrypt the dashboard behind a password.

  dashboard.html (plaintext, local only) + login.html  ->  index.html (lock screen + AES-256-GCM ciphertext)

The password lives in .password (local only, never committed). Each build uses a fresh key, which also
signs out remembered devices. Same scheme as Beitna: PBKDF2-SHA256 (310k) wraps a random AES-GCM key.

Usage (uses Beitna's venv for the cryptography package):
  ../Beitna/.venv/bin/python build.py           build index.html
  ../Beitna/.venv/bin/python build.py unpack    restore dashboard.html from index.html (asks for the password)
"""
import base64, getpass, json, os, re, sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

ROOT = os.path.dirname(os.path.abspath(__file__))
ITER = 310_000
path = lambda *p: os.path.join(ROOT, *p)
b64 = lambda b: base64.b64encode(b).decode()


def kek(pw, salt):
    return PBKDF2HMAC(hashes.SHA256(), 32, salt, ITER).derive(pw.encode())


def build():
    pw = open(path('.password'), encoding='utf-8').read().strip()
    app = open(path('dashboard.html'), 'rb').read()
    key, iv, salt, wiv = AESGCM.generate_key(256), os.urandom(12), os.urandom(16), os.urandom(12)
    payload = {'v': 1, 'iter': ITER, 'kid': b64(os.urandom(9)), 'iv': b64(iv), 'ct': b64(AESGCM(key).encrypt(iv, app, None)),
               'salt': b64(salt), 'wiv': b64(wiv), 'key': b64(AESGCM(kek(pw, salt)).encrypt(wiv, key, None))}
    shell = open(path('login.html'), encoding='utf-8').read()
    open(path('index.html'), 'w', encoding='utf-8').write(shell.replace('/*PAYLOAD*/null', json.dumps(payload, separators=(',', ':'))))
    print(f"index.html built ({len(app)//1024} KB dashboard), key {payload['kid']}")


def unpack():
    p = json.loads(re.search(r'const PAYLOAD=(\{.*?\})[,;]', open(path('index.html'), encoding='utf-8').read(), re.S).group(1))
    d = lambda k: base64.b64decode(p[k])
    try:
        key = AESGCM(kek(getpass.getpass('Password: '), d('salt'))).decrypt(d('wiv'), d('key'), None)
    except Exception:
        sys.exit('Wrong password.')
    open(path('dashboard.html'), 'wb').write(AESGCM(key).decrypt(d('iv'), d('ct'), None))
    print('dashboard.html restored')


if __name__ == '__main__':
    unpack() if sys.argv[1:] == ['unpack'] else build()
