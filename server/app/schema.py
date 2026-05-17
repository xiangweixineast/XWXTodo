from sqlalchemy import Column, Computed, ForeignKey, Index, MetaData, Table, text
from sqlalchemy.dialects import mysql

TODO_STATUS_VALUES = ("pending", "doing", "completed")

metadata = MetaData()

users = Table(
    "users",
    metadata,
    Column("id", mysql.CHAR(36), primary_key=True, nullable=False),
    Column(
        "username",
        mysql.VARCHAR(191, collation="utf8mb4_bin"),
        nullable=False,
        unique=True,
    ),
    Column("password_hash", mysql.VARCHAR(255), nullable=False),
    Column(
        "current_revision",
        mysql.BIGINT(unsigned=True),
        nullable=False,
        server_default=text("0"),
    ),
    Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
    Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
    mysql_charset="utf8mb4",
    mysql_engine="InnoDB",
)

session_tokens = Table(
    "session_tokens",
    metadata,
    Column("id", mysql.CHAR(36), primary_key=True, nullable=False),
    Column(
        "user_id",
        mysql.CHAR(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    ),
    Column("token_hash", mysql.CHAR(64), nullable=False, unique=True),
    Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
    Column("expires_at", mysql.DATETIME(fsp=6), nullable=False),
    Column("revoked_at", mysql.DATETIME(fsp=6), nullable=True),
    mysql_charset="utf8mb4",
    mysql_engine="InnoDB",
)

todos = Table(
    "todos",
    metadata,
    Column("id", mysql.CHAR(36), primary_key=True, nullable=False),
    Column(
        "user_id",
        mysql.CHAR(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    ),
    Column("title", mysql.VARCHAR(500), nullable=False),
    Column("status", mysql.ENUM(*TODO_STATUS_VALUES), nullable=False),
    Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
    Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
    Column("completed_at", mysql.DATETIME(fsp=6), nullable=True),
    Column("sort_order", mysql.BIGINT, nullable=False),
    Column(
        "doing_user_id",
        mysql.CHAR(36),
        Computed(
            "CASE WHEN status = 'doing' THEN user_id ELSE NULL END",
            persisted=True,
        ),
        nullable=True,
    ),
    mysql_charset="utf8mb4",
    mysql_engine="InnoDB",
)

Index("ix_session_tokens_user_id", session_tokens.c.user_id)
Index("ix_todos_user_id_sort_order", todos.c.user_id, todos.c.sort_order)
Index("uq_todos_single_doing_per_user", todos.c.doing_user_id, unique=True)
