from sqlalchemy.engine import Engine

from app.config import get_settings
from app.database import create_database_engine
from app.schema import metadata


def run_migrations(engine: Engine) -> None:
    metadata.create_all(engine)


def main() -> None:
    settings = get_settings()
    engine = create_database_engine(settings.database_url)
    try:
        run_migrations(engine)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
