from typing import Callable, Optional

from fastapi import FastAPI, HTTPException, status

from app.config import Settings, get_settings
from app.database import Database

HealthChecker = Callable[[], None]


def create_app(
    settings: Optional[Settings] = None,
    health_checker: Optional[HealthChecker] = None,
) -> FastAPI:
    resolved_settings = settings or get_settings()

    if health_checker is None:
        database = Database(resolved_settings)
        health_checker = database.check_health

    app = FastAPI(title="XWXTodo Sync API")

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

    return app
