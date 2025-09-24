# Race Savant — Build Plan

This document lays out the end-to-end plan for data ingestion, storage, APIs, and iOS UI for Home, Standings, and Telemetry features. It encodes all data rules, sources, and edge cases.

## 1) High-Level Architecture
- Frontend: SwiftUI app. Fetches third‑party APIs directly for Home schedule and Standings. Caches results locally.
- Backend: FastAPI service + Postgres. Stores laps and high‑frequency telemetry; exposes read APIs for Telemetry consumption by the app. Optional: session results caching later, but not required now.
- Ingestion: Python CLI to load a session’s laps + telemetry from Fast‑F1 into Postgres with duplicate detection.

## 2) Data Sources and Rules

### 2.1 Home Schedule (Fast‑F1 EventSchedule)
- Source: Fast‑F1 `eventschedules` object for the current season.
- Fields used per event: `RoundNumber`, `Country`, `Location`, `EventName`, `EventDate`, `Session1DateUtc` … `Session5DateUtc`.
- Each event card is clickable → Event Detail page.
- Event Detail lists 5 sessions; clicking a session goes to Session Result page.

### 2.2 Session Results (OpenF1)
- Step A: Resolve `session_key` by location or country name and session name.
  - Preferred query (keep spaces as-is; use URL params to encode):
    - Example: Practice 1, 2025 Chinese GP →
      `https://api.openf1.org/v1/sessions?location=Shanghai&session_name=Practice 1&year=2025`
  - Edge case fallback (non‑ASCII location names → use country_name):
    - Known: Montréal, São Paulo → use `country_name=Canada` or `country_name=Brazil`.
    - Example: Race, 2024 Brazilian GP →
      `https://api.openf1.org/v1/sessions?country_name=Brazil&session_name=Race&year=2024`
  - Extract `x[0].session_key` from JSON response.

- Step B: Fetch session results by `session_key`:
  - `https://api.openf1.org/v1/session_result?session_key=<KEY>` → array of drivers.

- Parsing rules per session type (loop over all drivers `x[]`):
  - Practice 1/2/3
    - `position`, `driver_number`, `dnf`, `dns`, `dsq`, `duration` (best lap time for the session).
  - Qualifying / Sprint Qualifying
    - `position`, `driver_number`, `dnf`, `dns`, `dsq`.
    - `duration` is an array (nullable entries):
      - `duration[0]` → Q1 best; `duration[1]` → Q2 best; `duration[2]` → Q3 best.
  - Race / Sprint
    - `position`, `driver_number`, `points`, `dnf`, `dns`, `dsq`.

### 2.3 Standings (Ergast via jolpi)
- Driver Standings: `http://api.jolpi.ca/ergast/f1/2025/driverstandings/`
  - Use: `x.MRData.StandingsTable.StandingsLists[0].DriverStandings[]`:
    - `position`, `points`, `wins`, `Driver.permanentNumber`.
- Constructor Standings: `http://api.jolpi.ca/ergast/f1/2025/constructorstandings/`
  - Use: `x.MRData.StandingsTable.StandingsLists[0].ConstructorStandings[]`:
    - `position`, `points`, `wins`, `Constructor.name`.

### 2.4 Telemetry (Fast‑F1 Laps + Car Data)
- For each driver:
  ```python
  driver_laps = all_laps.pick_driver(driver_code)
  telemetry_driver_laps = driver_laps.get_car_data()
  ```
- Laps columns to persist: `Driver (str)`, `DriverNumber (str)`, `LapTime (float64)`, `LapNumber (float64)`, `Stint (float64)`, `IsPersonalBest (bool)`, `Compound (str)`, `Team (str)`, `TrackStatus (str)`, `Position (float64)`.
- Telemetry columns to persist: `Speed (float64)`, `RPM (float64)`, `nGear (int)`, `Throttle (float64)`, `Brake (bool)`, `Time (timedelta64[ns])`.
- DRS visualization rule: only values {10, 12, 14} are “ON” (treat all others as OFF for charting).

## 3) Backend (FastAPI + Postgres)

### 3.1 Database Schema (initial)
- `sessions` (metadata for loaded sessions)
  - `id` (PK, bigint), `session_key` (int, unique), `year` (int), `event_name` (text), `round` (int), `location` (text), `country` (text), `session_name` (text), `created_at` (timestamptz)
- `laps`
  - `id` (PK), `session_key` (int FK), `driver_code` (text), `driver_number` (text), `lap_number` (int), `lap_time_s` (double precision), `stint` (int), `is_personal_best` (boolean), `compound` (text), `team` (text), `track_status` (text), `position` (int)
  - Unique index: `(session_key, driver_number, lap_number)`
- `telemetry`
  - `id` (PK), `session_key` (int FK), `driver_code` (text), `driver_number` (text), `lap_number` (int), `sample_ts_ms` (bigint), `speed` (double), `rpm` (double), `n_gear` (int), `throttle` (double), `brake` (boolean)
  - Unique index: `(session_key, driver_number, lap_number, sample_ts_ms)`
  - Note: `Time` from Fast‑F1 is a Timedelta per lap; store as milliseconds since lap start for easy plotting.

