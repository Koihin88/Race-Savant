# Race Savant — Development Log

Date: 2025-09-23

This log summarizes what was implemented so far, how it maps to BUILD_PLAN.md, and what to do next.

## Completed
- Backend
  - Data model and migrations (SQLAlchemy)
    - `events`: season metadata (year, round, location, country, name, date). Unique(year, name).
    - `sessions`: per‑event sessions with type code (FP1/FP2/FP3/Q/S/SQ/SS/R) and date. Unique(event_id, type).
    - `drivers`: canonical driver record (code, number, names, team_name/color fields reflect latest known during ingestion).
    - `laps`: per‑lap facts (session FK, driver FK, lap_number, lap_time_ms, compound, position, tyre_life, track_status). Unique(session_id, driver_id, lap_number).
    - `telemetry`: high‑frequency samples per lap (time_s, distance_m, speed_kmh, rpm, gear, throttle, brake, drs). FK to `laps`.
    - NEW `driver_entries`: per‑event driver team snapshot (event_id, driver_id, team_name, team_color). Unique(event_id, driver_id). Enables historical queries when drivers change teams mid‑season.
    - Lightweight, idempotent migrations ensure missing columns/tables are added without a full framework.
  - ETL/CLI (Fast‑F1)
    - `load_fastf1_session`: loads a session end‑to‑end, upserts event/session/driver, inserts/upserts laps, and replaces telemetry for each lap.
    - pick_lap deprecated: now uses `laps_df.pick_drivers(code).pick_laps(lap_number).iloc[0]` strictly.
    - Writes `driver_entries` for each observed driver with team at that event.
    - CLI options in `backend/main.py`: `--all`, `--nth`, `--list`, `--skip-existing`, `--no-telemetry`.
  - API (FastAPI)
    - Telemetry (read‑only, raw channels):
      - `GET /telemetry/years` → summarize years with stored data.
      - `GET /telemetry/events?year=YYYY` → events that have laps stored, with available session types.
      - `GET /telemetry/events/{event_id}/sessions` → sessions with data for that event.
      - `GET /telemetry/sessions/{session_id}/drivers` → drivers with laps in session.
      - `GET /telemetry/sessions/{session_id}/drivers/{driver_id}/laps` → lap list for that driver.
      - `GET /telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}` → arrays for time_s, speed_kmh, rpm, gear, throttle, brake, drs, plus lap meta.
      - DRS is raw; frontend applies ON rule (10/12/14).
    - Schedule passthrough (no DB writes): `GET /schedule/{year}` using Fast‑F1 schedule.
    - Admin endpoints for future web dashboard:
      - `GET /admin/overview/{year}` → per event, show scheduled sessions and load status (session_id, laps, distinct drivers).
      - `POST /admin/load` → trigger `load_fastf1_session` (year, gp, session_type, store_telemetry, skip_if_exists).
      - `DELETE /admin/sessions/{session_id}` → delete session row (cascades delete laps/telemetry).
    - CORS middleware (origins via `CORS_ALLOW_ORIGINS` env). Optional admin header auth via `ADMIN_TOKEN` env (`X-Admin-Token`).
- iOS (SwiftUI)
  - App Shell: Tabs for Home, Standings, Telemetry.
  - Local storage (JSON): schedule, standings, session results.
  - Home
    - Hardcoded 2025 schedule from `2025schedule.csv` (rounds 1–24; testing excluded).
    - Event list segmented into Past/Upcoming; event card shows flag, round, country, date range (MM-dd to MM-(dd+2)).
    - Event detail shows 5 sessions with time localized from UTC; upcoming sessions disabled.
    - Interactivity tied to session times vs current time; when offline or device time seems off, events are conservatively disabled (see “Known Gaps”).
  - Session Results
    - Resolves session_key via OpenF1; handles Montréal/São Paulo by country fallback (Canada/Brazil).
    - Fetches results by `session_key`, caches raw JSON locally.
    - Renders per session type:
      - Practice: position, driver name, best lap.
      - Qualifying/Sprint Qualifying: position, driver name, Q1/Q2/Q3 where present.
      - Race/Sprint: position, driver name, points, and status badges (DNF/DNS/DSQ).
    - Driver mapping hardcoded from `drivers_modify.csv` (number→name/team/color) for 2025.
  - Standings
    - Drivers/Constructors fetched from Ergast (jolpi) for 2025; cached locally.
    - Displays per spec; shows trophy+count only if wins > 0.
  - Telemetry
    - Progressive pickers Year→Event→Session→Driver→Lap using backend endpoints so only valid choices appear.
    - Charts: Speed, Throttle, Brake, DRS (frontend applies ON rule 10/12/14).
    - Error handling for network calls; simple in-view messages.
  - Utilities
    - NetworkMonitor to detect offline state.
    - Country flag mapping.

