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

    return app


def _user_response(session: AuthSession) -> UserResponse:
    return UserResponse(
        id=session.user.id,
        username=session.user.username,
        current_revision=session.user.current_revision,
    )
