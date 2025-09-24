from __future__ import annotations

from typing import Optional, List, Tuple

import pandas as pd
import fastf1

from sqlalchemy import select, delete
from sqlalchemy.orm import Session as OrmSession

from models import Base, Event, Session as DbSession, Driver, Lap, Telemetry, DriverEntry
from migrations import run_migrations
from utils import coalesce_attr, to_ms, to_int, to_float, timedelta_to_s


def init_db(engine) -> None:
    """Create tables and run idempotent lightweight migrations."""
    Base.metadata.create_all(engine)
    run_migrations(engine)


def _upsert_event(db: OrmSession, fevent) -> Event:
    year = coalesce_attr(fevent, "EventYear", "year")
    name = coalesce_attr(fevent, "EventName", "name")
    round_no = coalesce_attr(fevent, "RoundNumber", "round")
    date = coalesce_attr(fevent, "EventDate", "date")
    location = coalesce_attr(fevent, "Location", "EventLocation", "location")
    country = coalesce_attr(fevent, "Country", "country")

    ev = db.execute(select(Event).where(Event.year == year, Event.name == name)).scalar_one_or_none()
    if ev:
        # update optional fields if available
        ev.round = round_no or ev.round
        ev.location = location or ev.location
        ev.country = country or ev.country
        ev.date = pd.to_datetime(date).date() if date is not None else ev.date
        return ev
    ev = Event(
        year=int(year) if year is not None else None,
        round=int(round_no) if round_no is not None else None,
        location=str(location) if location is not None else None,
        country=str(country) if country is not None else None,
        name=str(name) if name is not None else None,
        date=pd.to_datetime(date).date() if date is not None else None,
    )
    db.add(ev)
    db.flush()
    return ev


def _upsert_session(db: OrmSession, event_id: int, fsession, explicit_type: Optional[str] = None) -> DbSession:
    # Prefer explicitly requested session type; fall back to attributes from FastF1
    stype = explicit_type or coalesce_attr(fsession, "session_type", "type", "name")
    sdate = coalesce_attr(fsession, "date")

    sess = db.execute(
        select(DbSession).where(DbSession.event_id == event_id, DbSession.type == stype)
    ).scalar_one_or_none()
    if sess:
        if sdate is not None:
            sess.date = pd.to_datetime(sdate)
        return sess
    sess = DbSession(event_id=event_id, type=str(stype) if stype else None)
    if sdate is not None:
        sess.date = pd.to_datetime(sdate)
    db.add(sess)
    db.flush()
    return sess


def _upsert_driver_from_series(db: OrmSession, d: pd.Series) -> Driver:
    """Upsert a driver row from FastF1 DriverResult (pandas Series).

    Access fields exactly like in test_name.py, e.g. d["FirstName"].
    Expected keys: Abbreviation, DriverNumber, FirstName, LastName,
    TeamName, TeamColor.
    """

    def _get(key: str):
        try:
            val = d[key]
        except Exception:
            try:
                val = d.get(key)
            except Exception:
                val = None
        if val is None or (isinstance(val, float) and pd.isna(val)):
            return None
        if isinstance(val, str):
            s = val.strip()
            return s or None
        return val

    code = _get("Abbreviation")
    if not code:
        raise ValueError("DriverResult missing Abbreviation")
    dn = _get("DriverNumber")
    try:
        number = int(dn) if dn is not None else None
    except Exception:
        number = None
    first = _get("FirstName")
    last = _get("LastName")
    team_name = _get("TeamName")
    team_color = _get("TeamColor")

    drv = db.execute(select(Driver).where(Driver.code == code)).scalar_one_or_none()
    if drv:
        if number is not None:
            drv.number = number
        if first:
            drv.first_name = first
        if last:
            drv.last_name = last
        if team_name:
            drv.team_name = team_name
            drv.team = team_name
        if team_color:
            drv.team_color = team_color
        return drv

    drv = Driver(
        code=code,
        number=number,
        first_name=first,
        last_name=last,
        team_name=team_name,
        team_color=team_color,
        team=team_name,
    )
    db.add(drv)
    db.flush()
    return drv


# Use conversion helpers directly from utils


