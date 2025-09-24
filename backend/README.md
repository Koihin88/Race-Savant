# Race Savant Backend (FastAPI + SQLAlchemy)

FastAPI service that stores per‑lap telemetry from Fast‑F1 into Postgres and exposes read APIs for the iOS app and an admin dashboard. Schedules and standings are not stored in the DB (fetched directly from third parties by clients).

## Quick Start

Requirements
- Python 3.11+
- Postgres reachable via `DATABASE_URL`
- Dependencies from `requirements.txt` (includes FastAPI, SQLAlchemy, Fast‑F1, psycopg v3)

Environment
- `DATABASE_URL` (required): e.g. `postgresql+psycopg://user:pass@localhost:5432/racesavant`
  - Shorthand `postgres://...` is auto‑normalized to `postgresql+psycopg://...`.
- `ADMIN_TOKEN` (optional): if set, admin routes require header `X-Admin-Token: <token>`.
- `CORS_ALLOW_ORIGINS` (optional): comma‑separated list; defaults to `*`.

Run
```bash
cd backend
uvicorn api:app --reload
# or from repo root
uvicorn backend.api:app --reload
```

Initialize schema (idempotent)
```bash
python - << 'PY'
from etl import init_db
from db import create_engine_and_session
engine, _ = create_engine_and_session()
init_db(engine)
print('DB initialized')
PY
```

OpenAPI: visit `/docs` or `/redoc` once server is running.

## Data Model

Defined in `backend/models.py` (SQLAlchemy) and created by `etl.init_db(...)` with extra idempotent DDL in `migrations.py`.

### events
- `id` int PK
- `year` int (indexed)
- `round` int nullable
- `location` str nullable
- `country` str nullable
- `name` str nullable (Fast‑F1 EventName)
- `date` date nullable
- Unique: `(year, name)`
- Relationships: `sessions` (one‑to‑many)

### sessions
- `id` int PK
- `event_id` FK → `events.id` (CASCADE), indexed
- `type` str (indexed). Canonical codes: `FP1`, `FP2`, `FP3`, `Q`, `SQ`, `SS`, `S`, `R`
- `date` datetime nullable
- Unique: `(event_id, type)`
- Relationships: `laps` (one‑to‑many)

### drivers
- `id` int PK
- `code` str(3) (indexed, unique) — Fast‑F1 Abbreviation
- `number` int nullable — race number
- `first_name` str nullable
- `last_name` str nullable
- `team_name` str nullable — most recent team as last seen in any load
- `team_color` str nullable (hex)
- `team` str nullable — legacy alias retained for compatibility
- Relationships: `laps` (one‑to‑many)

### driver_entries
- `id` int PK
- `event_id` FK → `events.id` (CASCADE), indexed
- `driver_id` FK → `drivers.id` (CASCADE), indexed
- `team_name` str nullable — driver’s team at this event
- `team_color` str nullable (hex)
- Unique: `(event_id, driver_id)`
- Purpose: preserves historical driver↔team at each event (so earlier rounds show the correct team even if a driver switches teams later).

### laps
- `id` int PK
- `session_id` FK → `sessions.id` (CASCADE), indexed
- `driver_id` FK → `drivers.id` (RESTRICT), indexed
- `lap_number` int (indexed)
- `lap_time_ms` int nullable
- `compound` str nullable
- `position` int nullable
- `tyre_life` float nullable
- `track_status` str nullable
- Unique: `(session_id, driver_id, lap_number)`
- Relationships: `telemetries` (one‑to‑many)

### telemetry
- `id` bigserial PK
- `lap_id` FK → `laps.id` (CASCADE), indexed
- `time_s` float nullable — seconds within lap (from Fast‑F1 Time as seconds)
- `distance_m` float nullable — cumulative distance within lap
- `speed_kmh` float nullable
- `rpm` float nullable
- `gear` int nullable
- `throttle` float nullable
- `brake` bool nullable
- `drs` int nullable — raw DRS channel; frontend should treat {10, 12, 14} as “ON”

### Session Type Normalization
ETL maps human names to canonical codes stored in DB:
- Practice 1/2/3 → `FP1`/`FP2`/`FP3`
- Qualifying → `Q`
- Sprint Qualifying → `SQ`
- Sprint Shootout → `SS`
- Sprint → `S`
- Race → `R`
Helper functions: `etl._normalize_session_name(name)` and `etl._extract_sessions_from_row(row)`.

## ETL (Fast‑F1 ingestion)

Entry points in `backend/etl.py`:

`load_fastf1_session(db, year, gp, session_type, cache_dir='cache', store_telemetry=True, skip_if_exists=False)`
- Enables Fast‑F1 cache if `cache_dir` is set (default `backend/cache`).
- Upserts Event and Session, drivers, per‑event `driver_entries`, laps, and (optionally) telemetry.
- Telemetry per lap uses `laps.pick_drivers(code).pick_laps(lap_no).iloc[0].get_car_data().add_distance()`.
- Returns a summary dict: `{ event_id, session_id, drivers, laps, telemetry_rows, skipped? }`.

`load_event_weekend(db, year, gp, cache_dir='cache', store_telemetry=True, skip_if_exists=False)`
- Iterates available sessions for an event (via schedule probing) and loads each chronologically.

Utility: `list_event_sessions(year, gp)` returns ordered `(session_type, datetime)` pairs for a scheduled event.

## API Reference

All routes are defined in `backend/api.py`. Unless noted, no authentication is required.

### GET `/` — Health/Test
200 OK
```json
{ "message": "Hello, world 🐶🐱🐭" }
```

