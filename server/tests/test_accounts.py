import pytest
from sqlalchemy import create_engine, event, select

from app.accounts import (
    AccountValidationError,
    DuplicateUsernameError,
    create_user,
)
from app.schema import users
from app.security import verify_password


@pytest.fixture
def user_engine():
    engine = create_engine("sqlite:///:memory:", future=True)

    @event.listens_for(engine, "connect")
    def add_mysql_collation(dbapi_connection, _connection_record):
        dbapi_connection.create_collation(
            "utf8mb4_bin",
            lambda left, right: (left > right) - (left < right),
        )

    users.create(engine)
    try:
        yield engine
    finally:
        users.drop(engine)
        engine.dispose()


def fetch_user(engine, user_id):
    with engine.connect() as connection:
        return (
            connection.execute(select(users).where(users.c.id == user_id))
            .mappings()
            .one()
        )


def test_create_user_inserts_user_with_password_hash_only(user_engine):
    user_id = create_user(user_engine, "alice", "plain-password-value")

    row = fetch_user(user_engine, user_id)

    assert row["id"] == user_id
    assert row["username"] == "alice"
    assert row["password_hash"] != "plain-password-value"
    assert "plain-password-value" not in row["password_hash"]
    assert verify_password("plain-password-value", row["password_hash"]) is True
    assert row["current_revision"] == 0
    assert row["created_at"] is not None
    assert row["updated_at"] is not None


def test_create_user_trims_username(user_engine):
    user_id = create_user(user_engine, "  alice  ", "plain-password-value")

    row = fetch_user(user_engine, user_id)

    assert row["username"] == "alice"


def test_create_user_rejects_duplicate_username(user_engine):
    create_user(user_engine, "alice", "plain-password-value")

    with pytest.raises(DuplicateUsernameError, match="用户名已存在"):
        create_user(user_engine, "alice", "another-password")


@pytest.mark.parametrize("username", ["", "   ", "a" * 192])
def test_create_user_rejects_invalid_username(user_engine, username):
    with pytest.raises(AccountValidationError):
        create_user(user_engine, username, "plain-password-value")


def test_create_user_rejects_empty_password(user_engine):
    with pytest.raises(AccountValidationError, match="密码不能为空"):
        create_user(user_engine, "alice", "")