def load_fastf1_session(
    db: OrmSession,
    *,
    year: int,
    gp: int | str,
    session_type: str,
    cache_dir: Optional[str] = "cache",
    store_telemetry: bool = True,
    skip_if_exists: bool = False,
) -> dict:
    """
    Load a FastF1 session and persist Event, Session, Drivers, Laps and Telemetry.

    Args:
        year: Season year, e.g. 2024
        gp: Round number (int) or Event name (str), e.g. 1 or "Bahrain"
        session_type: One of FP1, FP2, FP3, Q, SQ, R, etc.
        cache_dir: FastF1 cache directory
        store_telemetry: If False, only store up to lap level

    Returns:
        Summary counts as a dict
    """
    if cache_dir:
        fastf1.Cache.enable_cache(cache_dir)

    fsession = fastf1.get_session(year, gp, session_type)
    # Load laps first; telemetry will be fetched per lap on demand
    fsession.load()

    # Upsert Event and Session
    ev = _upsert_event(db, fsession.event)
    sess = _upsert_session(db, ev.id, fsession, explicit_type=session_type)

    # If requested, skip if this session already has laps stored
    if skip_if_exists:
        from sqlalchemy import func
        existing_laps = db.execute(
            select(func.count()).select_from(Lap).where(Lap.session_id == sess.id)
        ).scalar_one()
        if existing_laps and int(existing_laps) > 0:
            # Provide a quick summary without reprocessing
            from sqlalchemy import distinct
            distinct_drivers = db.execute(
                select(func.count(distinct(Lap.driver_id))).where(Lap.session_id == sess.id)
            ).scalar_one()
            return {
                "event_id": ev.id,
                "session_id": sess.id,
                "drivers": int(distinct_drivers or 0),
                "laps": int(existing_laps or 0),
                "telemetry_rows": None,
                "skipped": True,
            }

    laps_df = fsession.laps  # pandas DataFrame-like
    if laps_df is None or len(laps_df) == 0:
        return {"event_id": ev.id, "session_id": sess.id, "drivers": 0, "laps": 0, "telemetry_rows": 0}

    # Ensure drivers via session.get_driver() per FastF1 docs
    code_to_driver: dict[str, Driver] = {}
    try:
        driver_ids = list(getattr(fsession, "drivers", []) or [])
    except Exception:
        driver_ids = []
    if driver_ids:
        for drv_id in driver_ids:
            try:
                dseries = fsession.get_driver(drv_id)
                drv = _upsert_driver_from_series(db, dseries)
                code = str(dseries.get("Abbreviation")).strip()
                if code:
                    code_to_driver[code] = drv
                # Per-event entry with team at this event
                try:
                    team_name = dseries.get("TeamName")
                    team_color = dseries.get("TeamColor")
                    _ensure_driver_entry(db, event_id=ev.id, driver_id=drv.id, team_name=team_name, team_color=team_color)
                except Exception:
                    pass
            except Exception:
                continue
    else:
        # Fallback to codes observed in laps
        codes = sorted(laps_df["Driver"].dropna().unique())
        for code in codes:
            try:
                dseries = fsession.get_driver(code)
                drv = _upsert_driver_from_series(db, dseries)
                code_to_driver[code] = drv
                try:
                    team_name = dseries.get("TeamName")
                    team_color = dseries.get("TeamColor")
                    _ensure_driver_entry(db, event_id=ev.id, driver_id=drv.id, team_name=team_name, team_color=team_color)
                except Exception:
                    pass
            except Exception:
                continue

    # Insert laps
    lap_count = 0
    tel_count = 0
    for _, row in laps_df.iterrows():
        code = row.get("Driver")
        drv = code_to_driver.get(code)
        if not drv:
            continue
        lap_number = to_int(row.get("LapNumber"))
        laptime_ms = to_ms(row.get("LapTime"))
        compound = row.get("Compound") if pd.notna(row.get("Compound")) else None
        position = to_int(row.get("Position"))
        tyre_life = to_float(row.get("TyreLife"))
        track_status = None
        try:
            ts_val = row.get("TrackStatus")
            if ts_val is not None and pd.notna(ts_val):
                track_status = str(ts_val).strip() or None
        except Exception:
            track_status = None

        # upsert lap
        lap = db.execute(
            select(Lap).where(
                Lap.session_id == sess.id,
                Lap.driver_id == drv.id,
                Lap.lap_number == (lap_number or 0),
            )
        ).scalar_one_or_none()
        if lap:
            lap.lap_time_ms = laptime_ms
            lap.compound = compound
            lap.position = position
            lap.tyre_life = tyre_life
            lap.track_status = track_status
        else:
            lap = Lap(
                session_id=sess.id,
                driver_id=drv.id,
                lap_number=lap_number or 0,
                lap_time_ms=laptime_ms,
                compound=compound,
                position=position,
                tyre_life=tyre_life,
                track_status=track_status,
            )
            db.add(lap)
            db.flush()  # assign lap.id for telemetry FK
        lap_count += 1

        if store_telemetry and lap_number:
            try:
                # FastF1 >= 3.1+: pick_drivers + pick_laps only (no deprecated fallbacks)
                subset = laps_df.pick_drivers(code)
                res = subset.pick_laps(lap_number)
                if res is None or len(res) == 0:
                    continue
                picked = res.iloc[0]
                # Telemetry: speed, rpm, gear, throttle, brake, drs, time
                tel = picked.get_car_data().add_distance()  # ensure Distance column
                merged = tel

                # Build telemetry rows
                records = []
                for _, trow in merged.iterrows():
                    time_s = timedelta_to_s(trow.get("Time")) if "Time" in merged.columns else None
                    brv = to_int(trow.get("Brake"))
                    rec = dict(
                        lap_id=lap.id,
                        time_s=time_s,
                        distance_m=to_float(trow.get("Distance")),
                        speed_kmh=to_float(trow.get("Speed")),
                        rpm=to_float(trow.get("RPM")),
                        gear=to_int(trow.get("nGear")),
                        throttle=to_float(trow.get("Throttle")),
                        brake=(None if brv is None else bool(brv)),
                        drs=to_int(trow.get("DRS")),
                    )
                    records.append(rec)
                if records:
                    # replace existing telemetry for this lap
                    db.execute(delete(Telemetry).where(Telemetry.lap_id == lap.id))
                    db.bulk_insert_mappings(Telemetry, records)
                    tel_count += len(records)
            except Exception:
                # skip telemetry for this lap on errors; continue with others
                pass

    return {
        "event_id": ev.id,
        "session_id": sess.id,
        "drivers": len(code_to_driver),
        "laps": lap_count,
        "telemetry_rows": tel_count,
    }


