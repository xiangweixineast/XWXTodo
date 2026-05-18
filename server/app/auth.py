from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import secrets
from uuid import uuid4

from sqlalchemy import select, update
from sqlalchemy.engine import Engine

from app.schema import session_tokens, users
from app.security import verify_password

TOKEN_TTL = timedelta(days=30)
TOKEN_TYPE = "bearer"
UNAUTHORIZED_DETAIL = "unauthorized"


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class UnauthorizedError(Exception):
    pass


@dataclass(frozen=True)
class AuthUser:
    id: str
    username: str
    current_revision: int


@dataclass(frozen=True)
class AuthSession:
    token_hash: str
    expires_at: datetime
    user: AuthUser


class AuthService:
    def __init__(
        self,
        engine: Engine,
        token_secret: str,
        now_factory=_utc_now,
    ) -> None:
        self._engine = engine
        self._token_secret = token_secret
        self._now_factory = now_factory

    def login(self, username: str, password: str) -> tuple[str, AuthSession]:
        normalized_username = username.strip()

        with self._engine.begin() as connection:
            user_row = (
                connection.execute(
                    select(users).where(users.c.username == normalized_username)
                )
                .mappings()
                .one_or_none()
            )
            if user_row is None or not verify_password(
                password, user_row["password_hash"]
            ):
                raise UnauthorizedError()

            token = secrets.token_urlsafe(32)
            token_hash = hash_token(token, self._token_secret)
            now = self._now_factory()
            expires_at = now + TOKEN_TTL

            connection.execute(
                session_tokens.insert().values(
                    id=str(uuid4()),
                    user_id=user_row["id"],
                    token_hash=token_hash,
                    created_at=now,
                    expires_at=expires_at,
                )
            )

        return token, AuthSession(
            token_hash=token_hash,
            expires_at=expires_at,
            user=_auth_user_from_row(user_row),
        )

    def authenticate_token(self, token: str) -> AuthSession:
        if not token:
            raise UnauthorizedError()

        token_hash = hash_token(token, self._token_secret)
        now = self._now_factory()

        with self._engine.connect() as connection:
            row = (
                connection.execute(
                    select(
                        session_tokens.c.token_hash,
                        session_tokens.c.expires_at,
                        users.c.id,
                        users.c.username,
                        users.c.current_revision,
                    )
                    .select_from(
                        session_tokens.join(
                            users,
                            session_tokens.c.user_id == users.c.id,
                        )
                    )
                    .where(
                        session_tokens.c.token_hash == token_hash,
                        session_tokens.c.revoked_at.is_(None),
                        session_tokens.c.expires_at > now,
                    )
                )
                .mappings()
                .one_or_none()
            )

        if row is None:
            raise UnauthorizedError()

        return AuthSession(
            token_hash=row["token_hash"],
            expires_at=row["expires_at"],
            user=_auth_user_from_row(row),
        )

    def logout(self, token_hash: str) -> None:
        with self._engine.begin() as connection:
            connection.execute(
                update(session_tokens)
                .where(
                    session_tokens.c.token_hash == token_hash,
                    session_tokens.c.revoked_at.is_(None),
                )
                .values(revoked_at=self._now_factory())
            )


def hash_token(token: str, token_secret: str) -> str:
    # 服务端只保存 token 哈希，避免数据库泄漏后直接复用明文 token。
    return hmac.new(
        token_secret.encode("utf-8"),
        token.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _auth_user_from_row(row) -> AuthUser:
    return AuthUser(
        id=row["id"],
        username=row["username"],
        current_revision=int(row["current_revision"]),
    )
