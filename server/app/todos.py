from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from sqlalchemy import func, select, update
from sqlalchemy.engine import Connection, Engine

from app.schema import todos, users

MAX_TODO_TITLE_LENGTH = 500
PENDING_STATUS = "pending"
DOING_STATUS = "doing"
COMPLETED_STATUS = "completed"


class TodoError(Exception):
    pass


class TodoValidationError(TodoError):
    pass


class TodoNotFoundError(TodoError):
    pass


class TodoConflictError(TodoError):
    pass


@dataclass(frozen=True)
class TodoRecord:
    id: str
    title: str
    status: str
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    sort_order: int


@dataclass(frozen=True)
class TodoSnapshot:
    revision: int
    todos: list[TodoRecord]


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class TodoService:
    def __init__(self, engine: Engine, now_factory=_utc_now) -> None:
        self._engine = engine
        self._now_factory = now_factory

    def get_snapshot(self, user_id: str) -> TodoSnapshot:
        with self._engine.connect() as connection:
            return self._load_snapshot(connection, user_id)

    def add_todo(self, user_id: str, title: str) -> TodoSnapshot:
        normalized_title = _validate_title(title)

        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            sort_order = self._next_sort_order(connection, user_id)

            connection.execute(
                todos.insert().values(
                    id=str(uuid4()),
                    user_id=user_id,
                    title=normalized_title,
                    status=PENDING_STATUS,
                    created_at=now,
                    updated_at=now,
                    completed_at=None,
                    sort_order=sort_order,
                    doing_user_id=None,
                )
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def edit_todo(self, user_id: str, todo_id: str, title: str) -> TodoSnapshot:
        normalized_title = _validate_title(title)

        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            todo = self._get_owned_todo(connection, user_id, todo_id)
            self._ensure_not_completed(todo)

            connection.execute(
                update(todos)
                .where(todos.c.id == todo_id, todos.c.user_id == user_id)
                .values(title=normalized_title, updated_at=now)
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def delete_todo(self, user_id: str, todo_id: str) -> TodoSnapshot:
        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            todo = self._get_owned_todo(connection, user_id, todo_id)
            self._ensure_not_completed(todo)

            connection.execute(
                todos.delete().where(
                    todos.c.id == todo_id,
                    todos.c.user_id == user_id,
                )
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def start_todo(self, user_id: str, todo_id: str) -> TodoSnapshot:
        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            todo = self._get_owned_todo(connection, user_id, todo_id)
            self._ensure_not_completed(todo)

            # 先清空本账号 doing，再设置目标，避免触发单 doing 唯一约束。
            connection.execute(
                update(todos)
                .where(
                    todos.c.user_id == user_id,
                    todos.c.status == DOING_STATUS,
                )
                .values(
                    status=PENDING_STATUS,
                    updated_at=now,
                    doing_user_id=None,
                )
            )
            connection.execute(
                update(todos)
                .where(todos.c.id == todo_id, todos.c.user_id == user_id)
                .values(
                    status=DOING_STATUS,
                    updated_at=now,
                    completed_at=None,
                    doing_user_id=user_id,
                )
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def pause_todo(self, user_id: str, todo_id: str) -> TodoSnapshot:
        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            todo = self._get_owned_todo(connection, user_id, todo_id)
            self._ensure_status(todo, DOING_STATUS)

            connection.execute(
                update(todos)
                .where(todos.c.id == todo_id, todos.c.user_id == user_id)
                .values(
                    status=PENDING_STATUS,
                    updated_at=now,
                    doing_user_id=None,
                )
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def complete_todo(self, user_id: str, todo_id: str) -> TodoSnapshot:
        with self._engine.begin() as connection:
            now = self._now_factory()
            current_revision = self._lock_user_revision(connection, user_id)
            todo = self._get_owned_todo(connection, user_id, todo_id)
            self._ensure_not_completed(todo)

            connection.execute(
                update(todos)
                .where(todos.c.id == todo_id, todos.c.user_id == user_id)
                .values(
                    status=COMPLETED_STATUS,
                    updated_at=now,
                    completed_at=now,
                    doing_user_id=None,
                )
            )

            revision = self._bump_revision(
                connection,
                user_id,
                current_revision,
                now,
            )
            return self._load_snapshot(connection, user_id, revision)

    def _lock_user_revision(self, connection: Connection, user_id: str) -> int:
        # 写操作锁账号行，保证 revision 和 TODO 状态按账号串行更新。
        revision = connection.execute(
            select(users.c.current_revision)
            .where(users.c.id == user_id)
            .with_for_update()
        ).scalar_one()
        return int(revision)

    def _next_sort_order(self, connection: Connection, user_id: str) -> int:
        next_sort_order = connection.execute(
            select(func.coalesce(func.max(todos.c.sort_order), -1) + 1).where(
                todos.c.user_id == user_id
            )
        ).scalar_one()
        return int(next_sort_order)

    def _get_owned_todo(self, connection: Connection, user_id: str, todo_id: str):
        row = (
            connection.execute(
                select(todos.c.id, todos.c.status)
                .where(todos.c.id == todo_id, todos.c.user_id == user_id)
                .with_for_update()
            )
            .mappings()
            .one_or_none()
        )
        if row is None:
            raise TodoNotFoundError("todo_not_found")
        return row

    def _ensure_not_completed(self, todo) -> None:
        if todo["status"] == COMPLETED_STATUS:
            raise TodoConflictError("todo_state_conflict")

    def _ensure_status(self, todo, required_status: str) -> None:
        if todo["status"] != required_status:
            raise TodoConflictError("todo_state_conflict")

    def _bump_revision(
        self,
        connection: Connection,
        user_id: str,
        current_revision: int,
        updated_at: datetime,
    ) -> int:
        revision = current_revision + 1
        connection.execute(
            update(users)
            .where(users.c.id == user_id)
            .values(current_revision=revision, updated_at=updated_at)
        )
        return revision

    def _load_snapshot(
        self,
        connection: Connection,
        user_id: str,
        revision: Optional[int] = None,
    ) -> TodoSnapshot:
        if revision is None:
            revision = int(
                connection.execute(
                    select(users.c.current_revision).where(users.c.id == user_id)
                ).scalar_one()
            )

        rows = (
            connection.execute(
                select(
                    todos.c.id,
                    todos.c.title,
                    todos.c.status,
                    todos.c.created_at,
                    todos.c.updated_at,
                    todos.c.completed_at,
                    todos.c.sort_order,
                )
                .where(todos.c.user_id == user_id)
                .order_by(todos.c.sort_order.asc(), todos.c.created_at.asc())
            )
            .mappings()
            .all()
        )

        return TodoSnapshot(
            revision=revision,
            todos=[
                TodoRecord(
                    id=row["id"],
                    title=row["title"],
                    status=row["status"],
                    created_at=row["created_at"],
                    updated_at=row["updated_at"],
                    completed_at=row["completed_at"],
                    sort_order=int(row["sort_order"]),
                )
                for row in rows
            ],
        )


def _validate_title(title: str) -> str:
    normalized_title = title.strip()
    if not normalized_title:
        raise TodoValidationError("title_required")
    if len(normalized_title) > MAX_TODO_TITLE_LENGTH:
        raise TodoValidationError("title_too_long")
    return normalized_title
