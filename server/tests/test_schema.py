from sqlalchemy.dialects import mysql
from sqlalchemy.schema import CreateIndex, CreateTable

from app.migrate import run_migrations
from app.schema import metadata, session_tokens, todos, users


def mysql_statement(ddl) -> str:
    return str(ddl.compile(dialect=mysql.dialect()))


def test_metadata_contains_sync_tables():
    assert set(metadata.tables) == {"users", "session_tokens", "todos"}


def test_users_table_shape():
    assert users.c.id.type.length == 36
    assert users.c.id.primary_key is True
    assert users.c.username.type.length == 191
    assert users.c.username.type.collation == "utf8mb4_bin"
    assert users.c.username.unique is True
    assert users.c.password_hash.type.length == 255
    assert users.c.current_revision.type.unsigned is True
    assert users.c.current_revision.server_default.arg.text == "0"
    assert users.c.created_at.type.fsp == 6
    assert users.c.updated_at.type.fsp == 6


def test_session_tokens_table_shape():
    user_id_fk = next(iter(session_tokens.c.user_id.foreign_keys))

    assert session_tokens.c.id.type.length == 36
    assert session_tokens.c.token_hash.type.length == 64
    assert session_tokens.c.token_hash.unique is True
    assert user_id_fk.target_fullname == "users.id"
    assert user_id_fk.ondelete == "CASCADE"
    assert session_tokens.c.created_at.type.fsp == 6
    assert session_tokens.c.expires_at.type.fsp == 6
    assert session_tokens.c.revoked_at.nullable is True


def test_todos_table_shape():
    user_id_fk = next(iter(todos.c.user_id.foreign_keys))

    assert todos.c.id.type.length == 36
    assert todos.c.title.type.length == 500
    assert todos.c.status.type.enums == ["pending", "doing", "completed"]
    assert user_id_fk.target_fullname == "users.id"
    assert user_id_fk.ondelete == "CASCADE"
    assert todos.c.created_at.type.fsp == 6
    assert todos.c.updated_at.type.fsp == 6
    assert todos.c.completed_at.nullable is True
    assert todos.c.doing_user_id.computed.persisted is True
    assert "CASE WHEN status = 'doing' THEN user_id ELSE NULL END" in str(
        todos.c.doing_user_id.computed.sqltext
    )


def test_todos_mysql_ddl_contains_generated_single_doing_column():
    table_sql = mysql_statement(CreateTable(todos))
    index_sql = "\n".join(
        mysql_statement(CreateIndex(index))
        for index in todos.indexes
        if index.name == "uq_todos_single_doing_per_user"
    )

    assert "status ENUM('pending','doing','completed') NOT NULL" in table_sql
    assert (
        "doing_user_id CHAR(36) GENERATED ALWAYS AS "
        "(CASE WHEN status = 'doing' THEN user_id ELSE NULL END) STORED"
    ) in table_sql
    assert (
        "CREATE UNIQUE INDEX uq_todos_single_doing_per_user "
        "ON todos (doing_user_id)"
    ) in index_sql


def test_run_migrations_delegates_to_metadata(monkeypatch):
    class RecordingMetadata:
        engine = None

        def create_all(self, engine):
            self.engine = engine

    recording_metadata = RecordingMetadata()
    engine = object()

    monkeypatch.setattr("app.migrate.metadata", recording_metadata)

    run_migrations(engine)

    assert recording_metadata.engine is engine
