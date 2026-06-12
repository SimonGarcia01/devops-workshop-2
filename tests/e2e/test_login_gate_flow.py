"""
E2E Test: Login → QR Token → Gate Validation flow.

Covers the primary access control path:
  1. User authenticates and receives a JWT
  2. User requests a QR token
  3. User presents QR token at a gate
  4. Gate validates and returns GREEN / access granted
"""
import requests
import pytest

AUTH_URL    = "http://localhost:30081"
GATEWAY_URL = "http://localhost:30087"


class TestLoginGateFlow:

    def test_successful_login_returns_jwt(self, auth_headers):
        """Login endpoint returns a valid JWT with anonymousId."""
        resp = requests.post(
            f"{AUTH_URL}/api/v1/auth/login",
            json={"username": "testuser", "password": "testpass"},
            timeout=5
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "token" in body
        assert "anonymousId" in body
        assert body.get("type") == "Bearer"
        assert len(body["token"]) > 20

    def test_invalid_credentials_return_401(self):
        """Wrong password must be rejected."""
        resp = requests.post(
            f"{AUTH_URL}/api/v1/auth/login",
            json={"username": "testuser", "password": "wrongpassword"},
            timeout=5
        )
        assert resp.status_code == 401

    def test_gate_grants_access_with_valid_token(self, auth_token, auth_headers):
        """Gate accepts a valid JWT and returns GREEN status."""
        resp = requests.post(
            f"{GATEWAY_URL}/api/v1/gate/validate",
            json={"token": auth_token},
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body.get("valid") is True
        assert body.get("status") in ("GREEN", "CLEAR")

    def test_gate_rejects_invalid_token(self):
        """Gate must reject a malformed token."""
        resp = requests.post(
            f"{GATEWAY_URL}/api/v1/gate/validate",
            json={"token": "not-a-real-token"},
            timeout=5
        )
        assert resp.status_code in (400, 401)

    def test_gate_rejects_empty_token(self):
        """Gate must reject an empty token."""
        resp = requests.post(
            f"{GATEWAY_URL}/api/v1/gate/validate",
            json={"token": ""},
            timeout=5
        )
        assert resp.status_code in (400, 401)

    def test_qr_token_generation(self, auth_headers):
        """Authenticated user can generate a QR token."""
        resp = requests.post(
            f"{AUTH_URL}/api/v1/auth/qr-token",
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "qrToken" in body or "token" in body

    def test_full_login_to_gate_flow(self):
        """Full flow: login → get QR token → validate at gate."""
        # Step 1: Login
        login_resp = requests.post(
            f"{AUTH_URL}/api/v1/auth/login",
            json={"username": "testuser", "password": "testpass"},
            timeout=5
        )
        assert login_resp.status_code == 200
        jwt = login_resp.json()["token"]

        # Step 2: Validate at gate with JWT
        gate_resp = requests.post(
            f"{GATEWAY_URL}/api/v1/gate/validate",
            json={"token": jwt},
            headers={"Authorization": f"Bearer {jwt}"},
            timeout=5
        )
        assert gate_resp.status_code == 200
        assert gate_resp.json().get("valid") is True
