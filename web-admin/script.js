// Configuration
const CONFIG = {
    API_BASE_URL: 'http://localhost:8000',
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'password123',
    ADMIN_TOKEN: 'race-savant-admin-2024'
};

// State Management
class AppState {
    constructor() {
        this.isLoggedIn = false;
        this.currentUser = null;
        this.currentYear = 2025;
        this.overview = null;
        this.loading = false;
        this.error = null;
    }

    login(username) {
        this.isLoggedIn = true;
        this.currentUser = username;
        localStorage.setItem('admin_token', CONFIG.ADMIN_TOKEN);
        localStorage.setItem('admin_user', username);
    }

    logout() {
        this.isLoggedIn = false;
        this.currentUser = null;
        this.overview = null;
        localStorage.removeItem('admin_token');
        localStorage.removeItem('admin_user');
    }

    setOverview(data) {
        this.overview = data;
        this.error = null;
    }

    setError(error) {
        this.error = error;
        this.loading = false;
    }

    setLoading(loading) {
        this.loading = loading;
        if (loading) {
            this.error = null;
        }
    }

    checkAuth() {
        const token = localStorage.getItem('admin_token');
        const user = localStorage.getItem('admin_user');
        if (token && user) {
            this.isLoggedIn = true;
            this.currentUser = user;
            return true;
        }
        return false;
    }
}

// API Client
class ApiClient {
    constructor() {
        this.baseURL = CONFIG.API_BASE_URL;
    }

    getHeaders() {
        const headers = {
            'Content-Type': 'application/json'
        };

        const token = localStorage.getItem('admin_token');
        if (token) {
            headers['X-Admin-Token'] = token;
        }

        return headers;
    }

    async request(endpoint, options = {}) {
        const url = `${this.baseURL}${endpoint}`;

        const config = {
            headers: this.getHeaders(),
            ...options
        };

        try {
            const response = await fetch(url, config);

            if (!response.ok) {
                if (response.status === 401) {
                    // Unauthorized - logout user
                    app.logout();
                    return;
                }

                let errorMessage;
                try {
                    const errorData = await response.json();
                    errorMessage = errorData.detail || errorData.message || `HTTP ${response.status}`;
                } catch {
                    errorMessage = `HTTP ${response.status}`;
                }

                throw new Error(errorMessage);
            }

            return await response.json();
        } catch (error) {
            if (error.message.includes('fetch') || error.message.includes('NetworkError')) {
                throw new Error('Network error - check if backend is running');
            }
            throw error;
        }
    }

    async getOverview(year) {
        return this.request(`/admin/overview/${year}`);
    }

    async loadSession(sessionId) {
        return this.request('/admin/load', {
            method: 'POST',
            body: JSON.stringify({
                year: sessionId.year,
                gp: sessionId.gp,
                session_type: sessionId.session_type,
                store_telemetry: true,
                skip_if_exists: false
            })
        });
    }

    async deleteSession(sessionId) {
        return this.request(`/admin/sessions/${sessionId}`, {
            method: 'DELETE'
        });
    }
}

// Toast Notifications
class Toast {
    static show(message, type = 'success') {
        const toast = document.getElementById('toast');
        const toastMessage = document.getElementById('toastMessage');

        toast.className = `toast ${type}`;
        toast.style.display = 'flex';
        toastMessage.textContent = message;

        // Auto-hide after 5 seconds
        setTimeout(() => {
            Toast.hide();
        }, 5000);
    }

    static hide() {
        const toast = document.getElementById('toast');
        toast.style.display = 'none';
    }

    static success(message) {
        Toast.show(message, 'success');
    }

    static error(message) {
        Toast.show(message, 'error');
    }

    static warning(message) {
        Toast.show(message, 'warning');
    }
}

// UI Manager
class UIManager {
    constructor() {
        this.loginScreen = document.getElementById('loginScreen');
        this.dashboardScreen = document.getElementById('dashboardScreen');
    }

    showLogin() {
        this.loginScreen.style.display = 'block';
        this.dashboardScreen.style.display = 'none';
    }

    showDashboard() {
        this.loginScreen.style.display = 'none';
        this.dashboardScreen.style.display = 'block';
    }

    showLoading() {
        document.getElementById('loadingState').style.display = 'block';
        document.getElementById('errorState').style.display = 'none';
        document.getElementById('dashboardContent').style.display = 'none';
    }

