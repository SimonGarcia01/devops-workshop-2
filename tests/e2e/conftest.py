import pytest
import requests

AUTH_URL     = "http://localhost:30081"
GATEWAY_URL  = "http://localhost:30087"
FORM_URL     = "http://localhost:30086"
DASHBOARD_URL = "http://localhost:30084"


def is_service_up(url: str) -> bool:
    try:
        r = requests.get(f"{url}/actuator/health", timeout=3)
        return r.status_code == 200
    except Exception:
        return False


@pytest.fixture(scope="session", autouse=True)
def require_services():
    unavailable = []
    for name, url in [("auth", AUTH_URL), ("gateway", GATEWAY_URL), ("form", FORM_URL)]:
        if not is_service_up(url):
            unavailable.append(f"{name} ({url})")
    if unavailable:
        pytest.skip(f"Services not running: {', '.join(unavailable)}")


@pytest.fixture(scope="session")
def auth_token():
    """Login and return a valid JWT token for the test session."""
    resp = requests.post(
        f"{AUTH_URL}/api/v1/auth/login",
        json={"username": "testuser", "password": "testpass"},
        timeout=5
    )
    assert resp.status_code == 200, f"Login failed: {resp.text}"
    return resp.json()["token"]


@pytest.fixture(scope="session")
def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}", "Content-Type": "application/json"}
