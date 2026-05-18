import os

import pytest
from sqlalchemy import inspect, text
from sqlalchemy.engine import make_url

from app.database import create_database_engine
from app.migrate import run_migrations
from app.schema import metadata


def test_run_migrations_against_mysql_when_configured():
    database_url = os.environ.get("XWXTODO_TEST_DATABASE_URL")
    if not database_url:
        pytest.skip("XWXTODO_TEST_DATABASE_URL is not configured")

    database_name = make_url(database_url).database or ""
    if "test" not in database_name.lower():
        pytest.skip("XWXTODO_TEST_DATABASE_URL must point to a test database")

    engine = create_database_engine(database_url)
    try:
        metadata.drop_all(engine)
        run_migrations(engine)
        run_migrations(engine)

        inspector = inspect(engine)
        assert {"users", "session_tokens", "todos"}.issubset(
            set(inspector.get_table_names())
        )

        users_columns = {column["name"]: column for column in inspector.get_columns("users")}
        session_columns = {
            column["name"]: column for column in inspector.get_columns("session_tokens")
        }
        todos_columns = {column["name"]: column for column in inspector.get_columns("todos")}

        assert users_columns["username"]["type"].length == 191
        assert users_columns["current_revision"]["default"] == "0"
        assert session_columns["token_hash"]["type"].length == 64
        assert todos_columns["title"]["type"].length == 500
        assert "doing_user_id" in todos_columns

        todos_indexes = {index["name"]: index for index in inspector.get_indexes("todos")}
        assert "uq_todos_single_doing_per_user" in todos_indexes
        assert todos_indexes["uq_todos_single_doing_per_user"]["unique"] is True

        with engine.connect() as connection:
            create_table_sql = connection.execute(text("SHOW CREATE TABLE todos")).one()[1]

        assert "doing_user_id" in create_table_sql
        assert "GENERATED ALWAYS" not in create_table_sql.upper()
    finally:
        metadata.drop_all(engine)
        engine.dispose()