    showError(message) {
        document.getElementById('loadingState').style.display = 'none';
        document.getElementById('errorState').style.display = 'block';
        document.getElementById('dashboardContent').style.display = 'none';
        document.getElementById('errorMessage').textContent = message;
    }

    showContent() {
        document.getElementById('loadingState').style.display = 'none';
        document.getElementById('errorState').style.display = 'none';
        document.getElementById('dashboardContent').style.display = 'block';
    }

    updateSummary(overview) {
        document.getElementById('totalEvents').textContent = overview.events.length;
        document.getElementById('totalSessions').textContent = overview.totalSessions || 0;
        document.getElementById('loadedSessions').textContent = overview.loadedSessions || 0;
    }

    renderEvents(events) {
        const eventsGrid = document.getElementById('eventsGrid');
        const noEventsMessage = document.getElementById('noEventsMessage');

        if (!events || events.length === 0) {
            eventsGrid.innerHTML = '';
            noEventsMessage.style.display = 'block';
            return;
        }

        noEventsMessage.style.display = 'none';

        eventsGrid.innerHTML = events.map(event => this.renderEventCard(event)).join('');

        // Add event listeners for session buttons
        this.attachSessionListeners();
    }

    renderEventCard(event) {
        const loadedCount = event.sessions.filter(s => s.isLoaded).length;
        const eventDate = new Date(event.date).toLocaleDateString();

        return `
            <div class="event-card">
                <div class="event-header">
                    <h3 class="event-title">Round ${event.round}: ${event.name}</h3>
                    <p class="event-meta">${event.location} • ${eventDate}</p>
                    <p class="event-stats">Sessions: ${loadedCount}/${event.sessions.length} loaded</p>
                </div>

                <div class="sessions-container">
                    ${event.sessions.map(session => this.renderSessionCard(session)).join('')}
                </div>
            </div>
        `;
    }

    renderSessionCard(session) {
        const statusClass = session.isLoaded ? 'loaded' : 'not-loaded';
        const statusText = session.isLoaded ? '✓ Loaded' : '✗ Not Loaded';
        const statusColor = session.isLoaded ? 'loaded' : 'not-loaded';

        let details = '';
        if (session.isLoaded && session.lapCount) {
            details = `<span class="session-details">(${session.lapCount} laps, ${session.driverCount} drivers)</span>`;
        }

        const actionButton = session.isLoaded
            ? `<button class="btn btn-danger btn-small session-delete" data-session-id="${session.id}">Delete</button>`
            : `<button class="btn btn-primary btn-small session-load"
                  data-year="${session.year}"
                  data-gp="${session.gp}"
                  data-session-type="${session.type}">Load</button>`;

        return `
            <div class="session-card ${statusClass}">
                <div class="session-info">
                    <span class="session-type">${session.type}</span>
                    <span class="session-status ${statusColor}">${statusText}</span>
                    ${details}
                </div>
                <div class="session-actions">
                    ${actionButton}
                </div>
            </div>
        `;
    }

    attachSessionListeners() {
        // Load session buttons
        document.querySelectorAll('.session-load').forEach(btn => {
            btn.addEventListener('click', async (e) => {
                const year = parseInt(e.target.getAttribute('data-year'));
                const gp = parseInt(e.target.getAttribute('data-gp'));
                const session_type = e.target.getAttribute('data-session-type');

                const sessionData = { year, gp, session_type };
                await app.loadSession(sessionData);
            });
        });

        // Delete session buttons
        document.querySelectorAll('.session-delete').forEach(btn => {
            btn.addEventListener('click', async (e) => {
                const sessionId = e.target.getAttribute('data-session-id');

                // Only allow delete if session ID exists (is loaded)
                if (sessionId && sessionId !== 'null') {
                    if (confirm('Are you sure you want to delete this session?')) {
                        await app.deleteSession(sessionId);
                    }
                } else {
                    Toast.error('Cannot delete session - not loaded in database');
                }
            });
        });
    }

    setButtonLoading(button, loading) {
        if (loading) {
            button.disabled = true;
            button.innerHTML = '<span class="spinner"></span> Loading...';
        } else {
            button.disabled = false;
            // This will be restored when the UI re-renders
        }
    }
}

// Main Application
class RaceSavantAdmin {
    constructor() {
        this.state = new AppState();
        this.api = new ApiClient();
        this.ui = new UIManager();

        this.init();
    }

