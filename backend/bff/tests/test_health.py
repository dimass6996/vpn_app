from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_ok() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert response.headers["X-Request-ID"]


def test_validation_errors_have_stable_shape() -> None:
    response = client.post(
        "/api/v1/support/request",
        json={"subject": "x", "message": "bad"},
    )
    assert response.status_code == 401
    payload = response.json()
    assert payload["code"] == "http_error"
    assert payload["request_id"]


def test_request_validation_error_shape() -> None:
    response = client.post(
        "/api/v1/auth/start",
        json={"device_id": "missing-login"},
    )
    assert response.status_code == 422
    payload = response.json()
    assert payload["code"] == "validation_error"
    assert payload["request_id"]
    assert payload["details"]
