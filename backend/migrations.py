from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy import text


def run_migrations(engine) -> None:
    """Run lightweight, idempotent migrations.

    - Adds new nullable columns we rely on.
    - Drops legacy columns that are no longer modeled.
    This keeps maintenance simple without a full migration framework.
    """
    try:
        insp = sa.inspect(engine)

        # Drivers table expected columns
        driver_cols = {c["name"] for c in insp.get_columns("drivers")}
        drivers_needed = {
            "first_name": "VARCHAR(100)",
            "last_name": "VARCHAR(100)",
            "team_name": "VARCHAR(100)",
            "team_color": "VARCHAR(10)",
        }
        drivers_missing = {k: v for k, v in drivers_needed.items() if k not in driver_cols}

        # Laps table expected columns
        lap_cols = {c["name"] for c in insp.get_columns("laps")}
        laps_needed = {
            "tyre_life": "FLOAT",
            "track_status": "VARCHAR(20)",
        }
        laps_missing = {k: v for k, v in laps_needed.items() if k not in lap_cols}

        with engine.begin() as conn:
            # Add columns
            for name, dtype in {**drivers_missing, **laps_missing}.items():
                try:
                    table = "drivers" if name in drivers_needed else "laps"
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {name} {dtype}"))
                except Exception:
                    # Best effort: ignore unsupported dialects and perms
                    pass

            # Drop legacy columns (safe if no deps)
            try:
                conn.execute(text("ALTER TABLE drivers DROP COLUMN IF EXISTS headshot_url"))
            except Exception:
                pass
    except Exception:
        # Ignore inspection issues; create_all still ensures tables exist
        pass