    init() {
        this.setupEventListeners();

        // Check if user is already logged in
        if (this.state.checkAuth()) {
            this.ui.showDashboard();
            this.fetchOverview();
        } else {
            this.ui.showLogin();
        }
    }

    setupEventListeners() {
        // Login form
        document.getElementById('loginForm').addEventListener('submit', (e) => {
            e.preventDefault();
            this.handleLogin();
        });

        // Year selector
        document.getElementById('yearSelect').addEventListener('change', (e) => {
            this.state.currentYear = parseInt(e.target.value);
            this.fetchOverview();
        });

        // Refresh button
        document.getElementById('refreshBtn').addEventListener('click', () => {
            this.fetchOverview();
        });

        // Logout button
        document.getElementById('logoutBtn').addEventListener('click', () => {
            this.logout();
        });

        // Retry button
        document.getElementById('retryBtn').addEventListener('click', () => {
            this.fetchOverview();
        });

        // Toast close button
        document.getElementById('toastClose').addEventListener('click', () => {
            Toast.hide();
        });
    }

    async handleLogin() {
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const loginError = document.getElementById('loginError');
        const loginBtn = document.getElementById('loginBtn');

        loginError.style.display = 'none';

        if (username === CONFIG.ADMIN_USERNAME && password === CONFIG.ADMIN_PASSWORD) {
            loginBtn.disabled = true;
            loginBtn.textContent = 'Signing in...';

            this.state.login(username);
            this.ui.showDashboard();

            // Set year selector to current year
            document.getElementById('yearSelect').value = this.state.currentYear;

            await this.fetchOverview();

            loginBtn.disabled = false;
            loginBtn.textContent = 'Sign In';
        } else {
            loginError.textContent = 'Invalid username or password';
            loginError.style.display = 'block';
        }
    }

    logout() {
        this.state.logout();
        this.ui.showLogin();

        // Reset form
        document.getElementById('loginForm').reset();
        document.getElementById('loginError').style.display = 'none';

        Toast.success('Logged out successfully');
    }

    async fetchOverview() {
        this.state.setLoading(true);
        this.ui.showLoading();

        try {
            const events = await this.api.getOverview(this.state.currentYear);

            // Transform backend format to frontend format
            const overview = {
                events: events.map(event => ({
                    round: event.round,
                    name: event.name,
                    location: event.location,
                    date: event.date,
                    sessions: event.sessions.map(session => ({
                        id: session.session_id, // Use real session ID from DB (null if not loaded)
                        name: session.type,
                        type: session.type,
                        date: session.scheduled_utc || event.date,
                        isLoaded: session.laps > 0,
                        lapCount: session.laps,
                        driverCount: session.drivers,
                        lastUpdated: null,
                        // Store additional data needed for API calls
                        year: this.state.currentYear,
                        gp: event.round,
                        eventId: event.event_id
                    }))
                })),
                year: this.state.currentYear,
                totalSessions: 0,
                loadedSessions: 0
            };

            // Calculate totals
            overview.totalSessions = overview.events.reduce((total, event) => total + event.sessions.length, 0);
            overview.loadedSessions = overview.events.reduce((total, event) =>
                total + event.sessions.filter(session => session.isLoaded).length, 0
            );

            this.state.setOverview(overview);
            this.ui.showContent();
            this.ui.updateSummary(overview);
            this.ui.renderEvents(overview.events);
        } catch (error) {
            this.state.setError(error.message);
            this.ui.showError(error.message);
            Toast.error(`Failed to fetch data: ${error.message}`);
        }

        this.state.setLoading(false);
    }

    async loadSession(sessionData) {
        try {
            Toast.show('Loading session...', 'warning');

            const result = await this.api.loadSession(sessionData);

            if (result.success) {
                Toast.success(`Session loaded: ${result.lap_count} laps, ${result.driver_count} drivers`);
            } else {
                Toast.error(result.message || 'Failed to load session');
            }

            // Refresh the overview to get updated status
            await this.fetchOverview();
        } catch (error) {
            Toast.error(`Failed to load session: ${error.message}`);
        }
    }

    async deleteSession(sessionId) {
        try {
            Toast.show('Deleting session...', 'warning');

            await this.api.deleteSession(sessionId);
            Toast.success('Session deleted successfully');

            // Refresh the overview to get updated status
            await this.fetchOverview();
        } catch (error) {
            Toast.error(`Failed to delete session: ${error.message}`);
        }
    }
}

// Initialize the application
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new RaceSavantAdmin();
});