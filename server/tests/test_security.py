from app.schema import users
from app.security import HASH_ALGORITHM, hash_password, verify_password


def test_hash_password_returns_versioned_hash_without_plaintext():
    password = "plain-password-value"

    stored_hash = hash_password(password)

    algorithm, iterations, salt, digest = stored_hash.split("$")
    assert algorithm == HASH_ALGORITHM
    assert int(iterations) > 0
    assert len(salt) == 32
    assert len(digest) == 64
    assert password not in stored_hash
    assert len(stored_hash) <= users.c.password_hash.type.length


def test_verify_password_accepts_matching_password():
    password = "plain-password-value"
    stored_hash = hash_password(password)

    assert verify_password(password, stored_hash) is True


def test_verify_password_rejects_wrong_password_and_invalid_hash():
    stored_hash = hash_password("plain-password-value")

    assert verify_password("wrong-password", stored_hash) is False
    assert verify_password("plain-password-value", "invalid-hash") is False
