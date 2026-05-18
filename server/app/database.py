from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from app.config import Settings


def create_database_engine(database_url: str) -> Engine:
    return create_engine(
        database_url,
        future=True,
        pool_pre_ping=True,
        pool_recycle=1800,
    )


class Database:
    def __init__(self, settings: Settings) -> None:
        self._engine = create_database_engine(settings.database_url)

    @property
    def engine(self) -> Engine:
        return self._engine

    def check_health(self) -> None:
        with self._engine.connect() as connection:
            connection.execute(text("SELECT 1"))
