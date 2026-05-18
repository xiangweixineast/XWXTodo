from datetime import datetime
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.pool import StaticPool

from app.accounts import create_user
from app.api import create_app
from app.config import Settings
from app.schema import metadata, users


@pytest.fixture
def todos_context():
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

    metadata.create_all(engine)
    settings = Settings(
        database_url="sqlite://",
        token_secret="test-token-secret",
    )
    client = TestClient(
        create_app(settings=settings, health_checker=lambda: None, engine=engine)
    )

    try:
        yield client, engine
    finally:
        metadata.drop_all(engine)
        engine.dispose()


def test_get_todos_requires_auth(todos_context):
    client, _engine = todos_context

    response = client.get("/todos")

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}


def test_get_todos_returns_empty_snapshot(todos_context):
    client, engine = todos_context
    _user_id, token = _create_user_session(client, engine, "alice")

    response = client.get("/todos", headers=_auth_header(token))

    assert response.status_code == 200
    assert response.json() == {"revision": 0, "todos": []}


def test_create_todo_trims_title_generates_fields_and_increments_revision(
    todos_context,
):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")
    before = datetime.utcnow()

    response = client.post(
        "/todos",
        json={"title": "  写规格  "},
        headers=_auth_header(token),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["revision"] == 1
    assert _fetch_revision(engine, user_id) == 1

    todo = _only_todo(body)
    UUID(todo["id"])
    assert todo["title"] == "写规格"
    assert todo["status"] == "pending"
    assert todo["sort_order"] == 0
    assert todo["completed_at"] is None
    assert before <= datetime.fromisoformat(todo["created_at"]) <= datetime.utcnow()
    assert todo["updated_at"] == todo["created_at"]


def test_create_todo_appends_sort_order(todos_context):
    client, engine = todos_context
    _user_id, token = _create_user_session(client, engine, "alice")

    first = _create_todo(client, token, "A")
    second = _create_todo(client, token, "B")

    assert first["revision"] == 1
    assert second["revision"] == 2
    assert [todo["sort_order"] for todo in second["todos"]] == [0, 1]
    assert [todo["title"] for todo in second["todos"]] == ["A", "B"]


def test_edit_todo_updates_title_returns_snapshot_and_revision(todos_context):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")
    todo_id = _only_todo(_create_todo(client, token, "Before"))["id"]

    response = client.patch(
        f"/todos/{todo_id}",
        json={"title": "  After  "},
        headers=_auth_header(token),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["revision"] == 2
    assert _fetch_revision(engine, user_id) == 2
    assert _only_todo(body)["title"] == "After"


def test_delete_todo_removes_active_todo_and_increments_revision(todos_context):
    client, _engine = todos_context
    _user_id, token = _create_user_session(client, _engine, "alice")
    first_id = _only_todo(_create_todo(client, token, "A"))["id"]
    _create_todo(client, token, "B")

    response = client.delete(f"/todos/{first_id}", headers=_auth_header(token))

    assert response.status_code == 200
    body = response.json()
    assert body["revision"] == 3
    assert [todo["title"] for todo in body["todos"]] == ["B"]


def test_start_todo_allows_only_one_doing_per_account(todos_context):
    client, engine = todos_context
    _alice_id, alice_token = _create_user_session(client, engine, "alice")
    _bob_id, bob_token = _create_user_session(client, engine, "bob")
    first_id = _only_todo(_create_todo(client, alice_token, "A"))["id"]
    second_id = _create_todo(client, alice_token, "B")["todos"][1]["id"]
    bob_id = _only_todo(_create_todo(client, bob_token, "Bob"))["id"]

    first_start = client.post(
        f"/todos/{first_id}/start",
        headers=_auth_header(alice_token),
    )
    second_start = client.post(
        f"/todos/{second_id}/start",
        headers=_auth_header(alice_token),
    )

    assert first_start.status_code == 200
    assert second_start.status_code == 200
    alice_body = second_start.json()
    assert alice_body["revision"] == 4
    assert _status_by_id(alice_body) == {
        first_id: "pending",
        second_id: "doing",
    }

    bob_response = client.get("/todos", headers=_auth_header(bob_token))
    assert bob_response.status_code == 200
    assert bob_response.json()["revision"] == 1
    assert _status_by_id(bob_response.json()) == {bob_id: "pending"}


def test_pause_todo_requires_doing_and_increments_revision(todos_context):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")
    todo_id = _only_todo(_create_todo(client, token, "A"))["id"]
    client.post(f"/todos/{todo_id}/start", headers=_auth_header(token))

    response = client.post(f"/todos/{todo_id}/pause", headers=_auth_header(token))

    assert response.status_code == 200
    body = response.json()
    assert body["revision"] == 3
    assert _fetch_revision(engine, user_id) == 3
    assert _only_todo(body)["status"] == "pending"


def test_complete_todo_sets_completed_at_and_revision(todos_context):
    client, _engine = todos_context
    _user_id, token = _create_user_session(client, _engine, "alice")
    todo_id = _only_todo(_create_todo(client, token, "A"))["id"]

    response = client.post(f"/todos/{todo_id}/complete", headers=_auth_header(token))

    assert response.status_code == 200
    body = response.json()
    todo = _only_todo(body)
    assert body["revision"] == 2
    assert todo["status"] == "completed"
    assert todo["completed_at"] is not None
    assert todo["completed_at"] == todo["updated_at"]


@pytest.mark.parametrize(
    ("method", "path_suffix", "json_body"),
    [
        ("patch", "", {"title": "Changed"}),
        ("delete", "", None),
        ("post", "/start", None),
        ("post", "/complete", None),
    ],
)
def test_completed_todo_rejects_mutating_operations_without_revision_change(
    todos_context,
    method,
    path_suffix,
    json_body,
):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")
    todo_id = _only_todo(_create_todo(client, token, "A"))["id"]
    complete_response = client.post(
        f"/todos/{todo_id}/complete",
        headers=_auth_header(token),
    )
    assert complete_response.status_code == 200

    response = client.request(
        method,
        f"/todos/{todo_id}{path_suffix}",
        json=json_body,
        headers=_auth_header(token),
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "todo_state_conflict"}
    assert _fetch_revision(engine, user_id) == 2
    snapshot = client.get("/todos", headers=_auth_header(token)).json()
    assert snapshot["revision"] == 2
    assert _only_todo(snapshot)["status"] == "completed"


def test_pause_pending_todo_returns_conflict_without_revision_change(todos_context):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")
    todo_id = _only_todo(_create_todo(client, token, "A"))["id"]

    response = client.post(f"/todos/{todo_id}/pause", headers=_auth_header(token))

    assert response.status_code == 409
    assert response.json() == {"detail": "todo_state_conflict"}
    assert _fetch_revision(engine, user_id) == 1


@pytest.mark.parametrize(
    ("method", "path", "json_body"),
    [
        ("patch", "/todos/missing", {"title": "Changed"}),
        ("delete", "/todos/missing", None),
        ("post", "/todos/missing/start", None),
        ("post", "/todos/missing/pause", None),
        ("post", "/todos/missing/complete", None),
    ],
)
def test_missing_todo_returns_not_found_without_revision_change(
    todos_context,
    method,
    path,
    json_body,
):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")

    response = client.request(
        method,
        path,
        json=json_body,
        headers=_auth_header(token),
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "todo_not_found"}
    assert _fetch_revision(engine, user_id) == 0


def test_title_validation_returns_422_without_revision_change(todos_context):
    client, engine = todos_context
    user_id, token = _create_user_session(client, engine, "alice")

    empty_response = client.post(
        "/todos",
        json={"title": "   "},
        headers=_auth_header(token),
    )

    assert empty_response.status_code == 422
    assert empty_response.json() == {"detail": "title_required"}
    assert _fetch_revision(engine, user_id) == 0

    todo_id = _only_todo(_create_todo(client, token, "A"))["id"]
    long_response = client.patch(
        f"/todos/{todo_id}",
        json={"title": "a" * 501},
        headers=_auth_header(token),
    )

    assert long_response.status_code == 422
    assert long_response.json() == {"detail": "title_too_long"}
    assert _fetch_revision(engine, user_id) == 1


def _create_user_session(client: TestClient, engine, username: str) -> tuple[str, str]:
    password = "plain-password-value"
    user_id = create_user(engine, username, password)
    return user_id, _login(client, username, password)


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post(
        "/auth/login",
        json={"username": username, "password": password},
    )
    assert response.status_code == 200
    return response.json()["token"]


def _create_todo(client: TestClient, token: str, title: str) -> dict:
    response = client.post(
        "/todos",
        json={"title": title},
        headers=_auth_header(token),
    )
    assert response.status_code == 200
    return response.json()


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _fetch_revision(engine, user_id: str) -> int:
    with engine.connect() as connection:
        return int(
            connection.execute(
                select(users.c.current_revision).where(users.c.id == user_id)
            ).scalar_one()
        )


def _only_todo(snapshot: dict) -> dict:
    assert len(snapshot["todos"]) == 1
    return snapshot["todos"][0]


def _status_by_id(snapshot: dict) -> dict[str, str]:
    return {todo["id"]: todo["status"] for todo in snapshot["todos"]}
