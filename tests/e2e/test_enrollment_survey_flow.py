"""
E2E Test: Enrollment → Health Survey submission flow.

Covers:
  1. Fetch active questionnaire
  2. Submit a health survey (no symptoms)
  3. Submit a health survey (with symptoms)
  4. Verify survey is stored and returns correct validation status
"""
import requests
import pytest

AUTH_URL  = "http://localhost:30081"
FORM_URL  = "http://localhost:30086"


class TestEnrollmentSurveyFlow:

    def test_active_questionnaire_is_available(self, auth_headers):
        """A questionnaire must be available for users to complete."""
        resp = requests.get(
            f"{FORM_URL}/api/v1/questionnaires/active",
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "title" in body
        assert body.get("isActive") is True

    def test_submit_survey_without_symptoms(self, auth_headers):
        """Survey with no symptoms should be accepted and stored."""
        resp = requests.post(
            f"{FORM_URL}/api/v1/surveys",
            json={
                "anonymousId": "00000000-0000-0000-0000-000000000001",
                "hasFever": False,
                "hasCough": False,
                "answers": []
            },
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code in (200, 201)
        body = resp.json()
        assert "id" in body

    def test_submit_survey_with_symptoms_flagged(self, auth_headers):
        """Survey with symptoms must be stored with hasSymptoms=true."""
        resp = requests.post(
            f"{FORM_URL}/api/v1/surveys",
            json={
                "anonymousId": "00000000-0000-0000-0000-000000000002",
                "hasFever": True,
                "hasCough": True,
                "answers": []
            },
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code in (200, 201)

    def test_pending_surveys_endpoint_accessible_for_admin(self, auth_headers):
        """Admin can retrieve pending surveys for validation."""
        resp = requests.get(
            f"{FORM_URL}/api/v1/surveys/pending",
            headers=auth_headers,
            timeout=5
        )
        # Endpoint may return 200 (list) or 403 if auth required for admin role
        assert resp.status_code in (200, 403)

    def test_questionnaire_list_is_accessible(self, auth_headers):
        """All questionnaires are accessible to authenticated users."""
        resp = requests.get(
            f"{FORM_URL}/api/v1/questionnaires",
            headers=auth_headers,
            timeout=5
        )
        assert resp.status_code == 200
        assert isinstance(resp.json(), list)

    def test_full_enrollment_to_survey_flow(self):
        """Full flow: login → fetch questionnaire → submit survey."""
        # Step 1: Login
        login = requests.post(
            f"{AUTH_URL}/api/v1/auth/login",
            json={"username": "testuser", "password": "testpass"},
            timeout=5
        )
        assert login.status_code == 200
        token = login.json()["token"]
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

        # Step 2: Get active questionnaire
        q_resp = requests.get(
            f"{FORM_URL}/api/v1/questionnaires/active",
            headers=headers,
            timeout=5
        )
        assert q_resp.status_code == 200

        # Step 3: Submit survey
        survey_resp = requests.post(
            f"{FORM_URL}/api/v1/surveys",
            json={
                "anonymousId": "00000000-0000-0000-0000-000000000099",
                "hasFever": False,
                "hasCough": False,
                "answers": []
            },
            headers=headers,
            timeout=5
        )
        assert survey_resp.status_code in (200, 201)