def _ensure_driver_entry(db: OrmSession, *, event_id: int, driver_id: int, team_name, team_color) -> None:
    """Create/update a per-event driver entry capturing team affiliation for historical queries."""
    entry = db.execute(
        select(DriverEntry).where(DriverEntry.event_id == event_id, DriverEntry.driver_id == driver_id)
    ).scalar_one_or_none()
    if entry:
        # Update only if values present; keep historical record consistent with latest load for the event
        if team_name:
            entry.team_name = str(team_name)
        if team_color:
            entry.team_color = str(team_color)
        return
    db.add(
        DriverEntry(
            event_id=event_id,
            driver_id=driver_id,
            team_name=(str(team_name) if team_name else None),
            team_color=(str(team_color) if team_color else None),
        )
    )


def _resolve_schedule_row(year: int, gp: int | str) -> Optional[pd.Series]:
    """Find the event row (by round number or name) from the FastF1 schedule."""
    try:
        sched = fastf1.get_event_schedule(year, include_testing=False)
    except Exception:
        return None
    row = None
    if isinstance(gp, int):
        try:
            row = sched.loc[sched["RoundNumber"] == gp].iloc[0]
        except Exception:
            return None
    else:
        name = str(gp).strip().lower()
        try:
            row = sched.loc[sched["EventName"].str.lower() == name].iloc[0]
        except Exception:
            # partial contains match as fallback
            try:
                row = sched.loc[sched["EventName"].str.lower().str.contains(name, regex=False)].iloc[0]
            except Exception:
                return None
    return row


