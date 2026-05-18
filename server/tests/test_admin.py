from collections import deque

from sqlalchemy import create_engine, event

from app.admin import create_user_command
from app.config import Settings
from app.schema import users


def make_settings() -> Settings:
    return Settings(
        database_url="mysql+pymysql://xwxtodo_user:secret@127.0.0.1:3306/xwxtodo?charset=utf8mb4",
        token_secret="test-token-secret",
    )


def make_user_engine():
    engine = create_engine("sqlite:///:memory:", future=True)

    @event.listens_for(engine, "connect")
    def add_mysql_collation(dbapi_connection, _connection_record):
        dbapi_connection.create_collation(
            "utf8mb4_bin",
            lambda left, right: (left > right) - (left < right),
        )

    users.create(engine)
    return engine


def test_create_user_command_success_does_not_leak_password(capsys):
    passwords = deque(["plain-password-value", "plain-password-value"])
    engine = make_user_engine()
    engine.dispose = lambda: None

    result = create_user_command(
        "alice",
        password_reader=lambda _prompt: passwords.popleft(),
        engine_factory=lambda _database_url: engine,
        settings_provider=make_settings,
    )

    captured = capsys.readouterr()

    assert result == 0
    assert "已创建账号：alice" in captured.out
    assert "plain-password-value" not in captured.out
    assert "plain-password-value" not in captured.err


def test_create_user_command_password_mismatch_does_not_create_engine(capsys):
    passwords = deque(["first-password", "second-password"])

    def fail_engine_factory(_database_url):
        raise AssertionError("engine should not be created")

    result = create_user_command(
        "alice",
        password_reader=lambda _prompt: passwords.popleft(),
        engine_factory=fail_engine_factory,
        settings_provider=make_settings,
    )

    captured = capsys.readouterr()

    assert result == 1
    assert captured.out == ""
    assert "两次密码不一致" in captured.err
