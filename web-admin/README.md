# Race Savant Admin Dashboard

A vanilla HTML/CSS/JavaScript admin dashboard for managing F1 session data.

## Setup

1. **Update Configuration**
   Edit the `CONFIG` object in `script.js`:
   ```javascript
   const CONFIG = {
       API_BASE_URL: 'http://localhost:8000',
       ADMIN_USERNAME: 'admin',
       ADMIN_PASSWORD: 'password123',
       ADMIN_TOKEN: 'your-actual-admin-token-here'
   };
   ```

2. **Start Backend**
   Make sure your FastAPI backend is running:
   ```bash
   cd ../backend
   uvicorn api:app --reload
   ```

3. **Open Dashboard**
   Open `index.html` in your browser or serve with a local server:
   ```bash
   python -m http.server 3000
   # or
   npx serve .
   ```

## Features

- **Authentication**: Simple login with configurable credentials
- **Real API Integration**: Connects to FastAPI backend
- **Session Management**: Load and delete F1 sessions
- **Year Selection**: Switch between F1 seasons
- **Responsive Design**: Works on desktop and mobile
- **Toast Notifications**: Success/error feedback
- **Error Handling**: Network and API error management

## Login

- Username: `admin`
- Password: `password123`

## API Endpoints Used

- `GET /admin/overview/{year}` - Get events and session status
- `POST /admin/load` - Load session data
- `DELETE /admin/sessions/{session_id}` - Delete session

## File Structure

```
web-admin/
├── index.html          # Main HTML structure
├── styles.css          # All CSS styles
├── script.js           # JavaScript functionality
└── README.md           # This file
```