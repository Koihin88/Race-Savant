from __future__ import annotations

from typing import Dict, Iterator, List, Optional, Tuple
from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session as OrmSession

from db import create_engine_and_session, db_session
from models import Driver, Event, Lap, Session as DbSession, Telemetry
import pandas as pd
import fastf1
from fastf1.ergast import Ergast


app = FastAPI(title="Race Savant API", version="0.1.0")


# --- DB wiring (sync SQLAlchemy with dependency) ---
engine, SessionLocal = create_engine_and_session()


def get_db() -> Iterator[OrmSession]:
    with db_session(SessionLocal) as session:
        yield session


# --- Pydantic models ---
class YearItem(BaseModel):
    year: int
    events: int
    sessions: int
    laps: int


class EventItem(BaseModel):
    id: int
    year: int
    round: Optional[int] = None
    name: Optional[str] = None
    location: Optional[str] = None
    country: Optional[str] = None
    date: Optional[str] = None  # ISO date
    session_types: List[str]


class SessionItem(BaseModel):
    id: int
    type: Optional[str] = None
    date: Optional[str] = None  # ISO datetime


class DriverItem(BaseModel):
    id: int
    code: Optional[str] = None
    number: Optional[int] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    team_name: Optional[str] = None
    team_color: Optional[str] = None


class LapItem(BaseModel):
    lap_number: int
    lap_time_ms: Optional[int] = None
    position: Optional[int] = None
    compound: Optional[str] = None
    track_status: Optional[str] = None


class LapTelemetry(BaseModel):
    session_id: int
    driver_id: int
    lap_number: int
    time_s: List[Optional[float]]
    distance_m: List[Optional[float]]
    speed_kmh: List[Optional[float]]
    rpm: List[Optional[float]]
    gear: List[Optional[int]]
    throttle: List[Optional[float]]
    brake: List[Optional[bool]]
    drs: List[Optional[int]]  # raw DRS channel; frontend decides ON/OFF
    meta: LapItem


# --- Telemetry navigation endpoints ---


@app.get("/telemetry/years", response_model=List[YearItem], summary="List years with data")
def list_years(db: OrmSession = Depends(get_db)):
    # Count events/sessions/laps per year based on stored data
    q = (
        db.query(
            Event.year.label("year"),
            func.count(func.distinct(Event.id)).label("events"),
            func.count(func.distinct(DbSession.id)).label("sessions"),
            func.count(func.distinct(Lap.id)).label("laps"),
        )
        .select_from(Event)
        .join(DbSession, DbSession.event_id == Event.id)
        .join(Lap, Lap.session_id == DbSession.id)
        .group_by(Event.year)
        .order_by(Event.year)
    )
    return [YearItem(**row._asdict()) for row in q]


@app.get(
    "/telemetry/events",
    response_model=List[EventItem],
    summary="List events with stored telemetry",
)
def list_events(
    year: Optional[int] = Query(None, description="Filter by year"),
    db: OrmSession = Depends(get_db),
):
    # Base query: events that have at least one lap
    base = (
        db.query(Event)
        .join(DbSession, DbSession.event_id == Event.id)
        .join(Lap, Lap.session_id == DbSession.id)
        .group_by(Event.id)
    )
    if year is not None:
        base = base.filter(Event.year == year)

    # Collect session types per event
    rows = base.all()
    results: List[EventItem] = []
    for ev in rows:
        stypes = (
            db.query(DbSession.type)
            .join(Lap, Lap.session_id == DbSession.id)
            .filter(DbSession.event_id == ev.id)
            .distinct()
            .order_by(DbSession.type)
            .all()
        )
        types = [t[0] for t in stypes if t[0] is not None]
        results.append(
            EventItem(
                id=ev.id,
                year=ev.year,
                round=ev.round,
                name=ev.name,
                location=ev.location,
                country=ev.country,
                date=(ev.date.isoformat() if getattr(ev, "date", None) else None),
                session_types=types,
            )
        )
    return results


