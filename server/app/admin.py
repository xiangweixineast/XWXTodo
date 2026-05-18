import argparse
import getpass
import sys
from collections.abc import Callable, Sequence
from typing import Optional

from sqlalchemy.engine import Engine

from app.accounts import AccountError, create_user
from app.config import Settings, get_settings
from app.database import create_database_engine

PasswordReader = Callable[[str], str]
EngineFactory = Callable[[str], Engine]
SettingsProvider = Callable[[], Settings]


class AdminCommandError(Exception):
    pass


def create_user_command(
    username: str,
    password_reader: PasswordReader = getpass.getpass,
    engine_factory: EngineFactory = create_database_engine,
    settings_provider: SettingsProvider = get_settings,
) -> int:
    try:
        password = _read_confirmed_password(password_reader)
    except AdminCommandError as exc:
        print(f"创建账号失败：{exc}", file=sys.stderr)
        return 1

    settings = settings_provider()
    engine = engine_factory(settings.database_url)
    try:
        user_id = create_user(engine, username, password)
    except AccountError as exc:
        print(f"创建账号失败：{exc}", file=sys.stderr)
        return 1
    finally:
        engine.dispose()

    print(f"已创建账号：{username} ({user_id})")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="XWXTodo 服务端后台管理工具")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # 账号只能由服务器后台创建，客户端不提供注册入口。
    create_user_parser = subparsers.add_parser("create-user", help="创建后台账号")
    create_user_parser.add_argument("username", help="账号用户名")

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "create-user":
        return create_user_command(args.username)

    parser.print_help()
    return 2


def _read_confirmed_password(password_reader: PasswordReader) -> str:
    password = password_reader("Password: ")
    confirm_password = password_reader("Confirm password: ")
    if password != confirm_password:
        raise AdminCommandError("两次密码不一致")
    return password


if __name__ == "__main__":
    raise SystemExit(main())
