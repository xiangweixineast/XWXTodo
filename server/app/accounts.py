from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError

from app.schema import users
from app.security import hash_password

MAX_USERNAME_LENGTH = 191


class AccountError(Exception):
    pass


class AccountValidationError(AccountError):
    pass


class DuplicateUsernameError(AccountError):
    pass


def create_user(engine: Engine, username: str, password: str) -> str:
    normalized_username = _validate_username(username)
    _validate_password(password)

    user_id = str(uuid4())
    now = _utc_now()

    # 建号只落库密码哈希，明文密码不进入数据库或日志输出。
    values = {
        "id": user_id,
        "username": normalized_username,
        "password_hash": hash_password(password),
        "created_at": now,
        "updated_at": now,
    }

    try:
        with engine.begin() as connection:
            connection.execute(users.insert().values(**values))
    except IntegrityError as exc:
        raise DuplicateUsernameError("用户名已存在") from exc

    return user_id


def _validate_username(username: str) -> str:
    normalized_username = username.strip()
    if not normalized_username:
        raise AccountValidationError("用户名不能为空")
    if len(normalized_username) > MAX_USERNAME_LENGTH:
        raise AccountValidationError("用户名不能超过 191 个字符")
    return normalized_username


def _validate_password(password: str) -> None:
    if password == "":
        raise AccountValidationError("密码不能为空")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)
