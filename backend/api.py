from __future__ import annotations

import random
from typing import Iterator, List, Optional

import os
from fastapi import Depends, FastAPI, HTTPException, Query, Body, Header
from pydantic import BaseModel
from sqlalchemy import func, select, distinct
from sqlalchemy.orm import Session as OrmSession

from db import create_engine_and_session, db_session
from models import Driver, Event, Lap, Session as DbSession, Telemetry
import pandas as pd
import fastf1
from etl import list_event_sessions, load_fastf1_session


app = FastAPI(title="Race Savant API", version="0.1.0")

# CORS (dev-friendly; restrict via env if desired)
try:
    from fastapi.middleware.cors import CORSMiddleware

    allowed_origins = os.getenv("CORS_ALLOW_ORIGINS", "*")
    origins = [o.strip() for o in allowed_origins.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"]
    )
except Exception:
    pass


# --- DB wiring (sync SQLAlchemy with dependency) ---
engine, SessionLocal = create_engine_and_session()


def get_db() -> Iterator[OrmSession]:
    with db_session(SessionLocal) as session:
        yield session


# --- Simple Admin auth (optional) ---
def require_admin(x_admin_token: str | None = Header(default=None)):
    """If ADMIN_TOKEN env var is set, require 'X-Admin-Token' header to match.

    If ADMIN_TOKEN is not set, allow all (dev convenience).
    """
    expected = os.getenv("ADMIN_TOKEN")
    if not expected:
        return True
    if not x_admin_token or x_admin_token != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True


# --- Health/Test Endpoint ---
EMOJIS = ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯"]


@app.get("/", summary="Hello test endpoint")
def hello():
    suffix = "".join(random.sample(EMOJIS, k=3))
    return {"message": f"Hello, world {suffix}"}


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
    rows = (
        db.query(Lap)
        .filter(Lap.session_id == session_id, Lap.driver_id == driver_id)
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
    "/telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}",
    response_model=LapTelemetry,
    summary="Fetch telemetry arrays for a lap",
)
def get_lap_telemetry(
    session_id: int, driver_id: int, lap_number: int, db: OrmSession = Depends(get_db)
):
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
    teles = (
        db.query(Telemetry)
        .filter(Telemetry.lap_id == lap.id)
        .order_by(Telemetry.time_s)
        .all()
    )
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


# --- Admin: Overview + Load/Delete sessions ---

class AdminSessionStatus(BaseModel):
    type: str
    scheduled_utc: Optional[str] = None
    session_id: Optional[int] = None
    laps: int = 0
    drivers: int = 0
    telemetry_rows: Optional[int] = None


class AdminEventOverview(BaseModel):
    round: Optional[int] = None
    name: Optional[str] = None
    location: Optional[str] = None
    country: Optional[str] = None
    date: Optional[str] = None
    event_id: Optional[int] = None
    sessions: list[AdminSessionStatus]


@app.get(
    "/admin/overview/{year}",
    response_model=list[AdminEventOverview],
    summary="List season events with session load status",
)
def admin_overview(year: int, db: OrmSession = Depends(get_db), _: bool = Depends(require_admin)):
    try:
        sched = fastf1.get_event_schedule(year, include_testing=False)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load schedule: {e}")

    overviews: list[AdminEventOverview] = []
    for _, row in sched.iterrows():
        try:
            rnd = int(row.get("RoundNumber", 0))
        except Exception:
            rnd = 0
        if rnd < 1:
            continue
        name = row.get("EventName")
        location = row.get("Location") or row.get("EventLocation")
        country = row.get("Country")
        date = _to_iso_utc(row.get("EventDate"))
        # Match an existing DB event if loaded
        ev_row = db.execute(select(Event).where(Event.year == year, Event.name == name)).scalar_one_or_none()
        event_id = ev_row.id if ev_row else None

        # Extract scheduled sessions for this event
        sessions = []
        from etl import _extract_sessions_from_row  # reuse helper

        try:
            sess_pairs = _extract_sessions_from_row(row)
        except Exception:
            sess_pairs = []
        # Build status for each scheduled session code
        for code, ts in sess_pairs:
            # Normalize schedule type to our canonical codes to match stored rows
            norm = code
            try:
                from etl import _normalize_session_name as norm_fn
                norm = norm_fn(code) or code
            except Exception:
                pass
            status = AdminSessionStatus(type=code, scheduled_utc=(pd.to_datetime(ts, utc=True).isoformat().replace("+00:00", "Z") if ts is not None else None))
            if event_id is not None:
                srow = db.execute(
                    select(DbSession).where(DbSession.event_id == event_id, DbSession.type == norm)
                ).scalar_one_or_none()
                if srow is not None:
                    status.session_id = srow.id
                    # counts
                    lc = db.execute(select(func.count()).select_from(Lap).where(Lap.session_id == srow.id)).scalar_one()
                    dc = db.execute(
                        select(func.count(distinct(Lap.driver_id))).where(Lap.session_id == srow.id)
                    ).scalar_one()
                    status.laps = int(lc or 0)
                    status.drivers = int(dc or 0)
            sessions.append(status)

        overviews.append(
            AdminEventOverview(
                round=rnd,
                name=name,
                location=location,
                country=country,
                date=date,
                event_id=event_id,
                sessions=sessions,
            )
        )
    # sort by round
    overviews.sort(key=lambda x: (x.round or 0))
    return overviews


class AdminLoadRequest(BaseModel):
    year: int
    gp: str | int
    session_type: str
    store_telemetry: bool = True
    skip_if_exists: bool = False


@app.post("/admin/load", summary="Load a session into DB via FastF1")
def admin_load(req: AdminLoadRequest, db: OrmSession = Depends(get_db), _: bool = Depends(require_admin)):
    gp_val = req.gp
    if isinstance(gp_val, str) and gp_val.isdigit():
        gp_val = int(gp_val)
    try:
        res = load_fastf1_session(
            db,
            year=req.year,
            gp=gp_val,
            session_type=req.session_type,
            cache_dir="cache",
            store_telemetry=req.store_telemetry,
            skip_if_exists=req.skip_if_exists,
        )
        return res
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Load failed: {e}")


@app.delete("/admin/sessions/{session_id}", summary="Delete a session and related data")
def admin_delete_session(session_id: int, db: OrmSession = Depends(get_db), _: bool = Depends(require_admin)):
    srow = db.execute(select(DbSession).where(DbSession.id == session_id)).scalar_one_or_none()
    if srow is None:
        raise HTTPException(status_code=404, detail="Session not found")
    # Cascades will remove laps and telemetry
    db.delete(srow)
    return {"deleted_session_id": session_id}


if __name__ == "__main__":
    # Run with: python backend/api.py  (or `uvicorn backend.api:app --reload`)
    import uvicorn

    uvicorn.run("backend.api:app", host="0.0.0.0", port=8000, reload=True)
