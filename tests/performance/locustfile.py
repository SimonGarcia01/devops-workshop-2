"""
CircleGuard — Locust performance & stress tests.

Simulates two user types:
  - AuthenticatedUser: represents a student/employee doing their daily check-in
  - AdminUser:         represents an admin querying analytics dashboards

Run (interactive UI):
    locust -f locustfile.py

Run (headless CI mode, 50 users, 2 minutes):
    locust -f locustfile.py --headless -u 50 -r 5 -t 2m \
        --host http://localhost --html report.html

NodePorts (dev environment):
    auth-service:      30081
    gateway-service:   30087
    form-service:      30086
    dashboard-service: 30084
    promotion-service: 30088 (ClusterIP — internal only)
"""

from locust import HttpUser, task, between, events
import json
import random
import uuid


# ─────────────────────────────────────────────────────────────
# Authenticated student/employee flow
# ─────────────────────────────────────────────────────────────
class AuthenticatedUser(HttpUser):
    """
    Simulates the daily workflow of a campus user:
      1. Login
      2. Submit health survey
      3. Validate QR at gate
    """
    wait_time = between(1, 3)
    host = "http://localhost"
    token = ""
    anonymous_id = ""

    def on_start(self):
        """Authenticate once at the start of the user session."""
        with self.client.post(
            ":30081/api/v1/auth/login",
            json={"username": f"user{random.randint(1, 200)}", "password": "testpass"},
            catch_response=True,
            name="[auth] POST /login"
        ) as resp:
            if resp.status_code == 200:
                body = resp.json()
                self.token = body.get("token", "")
                self.anonymous_id = body.get("anonymousId", str(uuid.uuid4()))
                resp.success()
            else:
                self.token = ""
                resp.failure(f"Login failed with status {resp.status_code}")

    @property
    def _auth_headers(self):
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }

    @task(5)
    def validate_gate(self):
        """Most frequent action: scan QR at building entrance."""
        self.client.post(
            ":30087/api/v1/gate/validate",
            json={"token": self.token},
            headers=self._auth_headers,
            name="[gateway] POST /gate/validate"
        )

    @task(3)
    def get_active_questionnaire(self):
        """Fetch the daily health questionnaire."""
        self.client.get(
            ":30086/api/v1/questionnaires/active",
            headers=self._auth_headers,
            name="[form] GET /questionnaires/active"
        )

    @task(2)
    def submit_health_survey(self):
        """Submit daily health check (no symptoms scenario)."""
        self.client.post(
            ":30086/api/v1/surveys",
            json={
                "anonymousId": self.anonymous_id,
                "hasFever": False,
                "hasCough": False,
                "answers": []
            },
            headers=self._auth_headers,
            name="[form] POST /surveys"
        )

    @task(1)
    def health_check_auth(self):
        """Monitor auth service liveness."""
        self.client.get(
            ":30081/actuator/health",
            name="[auth] GET /actuator/health"
        )

    @task(1)
    def health_check_gateway(self):
        """Monitor gateway service liveness."""
        self.client.get(
            ":30087/actuator/health",
            name="[gateway] GET /actuator/health"
        )


# ─────────────────────────────────────────────────────────────
# Admin / analytics dashboard flow
# ─────────────────────────────────────────────────────────────
class AdminUser(HttpUser):
    """
    Simulates an admin checking dashboards and managing the system.
    Lower frequency than regular users.
    """
    wait_time = between(3, 8)
    host = "http://localhost"
    token = ""

    DEPARTMENTS = ["Engineering", "Medicine", "Business", "Sciences", "Arts"]

    def on_start(self):
        with self.client.post(
            ":30081/api/v1/auth/login",
            json={"username": "admin", "password": "admin"},
            catch_response=True,
            name="[auth] POST /login (admin)"
        ) as resp:
            if resp.status_code == 200:
                self.token = resp.json().get("token", "")
                resp.success()
            else:
                self.token = ""
                resp.failure(f"Admin login failed: {resp.status_code}")

    @property
    def _auth_headers(self):
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }

    @task(4)
    def view_health_board(self):
        """Check global health status dashboard."""
        self.client.get(
            ":30084/api/v1/analytics/health-board",
            headers=self._auth_headers,
            name="[dashboard] GET /analytics/health-board"
        )

    @task(3)
    def view_department_stats(self):
        """Check department-level statistics."""
        dept = random.choice(self.DEPARTMENTS)
        self.client.get(
            f":30084/api/v1/analytics/department/{dept}",
            headers=self._auth_headers,
            name="[dashboard] GET /analytics/department/:dept"
        )

    @task(2)
    def view_time_series(self):
        """View hourly entry trend data."""
        self.client.get(
            ":30084/api/v1/analytics/time-series?period=hourly&limit=24",
            headers=self._auth_headers,
            name="[dashboard] GET /analytics/time-series"
        )

    @task(1)
    def list_pending_surveys(self):
        """Admin reviews surveys pending certificate validation."""
        self.client.get(
            ":30086/api/v1/surveys/pending",
            headers=self._auth_headers,
            name="[form] GET /surveys/pending"
        )


# ─────────────────────────────────────────────────────────────
# Stress scenario: simultaneous logins (spike test)
# ─────────────────────────────────────────────────────────────
class SpikeUser(HttpUser):
    """
    Simulates a login spike (e.g., all students arrive at 8 AM).
    Pure login load, no wait time.
    """
    wait_time = between(0, 1)
    host = "http://localhost"

    @task
    def rapid_login_attempt(self):
        self.client.post(
            ":30081/api/v1/auth/login",
            json={
                "username": f"student{random.randint(1, 500)}",
                "password": "testpass"
            },
            name="[auth] POST /login (spike)"
        )


# ─────────────────────────────────────────────────────────────
# Custom event hooks for reporting
# ─────────────────────────────────────────────────────────────
@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    stats = environment.stats
    total = stats.total
    print("\n========== CircleGuard Load Test Summary ==========")
    print(f"  Total requests:  {total.num_requests}")
    print(f"  Failures:        {total.num_failures}")
    print(f"  Avg response:    {total.avg_response_time:.1f} ms")
    print(f"  95th percentile: {total.get_response_time_percentile(0.95):.1f} ms")
    print(f"  RPS:             {total.current_rps:.1f}")
    print("====================================================\n")
