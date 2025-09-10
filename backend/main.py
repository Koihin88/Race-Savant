from __future__ import annotations

import argparse
import os

from db import create_engine_and_session, db_session
from etl import init_db, load_fastf1_session, load_event_weekend, list_event_sessions


def parse_args():
    p = argparse.ArgumentParser(description="Load FastF1 data into Postgres")
    p.add_argument("year", type=int, help="Season year, e.g. 2024")
    p.add_argument("gp", help="Round number or Grand Prix name")
    p.add_argument("session", nargs="?", help="Session type, e.g. FP1, Q, R, SQ. Omit with --all or --nth.")
    p.add_argument("--no-telemetry", action="store_true", help="Skip telemetry storage")
    p.add_argument("--cache", default=os.getenv("FASTF1_CACHE", "cache"), help="FastF1 cache directory")
    p.add_argument("--all", action="store_true", help="Load all sessions for the weekend in order")
    p.add_argument("--nth", type=int, help="Load the Nth session of the weekend (1-based)")
    p.add_argument("--list", action="store_true", help="List detected sessions for the event and exit")
    p.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip loading if the session already has laps in the database",
    )
    return p.parse_args()


def main():
    args = parse_args()
    engine, SessionLocal = create_engine_and_session()
    init_db(engine)
    gp = int(args.gp) if args.gp.isdigit() else args.gp
    with db_session(SessionLocal) as db:
        if args.list:
            sessions = list_event_sessions(args.year, gp)
            for idx, (stype, when) in enumerate(sessions, start=1):
                print(f"{idx}. {stype} @ {when}")
            return
        if args.all:
            results = load_event_weekend(
                db,
                year=args.year,
                gp=gp,
                cache_dir=args.cache,
                store_telemetry=not args.no_telemetry,
                skip_if_exists=args.skip_existing,
            )
            for r in results:
                print(r)
            return
        if args.nth is not None:
            sessions = list_event_sessions(args.year, gp)
            if args.nth < 1 or args.nth > len(sessions):
                raise SystemExit(f"--nth out of range (1..{len(sessions)})")
            stype = sessions[args.nth - 1][0]
            summary = load_fastf1_session(
                db,
                year=args.year,
                gp=gp,
                session_type=stype,
                cache_dir=args.cache,
                store_telemetry=not args.no_telemetry,
                skip_if_exists=args.skip_existing,
            )
            summary["session_type"] = stype
            print(summary)
            return
        if not args.session:
            raise SystemExit("Provide a session type, or use --all/--nth/--list")
        summary = load_fastf1_session(
            db,
            year=args.year,
            gp=gp,
            session_type=args.session,
            cache_dir=args.cache,
            store_telemetry=not args.no_telemetry,
            skip_if_exists=args.skip_existing,
        )
        print(summary)


if __name__ == "__main__":
    main()
