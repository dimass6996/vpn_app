from datetime import datetime

from fastapi.testclient import TestClient
from sqlalchemy import update

from app.core.config import settings
from app.db.base import Base
from app.db.models.auth_challenge import AuthChallenge
from app.db.models.auth_session import AuthSession
from app.db.session import engine
from app.db.session import SessionLocal
from app.main import app
from app.services.rate_limit_service import rate_limit_service


client = TestClient(app)


def reset_db() -> None:
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    rate_limit_service.reset_for_tests()


def test_auth_verify_and_me_flow() -> None:
    reset_db()

    start_response = client.post(
        "/api/v1/auth/start",
        json={"login": "demo-user", "device_id": "ios-sim-1"},
    )
    assert start_response.status_code == 200
    challenge_id = start_response.json()["challenge_id"]

    verify_response = client.post(
        "/api/v1/auth/verify",
        json={
            "challenge_id": challenge_id,
            "code": "000000",
            "device_id": "ios-sim-1",
        },
    )
    assert verify_response.status_code == 200
    payload = verify_response.json()
    assert payload["access_token"]
    assert payload["refresh_token"]

    me_response = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {payload['access_token']}"},
    )
    assert me_response.status_code == 200
    assert me_response.json()["user_id"] == "demo-user"
    assert me_response.json()["marzban_link_status"] == "pending"


def test_manual_marzban_link_endpoint_links_existing_username(monkeypatch) -> None:
    reset_db()

    challenge_id = client.post(
        "/api/v1/auth/start",
        json={"login": "link-user", "device_id": "android-link-1"},
    ).json()["challenge_id"]
    payload = client.post(
        "/api/v1/auth/verify",
        json={
            "challenge_id": challenge_id,
            "code": "000000",
            "device_id": "android-link-1",
        },
    ).json()

    from app.services.marzban_link_service import marzban_client as service_client

    monkeypatch.setattr(service_client, "get_user", lambda username: {"username": username})

    response = client.post(
        "/api/v1/me/marzban/link",
        json={"marzban_username": "legacy_vpn_user"},
        headers={"Authorization": f"Bearer {payload['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["marzban_username"] == "legacy_vpn_user"
    assert response.json()["marzban_link_status"] == "linked"


def test_refresh_returns_new_access_token() -> None:
    reset_db()

    challenge_id = client.post(
        "/api/v1/auth/start",
        json={"login": "refresh-user", "device_id": "android-1"},
    ).json()["challenge_id"]
    verify_payload = client.post(
        "/api/v1/auth/verify",
        json={
            "challenge_id": challenge_id,
            "code": "000000",
            "device_id": "android-1",
        },
    ).json()

    refresh_response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": verify_payload["refresh_token"]},
    )
    assert refresh_response.status_code == 200
    assert refresh_response.json()["access_token"]


def test_auth_rate_limit_blocks_burst_requests() -> None:
    reset_db()

    response = None
    for index in range(settings.auth_rate_limit_attempts + 1):
        response = client.post(
            "/api/v1/auth/start",
            json={"login": f"burst-user-{index}", "device_id": "burst-device"},
        )

    assert response is not None
    assert response.status_code == 429


def test_auth_start_enforces_resend_cooldown_for_same_login() -> None:
    reset_db()

    login = "cooldown-user"
    first = client.post(
        "/api/v1/auth/start",
        json={"login": login, "device_id": "cooldown-device"},
    )
    second = client.post(
        "/api/v1/auth/start",
        json={"login": login, "device_id": "cooldown-device"},
    )

    assert first.status_code == 200
    assert second.status_code == 429
    assert "Retry in" in second.json()["message"]


def test_auth_verify_locks_challenge_after_max_attempts() -> None:
    reset_db()
    previous_rate_limit_attempts = settings.auth_rate_limit_attempts
    try:
        settings.auth_rate_limit_attempts = 50
        rate_limit_service.reset_for_tests()

        challenge_id = client.post(
            "/api/v1/auth/start",
            json={"login": "attempts-user", "device_id": "attempts-device"},
        ).json()["challenge_id"]

        for _ in range(settings.auth_verify_max_attempts):
            response = client.post(
                "/api/v1/auth/verify",
                json={
                    "challenge_id": challenge_id,
                    "code": "111111",
                    "device_id": "attempts-device",
                },
            )

        assert response.status_code == 400
        locked_response = client.post(
            "/api/v1/auth/verify",
            json={
                "challenge_id": challenge_id,
                "code": "000000",
                "device_id": "attempts-device",
            },
        )
        assert locked_response.status_code == 400
        assert "Challenge already used" in locked_response.json()["message"]
    finally:
        settings.auth_rate_limit_attempts = previous_rate_limit_attempts
        rate_limit_service.reset_for_tests()


def test_internal_admin_requires_api_key() -> None:
    reset_db()

    response = client.post(
        "/internal/admin/provision",
        json={"username": "admin-user", "plan_code": "mvp"},
        headers={"Idempotency-Key": "prov-1"},
    )
    assert response.status_code == 401


def test_internal_admin_idempotency_returns_same_action() -> None:
    reset_db()

    headers = {
        "X-API-Key": settings.internal_admin_api_key,
        "Idempotency-Key": "extend-1",
    }
    first = client.post(
        "/internal/admin/extend",
        json={"username": "same-user", "extra_days": 30},
        headers=headers,
    )
    second = client.post(
        "/internal/admin/extend",
        json={"username": "same-user", "extra_days": 30},
        headers=headers,
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["action_id"] == second.json()["action_id"]


def test_logout_revokes_current_session() -> None:
    reset_db()

    challenge_id = client.post(
        "/api/v1/auth/start",
        json={"login": "logout-user", "device_id": "device-logout"},
    ).json()["challenge_id"]
    verify_payload = client.post(
        "/api/v1/auth/verify",
        json={
            "challenge_id": challenge_id,
            "code": "000000",
            "device_id": "device-logout",
        },
    ).json()

    logout_response = client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": verify_payload["refresh_token"]},
        headers={"Authorization": f"Bearer {verify_payload['access_token']}"},
    )
    assert logout_response.status_code == 200
    assert logout_response.json()["success"] is True

    me_response = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {verify_payload['access_token']}"},
    )
    assert me_response.status_code == 401


