from app.config import Settings


def test_settings_reads_xwxtodo_environment(monkeypatch):
    monkeypatch.setenv(
        "XWXTODO_DATABASE_URL",
        "mysql+pymysql://xwxtodo_user:secret@127.0.0.1:3306/xwxtodo?charset=utf8mb4",
    )
    monkeypatch.setenv("XWXTODO_TOKEN_SECRET", "test-token-secret")
    monkeypatch.setenv("XWXTODO_HOST", "0.0.0.0")
    monkeypatch.setenv("XWXTODO_PORT", "19090")

    settings = Settings()

    assert settings.database_url.endswith("/xwxtodo?charset=utf8mb4")
    assert settings.token_secret == "test-token-secret"
    assert settings.host == "0.0.0.0"
    assert settings.port == 19090


def test_settings_defaults_to_local_service_port(monkeypatch):
    monkeypatch.setenv(
        "XWXTODO_DATABASE_URL",
        "mysql+pymysql://xwxtodo_user:secret@127.0.0.1:3306/xwxtodo?charset=utf8mb4",
    )
    monkeypatch.setenv("XWXTODO_TOKEN_SECRET", "test-token-secret")
    monkeypatch.delenv("XWXTODO_HOST", raising=False)
    monkeypatch.delenv("XWXTODO_PORT", raising=False)

    settings = Settings()

    assert settings.host == "127.0.0.1"
    assert settings.port == 18080
