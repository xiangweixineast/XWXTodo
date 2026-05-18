from datetime import datetime
from typing import Callable, Optional

from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy.engine import Engine

from app.auth import (
    TOKEN_TYPE,
    UNAUTHORIZED_DETAIL,
    AuthService,
    AuthSession,
    UnauthorizedError,
)
from app.config import Settings, get_settings
from app.database import Database
from app.todos import (
    TodoConflictError,
    TodoError,
    TodoNotFoundError,
    TodoService,
    TodoSnapshot,
    TodoValidationError,
)

HealthChecker = Callable[[], None]


class LoginRequest(BaseModel):
    username: str
    password: str


class UserResponse(BaseModel):
    id: str
    username: str
    current_revision: int


class LoginResponse(BaseModel):
    token: str
    token_type: str
    expires_at: datetime
    user: UserResponse


class MeResponse(BaseModel):
    expires_at: datetime
    user: UserResponse


class TodoTitleRequest(BaseModel):
    title: str


class TodoResponse(BaseModel):
    id: str
    title: str
    status: str
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime]
    sort_order: int


class TodoSnapshotResponse(BaseModel):
    revision: int
    todos: list[TodoResponse]


def create_app(
    settings: Optional[Settings] = None,
    health_checker: Optional[HealthChecker] = None,
    engine: Optional[Engine] = None,
) -> FastAPI:
    resolved_settings = settings or get_settings()
    database = None

    if health_checker is None or engine is None:
        database = Database(resolved_settings)

    if health_checker is None:
        health_checker = database.check_health
    resolved_engine = engine if engine is not None else database.engine
    auth_service = AuthService(resolved_engine, resolved_settings.token_secret)
    todo_service = TodoService(resolved_engine)
    bearer_scheme = HTTPBearer(auto_error=False)

    app = FastAPI(title="XWXTodo Sync API")

    def unauthorized() -> None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=UNAUTHORIZED_DETAIL,
        )

    def current_session(
        credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    ) -> AuthSession:
        # 认证依赖统一校验 bearer token，并隐藏具体失败原因。
        if credentials is None or credentials.scheme.lower() != TOKEN_TYPE:
            unauthorized()

        try:
            return auth_service.authenticate_token(credentials.credentials)
        except UnauthorizedError:
            unauthorized()

    def todo_http_exception(error: TodoError) -> HTTPException:
        if isinstance(error, TodoValidationError):
            return HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(error),
            )
        if isinstance(error, TodoNotFoundError):
            return HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=str(error),
            )
        if isinstance(error, TodoConflictError):
            return HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=str(error),
            )
        return HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="todo_error",
        )

    @app.get("/health")
    def health() -> dict[str, str]:
        try:
            health_checker()
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"status": "error", "database": "unavailable"},
            )

        return {"status": "ok", "database": "ok"}

    @app.post("/auth/login", response_model=LoginResponse)
    def login(request: LoginRequest) -> LoginResponse:
        try:
            token, session = auth_service.login(request.username, request.password)
        except UnauthorizedError:
            unauthorized()

        return LoginResponse(
            token=token,
            token_type=TOKEN_TYPE,
            expires_at=session.expires_at,
            user=_user_response(session),
        )

    @app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
    def logout(session: AuthSession = Depends(current_session)) -> Response:
        auth_service.logout(session.token_hash)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/auth/me", response_model=MeResponse)
    def me(session: AuthSession = Depends(current_session)) -> MeResponse:
        return MeResponse(
            expires_at=session.expires_at,
            user=_user_response(session),
        )

    @app.get("/todos", response_model=TodoSnapshotResponse)
    def list_todos(
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        return _todo_snapshot_response(todo_service.get_snapshot(session.user.id))

    @app.post("/todos", response_model=TodoSnapshotResponse)
    def add_todo(
        request: TodoTitleRequest,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.add_todo(session.user.id, request.title)
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    @app.patch("/todos/{todo_id}", response_model=TodoSnapshotResponse)
    def edit_todo(
        todo_id: str,
        request: TodoTitleRequest,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.edit_todo(
                session.user.id,
                todo_id,
                request.title,
            )
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    @app.delete("/todos/{todo_id}", response_model=TodoSnapshotResponse)
    def delete_todo(
        todo_id: str,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.delete_todo(session.user.id, todo_id)
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    @app.post("/todos/{todo_id}/start", response_model=TodoSnapshotResponse)
    def start_todo(
        todo_id: str,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.start_todo(session.user.id, todo_id)
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    @app.post("/todos/{todo_id}/pause", response_model=TodoSnapshotResponse)
    def pause_todo(
        todo_id: str,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.pause_todo(session.user.id, todo_id)
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    @app.post("/todos/{todo_id}/complete", response_model=TodoSnapshotResponse)
    def complete_todo(
        todo_id: str,
        session: AuthSession = Depends(current_session),
    ) -> TodoSnapshotResponse:
        try:
            snapshot = todo_service.complete_todo(session.user.id, todo_id)
        except TodoError as error:
            raise todo_http_exception(error)

        return _todo_snapshot_response(snapshot)

    return app


def _user_response(session: AuthSession) -> UserResponse:
    return UserResponse(
        id=session.user.id,
        username=session.user.username,
        current_revision=session.user.current_revision,
    )


def _todo_snapshot_response(snapshot: TodoSnapshot) -> TodoSnapshotResponse:
    # API 只返回当前账号快照，客户端用 revision 判断云端版本。
    return TodoSnapshotResponse(
        revision=snapshot.revision,
        todos=[
            TodoResponse(
                id=todo.id,
                title=todo.title,
                status=todo.status,
                created_at=todo.created_at,
                updated_at=todo.updated_at,
                completed_at=todo.completed_at,
                sort_order=todo.sort_order,
            )
            for todo in snapshot.todos
        ],
    )
