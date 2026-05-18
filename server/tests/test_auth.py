from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.pool import StaticPool

from app.accounts import create_user
from app.api import create_app
from app.auth import TOKEN_TTL, hash_token
from app.config import Settings
from app.schema import session_tokens, users


@pytest.fixture
def auth_context():
    engine = create_engine(
        "sqlite://",
        future=True,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    @event.listens_for(engine, "connect")
    def add_mysql_collation(dbapi_connection, _connection_record):
        dbapi_connection.create_collation(
            "utf8mb4_bin",
            lambda left, right: (left > right) - (left < right),
        )

    users.create(engine)
    session_tokens.create(engine)
    settings = Settings(
        database_url="sqlite://",
        token_secret="test-token-secret",
    )
    client = TestClient(
        create_app(settings=settings, health_checker=lambda: None, engine=engine)
    )

    try:
        yield client, engine, settings
    finally:
        session_tokens.drop(engine)
        users.drop(engine)
        engine.dispose()


def test_login_returns_bearer_token_and_stores_only_hash(auth_context):
    client, engine, settings = auth_context
    user_id = create_user(engine, "alice", "plain-password-value")
    before = _utc_now()

    response = client.post(
        "/auth/login",
        json={"username": "alice", "password": "plain-password-value"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["token"]
    assert body["token_type"] == "bearer"
    assert body["user"] == {
        "id": user_id,
        "username": "alice",
        "current_revision": 0,
    }
    expires_at = datetime.fromisoformat(body["expires_at"])
    assert before + TOKEN_TTL <= expires_at <= _utc_now() + TOKEN_TTL

    token_rows = _fetch_token_rows(engine)
    assert len(token_rows) == 1
    assert token_rows[0]["token_hash"] == hash_token(
        body["token"], settings.token_secret
    )
    assert token_rows[0]["token_hash"] != body["token"]
    assert token_rows[0]["user_id"] == user_id
    assert token_rows[0]["revoked_at"] is None


@pytest.mark.parametrize(
    ("username", "password"),
    [
        ("alice", "wrong-password"),
        ("missing", "plain-password-value"),
    ],
)
def test_login_failure_returns_unified_unauthorized(
    auth_context, username, password
):
    client, engine, _settings = auth_context
    create_user(engine, "alice", "plain-password-value")

    response = client.post(
        "/auth/login",
        json={"username": username, "password": password},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}


def test_me_returns_current_user_with_valid_token(auth_context):
    client, engine, _settings = auth_context
    user_id = create_user(engine, "alice", "plain-password-value")
    login_response = client.post(
        "/auth/login",
        json={"username": "alice", "password": "plain-password-value"},
    )
    token = login_response.json()["token"]

    response = client.get("/auth/me", headers=_auth_header(token))

    assert response.status_code == 200
    body = response.json()
    assert body["user"] == {
        "id": user_id,
        "username": "alice",
        "current_revision": 0,
    }
    assert body["expires_at"] == login_response.json()["expires_at"]


def test_me_without_token_returns_unified_unauthorized(auth_context):
    client, _engine, _settings = auth_context

    response = client.get("/auth/me")

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}


def test_me_with_invalid_token_returns_unified_unauthorized(auth_context):
    client, _engine, _settings = auth_context

    response = client.get("/auth/me", headers=_auth_header("invalid-token"))

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}


@pytest.mark.parametrize(
    ("expires_delta", "revoked"),
    [
        (timedelta(seconds=-1), False),
        (timedelta(days=1), True),
    ],
)
def test_me_with_expired_or_revoked_token_returns_unified_unauthorized(
    auth_context, expires_delta, revoked
):
    client, engine, settings = auth_context
    user_id = create_user(engine, "alice", "plain-password-value")
    token = "stored-token"
    now = _utc_now()
    _insert_token(
        engine=engine,
        settings=settings,
        user_id=user_id,
        token=token,
        created_at=now,
        expires_at=now + expires_delta,
        revoked_at=now if revoked else None,
    )

    response = client.get("/auth/me", headers=_auth_header(token))

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}


def test_logout_revokes_only_current_token(auth_context):
    client, engine, _settings = auth_context
    create_user(engine, "alice", "plain-password-value")
    first_token = _login(client, "alice", "plain-password-value")
    second_token = _login(client, "alice", "plain-password-value")

    response = client.post("/auth/logout", headers=_auth_header(first_token))

    assert response.status_code == 204
    assert response.text == ""
    assert client.get("/auth/me", headers=_auth_header(first_token)).status_code == 401
    assert client.get("/auth/me", headers=_auth_header(second_token)).status_code == 200

    token_rows = _fetch_token_rows(engine)
    revoked_rows = [row for row in token_rows if row["revoked_at"] is not None]
    active_rows = [row for row in token_rows if row["revoked_at"] is None]
    assert len(revoked_rows) == 1
    assert len(active_rows) == 1


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post(
        "/auth/login",
        json={"username": username, "password": password},
    )
    assert response.status_code == 200
    return response.json()["token"]


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _fetch_token_rows(engine):
    with engine.connect() as connection:
        return list(connection.execute(select(session_tokens)).mappings())


def _insert_token(
    engine,
    settings: Settings,
    user_id: str,
    token: str,
    created_at: datetime,
    expires_at: datetime,
    revoked_at: Optional[datetime],
) -> None:
    with engine.begin() as connection:
        connection.execute(
            session_tokens.insert().values(
                id=str(uuid4()),
                user_id=user_id,
                token_hash=hash_token(token, settings.token_secret),
                created_at=created_at,
                expires_at=expires_at,
                revoked_at=revoked_at,
            )
        )


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)