def _normalize_session_name(name: str) -> Optional[str]:
    """Map a human session name to our abbreviation.

    Abbreviations: FP1, FP2, FP3, Q, S, SS, SQ, R
    - Sprint Shootout -> SS
    - Sprint Qualifying -> SQ
    - Qualifying -> Q
    - Sprint -> S
    - Race -> R
    - Practice 1/2/3 -> FP1/FP2/FP3
    """
    if not name:
        return None
    nl = str(name).strip().lower()
    # Practice
    if nl in {"practice 1", "fp1", "free practice 1", "p1"}:
        return "FP1"
    if nl in {"practice 2", "fp2", "free practice 2", "p2"}:
        return "FP2"
    if nl in {"practice 3", "fp3", "free practice 3", "p3"}:
        return "FP3"
    # Sprint variants
    if "sprint shootout" in nl or nl == "ss":
        return "SS"
    if "sprint qualifying" in nl or nl == "sq":
        return "SQ"
    if nl == "sprint" or ("sprint" in nl and "qualifying" not in nl and "shootout" not in nl):
        return "S"
    # Qualifying and Race
    if nl == "qualifying" or nl == "q":
        return "Q"
    if nl == "race" or nl == "r":
        return "R"
    return None


def _extract_sessions_from_row(row: pd.Series) -> List[Tuple[str, pd.Timestamp]]:
    """Extract present sessions and map to FastF1 session codes with timestamps.

    Returns list of (session_type, datetime) tuples.
    """
    mapping = [
        ("FP1", "FP1"),
        ("FP2", "FP2"),
        ("FP3", "FP3"),
        ("Qualifying", "Q"),
        ("Sprint Qualifying", "SQ"),
        ("SprintShootout", "SS"),
        ("Sprint Shootout", "SS"),
        ("Sprint", "S"),
        ("Race", "R"),
    ]
    sessions: List[Tuple[str, pd.Timestamp]] = []
    for col, code in mapping:
        if col in row.index:
            val = row[col]
            if pd.notna(val):
                try:
                    ts = pd.to_datetime(val)
                    sessions.append((code, ts))
                except Exception:
                    pass
    # Some FastF1 versions have Session1..Session5 columns with names
    if not sessions:
        for i in range(1, 7):
            scol = f"Session{i}"
            dcol = f"Session{i}Date"
            if scol in row.index and dcol in row.index:
                name = str(row[scol]) if pd.notna(row[scol]) else None
                dt = row[dcol]
                if name and pd.notna(dt):
                    code = _normalize_session_name(name)
                    if not code:
                        continue
                    try:
                        ts = pd.to_datetime(dt)
                        sessions.append((code, ts))
                    except Exception:
                        pass
    return sorted(sessions, key=lambda x: x[1])


def list_event_sessions(year: int, gp: int | str) -> List[Tuple[str, pd.Timestamp]]:
    """Return available session types for an event ordered by time."""
    row = _resolve_schedule_row(year, gp)
    sessions = _extract_sessions_from_row(row) if row is not None else []
    if sessions:
        return sessions
    # Fallback: probe known types for date metadata without loading data
    candidates = ["FP1", "FP2", "FP3", "SQ", "SS", "S", "Q", "R"]
    found: List[Tuple[str, pd.Timestamp]] = []
    for t in candidates:
        try:
            s = fastf1.get_session(year, gp, t)
            if getattr(s, "date", None) is not None:
                found.append((t, pd.to_datetime(s.date)))
        except Exception:
            pass
    return sorted(found, key=lambda x: x[1])


def load_event_weekend(
    db: OrmSession,
    *,
    year: int,
    gp: int | str,
    cache_dir: Optional[str] = "cache",
    store_telemetry: bool = True,
    skip_if_exists: bool = False,
) -> list[dict]:
    """Load all available sessions for an event in chronological order."""
    sessions = list_event_sessions(year, gp)
    results: list[dict] = []
    for stype, _ in sessions:
        res = load_fastf1_session(
            db,
            year=year,
            gp=gp,
            session_type=stype,
            cache_dir=cache_dir,
            store_telemetry=store_telemetry,
            skip_if_exists=skip_if_exists,
        )
        res["session_type"] = stype
        results.append(res)
    return results
