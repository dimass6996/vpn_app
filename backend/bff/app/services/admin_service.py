import secrets

from sqlalchemy.orm import Session

from app.core.security import unix_timestamp_now
from app.services.audit_service import audit_service
from app.services.marzban_client import MarzbanError, marzban_client
from app.services.subscription_service import subscription_service


class AdminService:
    def provision_user(self, db: Session, username: str, plan_code: str) -> dict[str, str | bool]:
        action_id = f"prov_{secrets.token_hex(6)}"
        expire_at_unix = subscription_service.resolve_expire_timestamp(plan_code=plan_code)
        remote_status = self._provision_remote_user(username=username, expire_at_unix=expire_at_unix)
        subscription_service.sync_local_subscription(
            db=db,
            user_id=username,
            expire_at_unix=expire_at_unix,
        )
        audit_service.log(
            db=db,
            user_id=username,
            action="admin.provision",
            details=(
                f"plan_code={plan_code};action_id={action_id};"
                f"expire_at_unix={expire_at_unix};remote_status={remote_status}"
            ),
        )
        return {"success": True, "action_id": action_id}

    def extend_subscription(self, db: Session, username: str, extra_days: int) -> dict[str, str | bool]:
        action_id = f"ext_{secrets.token_hex(6)}"
        current = subscription_service.get_subscription(db=db, user_id=username)
        expire_at = current["expire_at_unix"]
        base_ts = expire_at if expire_at else 0
        if base_ts <= 0:
            base_ts = unix_timestamp_now()
        next_expire = base_ts + max(extra_days, 0) * 86400
        remote_status = self._extend_remote_user(username=username, next_expire=next_expire)
        subscription_service.sync_local_subscription(
            db=db,
            user_id=username,
            expire_at_unix=next_expire,
        )
        audit_service.log(
            db=db,
            user_id=username,
            action="admin.extend",
            details=(
                f"extra_days={extra_days};action_id={action_id};"
                f"next_expire={next_expire};remote_status={remote_status}"
            ),
        )
        return {"success": True, "action_id": action_id}

    def _provision_remote_user(self, username: str, expire_at_unix: int) -> str:
        if not marzban_client.is_configured():
            return "skipped_not_configured"

        payload = {
            "username": username,
            "status": "active",
            "expire": expire_at_unix,
        }
        try:
            existing = marzban_client.get_user(username)
            if existing is None:
                marzban_client.create_user(payload)
                return "created"

            update_payload = {
                "status": "active",
                "expire": expire_at_unix,
            }
            marzban_client.update_user(username, update_payload)
            return "updated_existing"
        except MarzbanError as exc:
            return f"error:{exc}"

    def _extend_remote_user(self, username: str, next_expire: int) -> str:
        if not marzban_client.is_configured():
            return "skipped_not_configured"

        try:
            existing = marzban_client.get_user(username)
            if existing is None:
                marzban_client.create_user(
                    {
                        "username": username,
                        "status": "active",
                        "expire": next_expire,
                    }
                )
                return "created_during_extend"

            marzban_client.update_user(
                username,
                {
                    "status": "active",
                    "expire": next_expire,
                },
            )
            return "updated"
        except MarzbanError as exc:
            return f"error:{exc}"


admin_service = AdminService()
