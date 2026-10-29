import hashlib
import hmac
import secrets


def password_hash(password: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 200_000).hex()
    return f'{salt}${digest}'


def verify_password(password: str, stored: str) -> bool:
    return hmac.compare_digest(password_hash(password, stored.split('$')[0]), stored)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
