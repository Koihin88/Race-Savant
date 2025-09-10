from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def _load_env_from_dotenv() -> None:
    """Load key=value pairs from a local .env file if present.

    This avoids adding a dependency on python-dotenv while still making
    `DATABASE_URL` available when users place it in `.env` at the project root.
    Existing environment variables are not overridden.
    """
    # Resolve .env next to this file (project's api directory)
    here = os.path.dirname(__file__)
    env_path = os.path.join(here, ".env")
    if not os.path.exists(env_path):
        return
    try:
        with open(env_path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = value
    except Exception:
        # Silent best-effort load; actual errors will surface when reading vars
        pass


def _normalize_database_url(url: str) -> str:
    """Normalize common Postgres URL variants for SQLAlchemy + psycopg3.

    - Convert `postgres://` -> `postgresql+psycopg://`
    - Convert `postgresql://` -> `postgresql+psycopg://` if driver not specified
    """
    if not url:
        return url
    u = url.strip()
    if u.startswith("postgres://"):
        return "postgresql+psycopg://" + u[len("postgres://") :]
    if u.startswith("postgresql://") and not u.startswith("postgresql+", 0, 13):
        return u.replace("postgresql://", "postgresql+psycopg://", 1)
    return u


def get_database_url() -> str:
    # Best effort to load from .env if not already in environment
    if not os.getenv("DATABASE_URL"):
        _load_env_from_dotenv()
    url = os.getenv("DATABASE_URL")
    if not url:
        raise RuntimeError(
            "DATABASE_URL env var is not set. Add it to your shell env or to .env. "
            "Example: postgresql+psycopg://user:pass@localhost:5432/dbname"
        )
    return _normalize_database_url(url)


def create_engine_and_session():
    engine = create_engine(get_database_url(), future=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    return engine, SessionLocal


@contextmanager
def db_session(SessionLocal) -> Iterator:
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
