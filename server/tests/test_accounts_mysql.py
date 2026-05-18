import os

import pytest
from sqlalchemy import select
from sqlalchemy.engine import make_url

from app.accounts import create_user
from app.database import create_database_engine
from app.schema import metadata, users
from app.security import verify_password


def test_create_user_against_mysql_when_configured():
    database_url = os.environ.get("XWXTODO_TEST_DATABASE_URL")
    if not database_url:
        pytest.skip("XWXTODO_TEST_DATABASE_URL is not configured")

    database_name = make_url(database_url).database or ""
    if "test" not in database_name.lower():
        pytest.skip("XWXTODO_TEST_DATABASE_URL must point to a test database")

    engine = create_database_engine(database_url)
    try:
        metadata.drop_all(engine)
        metadata.create_all(engine)

        user_id = create_user(engine, "alice", "plain-password-value")

        with engine.connect() as connection:
            row = (
                connection.execute(select(users).where(users.c.id == user_id))
                .mappings()
                .one()
            )

        assert row["password_hash"] != "plain-password-value"
        assert "plain-password-value" not in row["password_hash"]
        assert verify_password("plain-password-value", row["password_hash"]) is True
    finally:
        metadata.drop_all(engine)
        engine.dispose()