@app.get(
    "/telemetry/events/{event_id}/sessions",
    response_model=List[SessionItem],
    summary="List sessions for an event",
)
def list_sessions(event_id: int, db: OrmSession = Depends(get_db)):
    rows = (
        db.query(DbSession)
        .join(Lap, Lap.session_id == DbSession.id)
        .filter(DbSession.event_id == event_id)
        .group_by(DbSession.id)
        .order_by(DbSession.date)
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No sessions found for event")
    return [
        SessionItem(
            id=s.id,
            type=s.type,
            date=(s.date.isoformat() if getattr(s, "date", None) else None),
        )
        for s in rows
    ]


@app.get(
    "/telemetry/sessions/{session_id}/drivers",
    response_model=List[DriverItem],
    summary="List drivers with laps for a session",
)
def list_drivers(session_id: int, db: OrmSession = Depends(get_db)):
    rows = (
        db.query(Driver)
        .join(Lap, Lap.driver_id == Driver.id)
        .filter(Lap.session_id == session_id)
        .group_by(Driver.id)
        .order_by(Driver.number)
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No drivers found for session")
    return [
        DriverItem(
            id=d.id,
            code=d.code,
            number=d.number,
            first_name=d.first_name,
            last_name=d.last_name,
            team_name=d.team_name,
            team_color=d.team_color,
        )
        for d in rows
    ]


@app.get(
    "/telemetry/sessions/{session_id}/drivers/{driver_id}/laps",
    response_model=List[LapItem],
    summary="List laps for a driver in session",
)
def list_laps(session_id: int, driver_id: int, db: OrmSession = Depends(get_db)):
    rows = db.query(Lap).filter(Lap.session_id == session_id, Lap.driver_id == driver_id).order_by(Lap.lap_number).all()
    if not rows:
        raise HTTPException(status_code=404, detail="No laps found for driver in session")
    return [
        LapItem(
            lap_number=l.lap_number,
            lap_time_ms=l.lap_time_ms,
            position=l.position,
            compound=l.compound,
            track_status=l.track_status,
        )
        for l in rows
    ]


@app.get(
    "/telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}",
    response_model=LapTelemetry,
    summary="Fetch telemetry arrays for a lap",
)
def get_lap_telemetry(session_id: int, driver_id: int, lap_number: int, db: OrmSession = Depends(get_db)):
    lap = (
        db.query(Lap)
        .filter(
            Lap.session_id == session_id,
            Lap.driver_id == driver_id,
            Lap.lap_number == lap_number,
        )
        .first()
    )
    if not lap:
        raise HTTPException(status_code=404, detail="Lap not found")
    teles = db.query(Telemetry).filter(Telemetry.lap_id == lap.id).order_by(Telemetry.time_s).all()
    # Build arrays (raw values; frontend applies any visualization rules like DRS)
    time_s = [t.time_s for t in teles]
    distance_m = [t.distance_m for t in teles]
    speed_kmh = [t.speed_kmh for t in teles]
    rpm = [t.rpm for t in teles]
    gear = [t.gear for t in teles]
    throttle = [t.throttle for t in teles]
    brake = [t.brake for t in teles]
    drs = [t.drs for t in teles]

    meta = LapItem(
        lap_number=lap.lap_number,
        lap_time_ms=lap.lap_time_ms,
        position=lap.position,
        compound=lap.compound,
        track_status=lap.track_status,
    )
    return LapTelemetry(
        session_id=session_id,
        driver_id=driver_id,
        lap_number=lap_number,
        time_s=time_s,
        distance_m=distance_m,
        speed_kmh=speed_kmh,
        rpm=rpm,
        gear=gear,
        throttle=throttle,
        brake=brake,
        drs=drs,
        meta=meta,
    )


# --- Schedule (Fast-F1, no DB storage) ---


class ScheduleEventItem(BaseModel):
    RoundNumber: int | None = None
    Country: str | None = None
    Location: str | None = None
    EventName: str | None = None
    EventDate: str | None = None
    Session1: str | None = None
    Session1DateUtc: str | None = None
    Session2: str | None = None
    Session2DateUtc: str | None = None
    Session3: str | None = None
    Session3DateUtc: str | None = None
    Session4: str | None = None
    Session4DateUtc: str | None = None
    Session5: str | None = None
    Session5DateUtc: str | None = None


def _to_iso_utc(val) -> str | None:
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return None
    try:
        ts = pd.to_datetime(val, utc=True)
        return ts.isoformat().replace("+00:00", "Z")
    except Exception:
        return None


@app.get("/schedule/{year}", response_model=list[ScheduleEventItem], summary="Season event schedule via Fast-F1")
def get_schedule(year: int, include_testing: bool = False):
    try:
        sched = fastf1.get_event_schedule(year, include_testing=include_testing)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load schedule: {e}")

    items: list[ScheduleEventItem] = []
    for _, row in sched.iterrows():
        # Prefer explicit SessionN/SessionNDateUtc fields if present; fall back to known names
        def getv(name: str):
            try:
                v = row[name]
                if isinstance(v, str) and not v:
                    return None
                return v
            except Exception:
                return None

        def session_pair(n: int):
            sname = getv(f"Session{n}")
            sdt = getv(f"Session{n}DateUtc") or getv(f"Session{n}Date")
            return sname, _to_iso_utc(sdt)

        ev = ScheduleEventItem(
            RoundNumber=int(getv("RoundNumber") or 0) or None,
            Country=(getv("Country") or None),
            Location=(getv("Location") or getv("EventLocation") or None),
            EventName=(getv("EventName") or None),
            EventDate=_to_iso_utc(getv("EventDate")),
        )
        # fill up to 5 sessions
        for i in range(1, 6):
            name, dt = session_pair(i)
            setattr(ev, f"Session{i}", name if name else None)
            setattr(ev, f"Session{i}DateUtc", dt)
        items.append(ev)
    return items


# --- Helpers to resolve by year/round/session and driver code ---


def _normalize_session_type(stype: str) -> str:
    if not stype:
        return stype
    s = stype.strip().lower()
    aliases = {
        "r": "R",
        "race": "R",
        "q": "Q",
        "qualifying": "Q",
        "s": "S",
        "sprint": "S",
        "ss": "SS",
        "sprint_shootout": "SS",
        "sprintshootout": "SS",
        "fp1": "FP1",
        "practice1": "FP1",
        "practice 1": "FP1",
        "fp2": "FP2",
        "practice2": "FP2",
        "practice 2": "FP2",
        "fp3": "FP3",
        "practice3": "FP3",
        "practice 3": "FP3",
    }
    return aliases.get(s, stype.upper())


def _resolve_event_session(
    db: OrmSession, *, year: int, round_number: int, session_type: str
) -> Tuple[Event, DbSession]:
    stype = _normalize_session_type(session_type)
    ev = (
        db.query(Event)
        .filter(Event.year == year, Event.round == round_number)
        .first()
    )
    if not ev:
        raise HTTPException(status_code=404, detail="Event not found for year/round")
    sess = (
        db.query(DbSession)
        .filter(DbSession.event_id == ev.id, DbSession.type == stype)
        .first()
    )
    if not sess:
        raise HTTPException(status_code=404, detail="Session not found for given event and type")
    return ev, sess


def _resolve_driver_by_code(db: OrmSession, *, code: str) -> Driver:
    d = db.query(Driver).filter(func.upper(Driver.code) == code.strip().upper()).first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver not found")
    return d


# --- Round-based routes (more human-friendly) ---


@app.get(
    "/telemetry/{year}/{round_number}/{session_type}/drivers",
    response_model=List[DriverItem],
    summary="List drivers with laps for a year/round/session",
)
def list_drivers_by_round(
    year: int, round_number: int, session_type: str, db: OrmSession = Depends(get_db)
):
    _, sess = _resolve_event_session(db, year=year, round_number=round_number, session_type=session_type)
    rows = (
        db.query(Driver)
        .join(Lap, Lap.driver_id == Driver.id)
        .filter(Lap.session_id == sess.id)
        .group_by(Driver.id)
        .order_by(Driver.number)
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No drivers found for session")
    return [
        DriverItem(
            id=d.id,
            code=d.code,
            number=d.number,
            first_name=d.first_name,
            last_name=d.last_name,
            team_name=d.team_name,
            team_color=d.team_color,
        )
        for d in rows
    ]


@app.get(
    "/telemetry/{year}/{round_number}/{session_type}/drivers/{driver_code}/laps",
    response_model=List[LapItem],
    summary="List laps for a driver by year/round/session",
)
def list_laps_by_round(
    year: int,
    round_number: int,
    session_type: str,
    driver_code: str,
    db: OrmSession = Depends(get_db),
):
    _, sess = _resolve_event_session(db, year=year, round_number=round_number, session_type=session_type)
    drv = _resolve_driver_by_code(db, code=driver_code)
    rows = (
        db.query(Lap)
        .filter(Lap.session_id == sess.id, Lap.driver_id == drv.id)
        .order_by(Lap.lap_number)
        .all()
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No laps found for driver in session")
    return [
        LapItem(
            lap_number=l.lap_number,
            lap_time_ms=l.lap_time_ms,
            position=l.position,
            compound=l.compound,
            track_status=l.track_status,
        )
        for l in rows
    ]


@app.get(
    "/telemetry/{year}/{round_number}/{session_type}/{driver_code}/{lap_number}",
    response_model=LapTelemetry,
    summary="Fetch telemetry arrays for a lap via year/round/session/driver",
)
def get_lap_telemetry_by_round(
    year: int,
    round_number: int,
    session_type: str,
    driver_code: str,
    lap_number: int,
    db: OrmSession = Depends(get_db),
):
    _, sess = _resolve_event_session(db, year=year, round_number=round_number, session_type=session_type)
    drv = _resolve_driver_by_code(db, code=driver_code)
    lap = (
        db.query(Lap)
        .filter(
            Lap.session_id == sess.id,
            Lap.driver_id == drv.id,
            Lap.lap_number == lap_number,
        )
        .first()
    )
    if not lap:
        raise HTTPException(status_code=404, detail="Lap not found")
    teles = db.query(Telemetry).filter(Telemetry.lap_id == lap.id).order_by(Telemetry.time_s).all()
    time_s = [t.time_s for t in teles]
    distance_m = [t.distance_m for t in teles]
    speed_kmh = [t.speed_kmh for t in teles]
    rpm = [t.rpm for t in teles]
    gear = [t.gear for t in teles]
    throttle = [t.throttle for t in teles]
    brake = [t.brake for t in teles]
    drs = [t.drs for t in teles]

    meta = LapItem(
        lap_number=lap.lap_number,
        lap_time_ms=lap.lap_time_ms,
        position=lap.position,
        compound=lap.compound,
        track_status=lap.track_status,
    )
    return LapTelemetry(
        session_id=sess.id,
        driver_id=drv.id,
        lap_number=lap_number,
        time_s=time_s,
        distance_m=distance_m,
        speed_kmh=speed_kmh,
        rpm=rpm,
        gear=gear,
        throttle=throttle,
        brake=brake,
        drs=drs,
        meta=meta,
    )


# --- Race positions (per-lap) ---


class DriverPositionsItem(BaseModel):
    driver_code: str
    positions: List[Optional[int]]


class RacePositions(BaseModel):
    session_id: int
    year: int
    round: int
    session_type: str
    laps: int
    drivers: List[DriverPositionsItem]


@app.get(
    "/telemetry/{year}/{round_number}/{session_type}/positions",
    response_model=RacePositions,
    summary="All drivers' lap-by-lap positions for a session",
)
def get_race_positions(
    year: int, round_number: int, session_type: str, db: OrmSession = Depends(get_db)
):
    ev, sess = _resolve_event_session(db, year=year, round_number=round_number, session_type=session_type)

    max_lap = (
        db.query(func.max(Lap.lap_number)).filter(Lap.session_id == sess.id).scalar()
    )
    if not max_lap or max_lap <= 0:
        raise HTTPException(status_code=404, detail="No laps found for session")

    # Initialize positions arrays per driver code
    drivers_rows = (
        db.query(Driver.code, Driver.id)
        .join(Lap, Lap.driver_id == Driver.id)
        .filter(Lap.session_id == sess.id)
        .group_by(Driver.id)
        .all()
    )
    positions_map: Dict[str, List[Optional[int]]] = {
        code: [None] * int(max_lap) for code, _ in drivers_rows
    }

    # Fill positions
    laps_rows = (
        db.query(Driver.code, Lap.lap_number, Lap.position)
        .join(Driver, Driver.id == Lap.driver_id)
        .filter(Lap.session_id == sess.id)
        .order_by(Driver.code, Lap.lap_number)
        .all()
    )
    for code, lap_no, pos in laps_rows:
        if 1 <= int(lap_no) <= int(max_lap):
            positions_map[code][int(lap_no) - 1] = pos

    items = [
        DriverPositionsItem(driver_code=code, positions=positions)
        for code, positions in sorted(positions_map.items())
    ]
    return RacePositions(
        session_id=sess.id,
        year=ev.year,
        round=ev.round or round_number,
        session_type=_normalize_session_type(session_type),
        laps=int(max_lap),
        drivers=items,
    )


# --- Standings (Ergast via FastF1) ---


class StandingSeries(BaseModel):
    code: str
    points: List[Optional[float]]


class StandingsProgress(BaseModel):
    season: int
    rounds: int
    entries: List[StandingSeries]


def _find_col(columns: List[str], candidates: List[str]) -> Optional[str]:
    cols = [c.lower() for c in columns]
    for cand in candidates:
        if cand.lower() in cols:
            # return original-cased name
            return columns[cols.index(cand.lower())]
    return None


@app.get(
    "/standings/{season}/drivers",
    response_model=StandingsProgress,
    summary="Driver standings progression across rounds (Ergast)",
)
def driver_standings_progress(season: int):
    try:
        ergast = Ergast()
        latest = ergast.get_driver_standings(season=season)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Failed to load Ergast data: {e}")

    try:
        num_rounds = int(latest.description.get("round", 0))
    except Exception:
        num_rounds = 0
    if num_rounds <= 0:
        raise HTTPException(status_code=404, detail="No standings rounds available for season")

    all_parts: List[pd.DataFrame] = []
    for rnd in range(1, num_rounds + 1):
        res = ergast.get_driver_standings(season=season, round=rnd)
        if not getattr(res, "content", None):
            continue
        df = res.content[0].copy()
        if df is None or df.empty:
            continue
        df["round"] = rnd
        # Normalize columns
        code_col = _find_col(list(df.columns), ["driverCode", "code", "driver", "driverId"])
        if not code_col:
            # fallback: compose from name columns if present
            first = _find_col(list(df.columns), ["givenName", "firstName"]) or ""
            last = _find_col(list(df.columns), ["familyName", "lastName"]) or ""
            if first and last:
                df["driverCode"] = (df[first].str[:1] + df[last].str[:2]).str.upper()
                code_col = "driverCode"
            else:
                code_col = df.columns[0]
        pts_col = _find_col(list(df.columns), ["points"]) or "points"
        # Ensure numeric points
        df[pts_col] = pd.to_numeric(df[pts_col], errors="coerce")
        all_parts.append(df[[code_col, "round", pts_col]].rename(columns={code_col: "code", pts_col: "points"}))

    if not all_parts:
        raise HTTPException(status_code=404, detail="No standings data found")

    combined = pd.concat(all_parts, ignore_index=True)
    # Pivot: index by driver code, columns by round
    table = combined.pivot(index="code", columns="round", values="points").sort_index()
    # Build response
    entries = []
    for code, row in table.iterrows():
        pts = [None] * num_rounds
        for rnd, value in row.items():
            if 1 <= int(rnd) <= num_rounds:
                pts[int(rnd) - 1] = None if pd.isna(value) else float(value)
        entries.append(StandingSeries(code=str(code), points=pts))
    return StandingsProgress(season=season, rounds=num_rounds, entries=entries)


@app.get(
    "/standings/{season}/constructors",
    response_model=StandingsProgress,
    summary="Constructor standings progression across rounds (Ergast)",
)
def constructor_standings_progress(season: int):
    try:
        ergast = Ergast()
        latest = ergast.get_constructor_standings(season=season)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Failed to load Ergast data: {e}")

    try:
        num_rounds = int(latest.description.get("round", 0))
    except Exception:
        num_rounds = 0
    if num_rounds <= 0:
        raise HTTPException(status_code=404, detail="No standings rounds available for season")

    all_parts: List[pd.DataFrame] = []
    for rnd in range(1, num_rounds + 1):
        res = ergast.get_constructor_standings(season=season, round=rnd)
        if not getattr(res, "content", None):
            continue
        df = res.content[0].copy()
        if df is None or df.empty:
            continue
        df["round"] = rnd
        name_col = _find_col(list(df.columns), ["constructorRef", "constructorId", "constructor", "name", "team"])
        if not name_col:
            name_col = df.columns[0]
        pts_col = _find_col(list(df.columns), ["points"]) or "points"
        df[pts_col] = pd.to_numeric(df[pts_col], errors="coerce")
        all_parts.append(df[[name_col, "round", pts_col]].rename(columns={name_col: "code", pts_col: "points"}))

    if not all_parts:
        raise HTTPException(status_code=404, detail="No standings data found")

    combined = pd.concat(all_parts, ignore_index=True)
    table = combined.pivot(index="code", columns="round", values="points").sort_index()
    entries = []
    for code, row in table.iterrows():
        pts = [None] * num_rounds
        for rnd, value in row.items():
            if 1 <= int(rnd) <= num_rounds:
                pts[int(rnd) - 1] = None if pd.isna(value) else float(value)
        entries.append(StandingSeries(code=str(code), points=pts))
    return StandingsProgress(season=season, rounds=num_rounds, entries=entries)


if __name__ == "__main__":
    # Run with: python backend/api.py  (or `uvicorn backend.api:app --reload`)
    import uvicorn

    uvicorn.run("backend.api:app", host="0.0.0.0", port=8000, reload=True)