## Partially Complete
- Home interactivity offline behavior
  - When offline or with suspicious device clock, events are disabled by default because we don’t yet track an “event has cached results” marker.
- Telemetry charts
  - Basic charts implemented; no styling toggles/legends or downsampling for very long laps yet.
- Codable warnings
  - Model `id` fields have default values; decoding can warn. We currently accept warnings. Can add custom Codable to silence.

## Deviations from BUILD_PLAN.md
- Schedule source on iOS: Hardcoded 2025 (requested), not pulled live from Fast‑F1 for Home. Backend still exposes `/schedule/{year}` as fallback for other years.
- Server does not cache or serve results/standings; per plan, the device fetches and caches these from OpenF1/Ergast.
- DRS ON/OFF strictly handled on frontend; backend sends raw int channel.

## Next Steps (Proposed)
- Home/Offline polish
  - Add a small cache marker per event when any session result is stored; enable event interactivity offline based on that marker.
  - Optional: show an “Offline” badge in Home when NetworkMonitor reports offline.
- iOS polish
  - Show team color swatch in Standings and Results (use `DriverMapEntry.colorHex`).
  - Add Settings: backend base URL, clear cache, and a toggle to show UTC times.
  - Improve date formatting with locale-aware formats and accessibility labels.
  - Add loading/empty/skeleton states.
- Telemetry UX/Perf
  - Add driver/session filters and downsampling for long telemetry sequences.
  - Optional: export lap telemetry as CSV for debugging.
- Backend
  - Add server-side downsampling or pagination for telemetry arrays to reduce payload size.
  - Add health endpoint (`/health`) and stats (`/admin/stats`) for quick DB checks.
  - Extend admin API:
    - DELETE by (year, gp, session_type) convenience (resolve to session_id internally).
    - DELETE /admin/events/{event_id} to remove all sessions for an event.
    - GET /admin/sessions/{session_id} for details (counts, drivers).
  - Expose per‑event team info:
    - Add `GET /events/{event_id}/drivers` that joins `driver_entries` to surface historical team names/colors.
- Tooling/QA
  - Unit tests:
    - iOS: APIService parsing (OpenF1 session_key response variants; Ergast paths), date formatting helpers, roster mapping.
    - Backend: schedule serializer, telemetry endpoints (happy path + empty).
  - Snapshot tests for Home/Standings cells.

## Open Questions
- Do we need server-side caching for session results to improve offline experience and reduce third‑party fetches?
- Should Home show precise “Session live/ended” based on last session time vs now?
- Any additional non‑ASCII locations (beyond Montréal, São Paulo) to handle via `country_name` fallback for session_key resolution?

## Known Gaps / Follow-ups
- iOS: Add an `event_has_cached_results` marker when saving session results to improve offline UX in Home.
- ATS: the app hits `http://127.0.0.1:8000` and `http://api.jolpi.ca`; ensure NSAppTransportSecurity exceptions are configured during development.
- Codable warnings on model `id` fields; harmless but noisy—can be silenced with custom Codable.

## Backend Data Model — Practical Notes
- Historical teams: query `driver_entries` for the driver’s team at a given event (e.g., Tsunoda at Round 1 vs later rounds).
- Joins cheatsheet:
  - list events with any data: `events JOIN sessions JOIN laps` (distinct event_id)
  - per-event drivers with teams: `driver_entries JOIN drivers` filtered by event_id
  - telemetry for a lap: `telemetry WHERE lap_id IN (SELECT id FROM laps WHERE session_id = ... AND driver_id = ... AND lap_number = ...) ORDER BY time_s`

## Backend API — Quick Reference
- Telemetry
  - `/telemetry/years`
  - `/telemetry/events?year=YYYY`
  - `/telemetry/events/{event_id}/sessions`
  - `/telemetry/sessions/{session_id}/drivers`
  - `/telemetry/sessions/{session_id}/drivers/{driver_id}/laps`
  - `/telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}`
- Schedule
  - `/schedule/{year}`
- Admin (optional `X-Admin-Token`)
  - `/admin/overview/{year}`
  - `/admin/load` (POST JSON: `{year,gp,session_type,store_telemetry,skip_if_exists}`)
  - `/admin/sessions/{session_id}` (DELETE)

## How to Run (Current)
- Backend
  - Ensure `DATABASE_URL` is set.
  - Ingest sample data (e.g., `python backend/main.py 2024 1 --all --skip-existing`).
  - Start API: `uvicorn backend.api:app --reload`.
- iOS
  - Targets: run the SwiftUI app target.
  - Ensure ATS exceptions for local dev endpoints.
