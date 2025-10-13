# Race Savant

Lightweight iOS app that visualizes Formula 1 telemetry (live & historical).  
Frontend: SwiftUI | Backend: FastAPI.  
Data sources: Fast‑F1, jolpica‑F1 API, Open‑F1 API.

Screenshots

<table>
  <tr>
    <td><img src="docs/01-home.PNG" alt="Home" width="250"></td>
    <td><img src="docs/02-session-overview.PNG" alt="Session Overview" width="250"></td>
    <td><img src="docs/03-session-detail.PNG" alt="Session Detail" width="250"></td>
  </tr>
  <tr>
    <td><img src="docs/04-driver-standings.PNG" alt="Driver Standings" width="250"></td>
    <td><img src="docs/05-constructor-standings.PNG" alt="Constructor Standings" width="250"></td>
    <td><img src="docs/06-telemetry-selections.PNG" alt="Telemetry Selections" width="250"></td>
  </tr>
  <tr>
    <td><img src="docs/07-telemtry-graphs.PNG" alt="Telemetry Graphs" width="250"></td>
    <td></td>
    <td></td>
  </tr>
  
</table>

Quick features
- Session list (Practice/Quali/Race)
- Telemetry graphs: speed, RPM, throttle, brake, gear
- Lap comparison and deltas
- Configurable data sources (Fast‑F1, jolpica, Open‑F1)

Tech stack
- iOS: SwiftUI (Swift)
- Backend: FastAPI (Python)
- Data libs/APIs: Fast‑F1, jolpica‑F1 API, Open‑F1 API