def test_logout_all_revokes_all_user_sessions() -> None:
    reset_db()

    first_challenge = client.post(
        "/api/v1/auth/start",
        json={"login": "global-logout-user", "device_id": "device-1"},
    ).json()["challenge_id"]
    first_tokens = client.post(
        "/api/v1/auth/verify",
        json={"challenge_id": first_challenge, "code": "000000", "device_id": "device-1"},
    ).json()

    second_challenge = client.post(
        "/api/v1/auth/start",
        json={"login": "global-logout-user", "device_id": "device-2"},
    ).json()["challenge_id"]
    second_tokens = client.post(
        "/api/v1/auth/verify",
        json={"challenge_id": second_challenge, "code": "000000", "device_id": "device-2"},
    ).json()

    logout_all_response = client.post(
        "/api/v1/auth/logout-all",
        headers={"Authorization": f"Bearer {first_tokens['access_token']}"},
    )
    assert logout_all_response.status_code == 200
    assert logout_all_response.json()["revoked_sessions"] >= 2

    first_me = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {first_tokens['access_token']}"},
    )
    second_me = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {second_tokens['access_token']}"},
    )
    assert first_me.status_code == 401
    assert second_me.status_code == 401


def test_cleanup_auth_removes_expired_records() -> None:
    reset_db()

    challenge_id = client.post(
        "/api/v1/auth/start",
        json={"login": "cleanup-user", "device_id": "cleanup-device"},
    ).json()["challenge_id"]
    verify_payload = client.post(
        "/api/v1/auth/verify",
        json={"challenge_id": challenge_id, "code": "000000", "device_id": "cleanup-device"},
    ).json()

    with SessionLocal() as session:
        expired_at = datetime(2000, 1, 1)
        session.execute(update(AuthChallenge).values(expires_at=expired_at))
        session.execute(update(AuthSession).values(expires_at=expired_at))
        session.commit()

    cleanup_response = client.post(
        "/internal/maintenance/cleanup-auth",
        headers={"X-API-Key": settings.internal_admin_api_key},
    )
    assert cleanup_response.status_code == 200
    assert cleanup_response.json()["deleted_challenges"] >= 1
    assert cleanup_response.json()["deleted_sessions"] >= 1
