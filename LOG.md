# Race Savant — Development Log

Date: 2025-09-23

This log summarizes what was implemented so far, how it maps to BUILD_PLAN.md, and what to do next.

## Completed
- Backend
  - DB models and migrations for `events`, `sessions`, `drivers`, `laps`, `telemetry` (idempotent light migrations).
  - ETL/CLI: load Fast‑F1 sessions and weekends into DB; duplicate-safe via unique keys and replace-per-lap telemetry. Flags: `--all`, `--nth`, `--list`, `--skip-existing`, `--no-telemetry`.
  - API (FastAPI):
    - Telemetry navigation/endpoints (read-only, raw channels):
      - `GET /telemetry/years`
      - `GET /telemetry/events?year=YYYY`
      - `GET /telemetry/events/{event_id}/sessions`
      - `GET /telemetry/sessions/{session_id}/drivers`
      - `GET /telemetry/sessions/{session_id}/drivers/{driver_id}/laps`
      - `GET /telemetry/sessions/{session_id}/drivers/{driver_id}/laps/{lap_number}`
    - Raw DRS returned; frontend determines ON/OFF (10/12/14) as per requirement.
    - Schedule passthrough (no DB writes): `GET /schedule/{year}` from Fast‑F1.
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
  - Add CORS config and minimal rate limiting.
  - Optional pagination or server-side downsampling for telemetry arrays.
  - Add health endpoint and simple status page (counts per table).
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
- Events are always disabled when offline/time-skewed because we don’t yet record event-level cache presence. Add an `event_has_cached_results` marker when saving session results.
- ATS: the app hits `http://127.0.0.1:8000` and `http://api.jolpi.ca`; ensure NSAppTransportSecurity exceptions are configured during development.
- Codable warnings on model `id` fields; harmless but noisy—can be silenced with custom Codable.

## How to Run (Current)
- Backend
  - Ensure `DATABASE_URL` is set.
  - Ingest sample data (e.g., `python backend/main.py 2024 1 --all --skip-existing`).
  - Start API: `uvicorn backend.api:app --reload`.
- iOS
  - Targets: run the SwiftUI app target.
  - Ensure ATS exceptions for local dev endpoints.