### 3.2 API Endpoints (read‑only for app)
- `GET /telemetry/sessions/{session_key}/drivers/{driver_number}/laps/{lap_number}`
  - Returns: lap metadata + arrays for `time_ms`, `speed`, `rpm`, `nGear`, `throttle`, `brake`, and derived `drs_on` (bool from raw channel if stored; if not, derive at render time if available).
- `GET /telemetry/sessions/{session_key}/drivers` → list available drivers for session.
- `GET /telemetry/sessions/{session_key}/drivers/{driver_number}/laps` → list available lap numbers.

### 3.3 Implementation Notes
- Use `asyncpg` or SQLAlchemy Core. Bulk insert with `ON CONFLICT DO NOTHING` for duplicates.
- Add DB constraints first; rely on upserts to enforce idempotence.
- Optional extension later: TimescaleDB for telemetry; not required initially.

## 4) Ingestion CLI (Python)
- Purpose: `load_session` pulls a session via Fast‑F1, extracts Laps + per‑driver Telemetry, and loads into DB, safely handling duplicates.
- Invocation examples:
  - `python -m tools.load_session --year 2025 --event "Shanghai" --session "Practice 1"`
  - `python -m tools.load_session --session-key 9998`
- Steps:
  1) Resolve `session_key` (via OpenF1 as in §2.2) if not provided. Apply location→country fallback for Montréal/São Paulo.
  2) `fastf1.Session(year, gp_name_or_round, session_name).load()`
  3) Extract `all_laps` and required columns; normalize types (convert `timedelta` to seconds, NaN→null).
  4) For each driver, compute telemetry samples per lap; convert `Time` to `sample_ts_ms`.
  5) Upsert into `sessions`, `laps`, `telemetry` with unique indexes preventing duplicates.
- Safety:
  - Wrap inserts in transactions per logical batch (e.g., per driver) with retry.
  - Log skipped rows on conflict for audit.

## 5) iOS App (SwiftUI)

### 5.1 Local Storage
- Use SwiftData (or Core Data) for on‑device caching of: session results, standings, and schedule snapshots. Keep a mapping struct for driver number → full name, team name, and team color for current year. Evict or refresh via TTL (e.g., 6h for schedule; race results cache forever).

### 5.2 Home Tab
- Segmented control: Past | Upcoming.
- Event card per schedule item:
  - Show: RoundNumber, Country, EventDate range as `MM-dd to MM-(dd+2)`.
- Event Detail page:
  - Header: RoundNumber, EventName, Location.
  - List of 5 sessions with local time (convert `Session{n}DateUtc` to device timezone).
  - Interactivity:
    - Upcoming: greyed out, disabled.
    - Past: tappable → Session Result page.

### 5.3 Session Result Pages
- Practice (P1/2/3): list rows → `position`, Driver Full Name (from mapping), best lap time (`duration`).
- Qualifying / Sprint Qualifying: list rows → `position`, Driver Full Name, times:
  - `Q1: duration[0]` if non‑null, `Q2: duration[1]` if non‑null, `Q3: duration[2]` if non‑null.
- Race / Sprint: list rows → `position`, Driver Full Name, `points`, status badge if any of `dnf`/`dns`/`dsq` is true.

### 5.4 Standings Tab
- Segmented control: Drivers | Constructors.
- Drivers: list → `position`, Driver Full Name, Team, wins (trophy + count) only if wins > 0.
- Constructors: list → `position`, Constructor name, points, wins only if > 0.

### 5.5 Telemetry Tab
- UX: pickers for Year → Event → Session → Driver → Lap.
- Charts:
  - Speed vs Time
  - Throttle vs Time
  - Brake vs Time
  - DRS vs Time (boolean series; treat raw values {10,12,14} as ON).
- Data source: backend telemetry endpoints (§3.2).

## 6) Data Handling Details & Edge Cases
- OpenF1 query params: always use `params={...}` to preserve spaces in `session_name`.
- Montréal/São Paulo: if `Location` contains non‑ASCII or matches known set, query by `country_name` (Canada/Brazil) instead of `location`.
- Time zones: show session times as user’s device local time; store as UTC in code and convert at display.
- Null qualifying stints: omit Q1/Q2/Q3 labels for missing times.
- Driver mapping: ship a current‑year mapping for driver number → full name, team name, team color.

## 7) Testing & Validation
- Unit tests (backend):
  - Session key resolver: location vs country fallback.
  - Upsert idempotence: duplicate ingestion yields no extra rows.
  - Telemetry sample conversion: timedelta → ms monotonic.
- iOS snapshot tests (optional) for list cells; formatters for dates and lap times.

## 8) Milestones
- M1: Backend skeleton + DB migrations + basic endpoints.
- M2: Ingestion CLI end‑to‑end for one session; dedupe proven.
- M3: iOS Home + Event Detail + Session Results from OpenF1; local caching.
- M4: Standings screens from Ergast; local caching.
- M5: Telemetry tab consuming backend, 4 charts.
- M6: Polish: errors, loading states, empty states, offline behavior.

## 9) Out‑of‑Scope (for now)
- Historical seasons beyond current mapping, multi‑year driver roster.
- Authentication, user accounts, sync.
- Advanced DB optimizations (e.g., compression, TimescaleDB).

## 10) Open Questions
- Should we also cache session results server‑side for durability? (Client caches only by default.)
- Preferred charting library on iOS (Swift Charts vs custom)?

