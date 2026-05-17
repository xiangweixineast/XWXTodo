from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = Field(min_length=1)
    token_secret: str = Field(min_length=1)
    host: str = "127.0.0.1"
    port: int = 18080

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="XWXTODO_",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