### GET `/telemetry/years` — List years with stored data
Response 200
```json
[
  { "year": 2024, "events": 22, "sessions": 44, "laps": 12345 }
]
```

### GET `/telemetry/events` — List events with stored telemetry
Query params
- `year` (optional int) — filter by season year

Response 200
```json
[
  {
    "id": 12,
    "year": 2025,
    "round": 1,
    "name": "Bahrain Grand Prix",
    "location": "Sakhir",
    "country": "Bahrain",
    "date": "2025-03-01",
    "session_types": ["FP1", "FP2", "Q", "R"]
  }
]
```

### GET `/telemetry/events/{event_id}/sessions` — Sessions for an event
Response 200
```json
[
  { "id": 101, "type": "Q", "date": "2025-03-01T18:00:00" },
  { "id": 102, "type": "R", "date": "2025-03-02T18:00:00" }
]
```
Errors
- 404 when no sessions found for event

### GET `/telemetry/sessions/{session_id}/drivers` — Drivers with laps in a session
Response 200
```json
[
  { "id": 45, "code": "VER", "number": 1, "first_name": "Max", "last_name": "Verstappen", "team_name": "Red Bull Racing", "team_color": "#3671C6" }
]
```
Errors
- 404 when no drivers found for session

### GET `/telemetry/sessions/{session_id}/drivers/{driver_id}/laps` — Laps for a driver in a session
Response 200
```json
[
  { "lap_number": 1, "lap_time_ms": 95732, "position": 2, "compound": "MEDIUM", "track_status": "1" },
  { "lap_number": 2, "lap_time_ms": 95501, "position": 1, "compound": "MEDIUM", "track_status": "1" }
]
```
Errors
- 404 when no laps found

### GET `/telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}` — Telemetry arrays for a lap
Response 200
```json
{
  "session_id": 102,
  "driver_id": 45,
  "lap_number": 10,
  "time_s": [0.0, 0.02, 0.04],
  "distance_m": [0.0, 1.2, 2.5],
  "speed_kmh": [120.0, 121.5, 122.1],
  "rpm": [11000, 11050, 11100],
  "gear": [3, 3, 4],
  "throttle": [0.6, 0.62, 0.65],
  "brake": [false, false, true],
  "drs": [0, 0, 12],
  "meta": { "lap_number": 10, "lap_time_ms": 94210, "position": 1, "compound": "SOFT", "track_status": "1" }
}
```
Errors
- 404 when lap not found

### GET `/schedule/{year}` — Season schedule via Fast‑F1 (no DB writes)
Query params
- `include_testing` (bool, default `false`)

Response 200 (fields are best‑effort — may be null if not present in Fast‑F1)
```json
[
  {
    "RoundNumber": 1,
    "Country": "Bahrain",
    "Location": "Sakhir",
    "EventName": "Bahrain Grand Prix",
    "EventDate": "2025-03-01T00:00:00Z",
    "Session1": "Practice 1",
    "Session1DateUtc": "2025-02-28T11:30:00Z",
    "Session2": "Practice 2",
    "Session2DateUtc": "2025-02-28T15:00:00Z",
    "Session3": "Qualifying",
    "Session3DateUtc": "2025-02-28T19:00:00Z",
    "Session4": "Race",
    "Session4DateUtc": "2025-03-01T18:00:00Z",
    "Session5": null,
    "Session5DateUtc": null
  }
]
```

## Admin API

If `ADMIN_TOKEN` is set, include header `X-Admin-Token: <token>`; otherwise these routes are open (dev convenience).

### GET `/admin/overview/{year}` — Events with scheduled sessions and current load status
Response 200
```json
[
  {
    "round": 1,
    "name": "Bahrain Grand Prix",
    "location": "Sakhir",
    "country": "Bahrain",
    "date": "2025-03-01T00:00:00Z",
    "event_id": 12,
    "sessions": [
      { "type": "FP1", "scheduled_utc": "2025-02-28T11:30:00Z", "session_id": 1001, "laps": 557, "drivers": 20 },
      { "type": "Q",   "scheduled_utc": "2025-02-28T19:00:00Z", "session_id": 1003, "laps": 0,   "drivers": 0 }
    ]
  }
]
```

### POST `/admin/load` — Load a single session via Fast‑F1
Body
```json
{ "year": 2025, "gp": 1, "session_type": "Q", "store_telemetry": true, "skip_if_exists": false }
```
Response 200
```json
{ "event_id": 12, "session_id": 1003, "drivers": 20, "laps": 325, "telemetry_rows": 152340 }
```
Errors
- 500 `Load failed: ...` (Fast‑F1 or DB errors)

### DELETE `/admin/sessions/{session_id}` — Delete a session and related data
Response 200
```json
{ "deleted_session_id": 1003 }
```
Errors
- 404 when session not found
- 401 when admin token invalid/missing and `ADMIN_TOKEN` is set

## Auth, CORS, Errors
- Admin auth is opt‑in via `ADMIN_TOKEN`. Without it, admin routes are open.
- CORS defaults to `*` and can be constrained with `CORS_ALLOW_ORIGINS`.
- Typical errors: 401 (admin auth), 404 (not found), 422 (validation from FastAPI), 500 (load failures).

## Notes & Gotchas
- Postgres driver: `psycopg[binary]` (already in `requirements.txt`). Ensure `DATABASE_URL` uses the `postgresql+psycopg://` scheme; `postgres://` is auto‑normalized.
- DRS values are stored raw; frontend should treat {10, 12, 14} as “ON”.
- Use `driver_entries` to query historical driver↔team per event (instead of `drivers.team_name`).
