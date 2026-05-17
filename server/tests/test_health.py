from fastapi.testclient import TestClient

from app.api import create_app
from app.config import Settings


def make_settings() -> Settings:
    return Settings(
        database_url="mysql+pymysql://xwxtodo_user:secret@127.0.0.1:3306/xwxtodo?charset=utf8mb4",
        token_secret="test-token-secret",
    )


def test_health_returns_ok_when_database_check_passes():
    client = TestClient(create_app(settings=make_settings(), health_checker=lambda: None))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}


def test_health_returns_503_without_database_error_detail():
    def fail_health_check() -> None:
        raise RuntimeError("database password leaked")

    client = TestClient(
        create_app(settings=make_settings(), health_checker=fail_health_check)
    )

    response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {"status": "error", "database": "unavailable"}
    }
    assert "database password leaked" not in response.text
