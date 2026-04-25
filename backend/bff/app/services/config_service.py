from sqlalchemy.orm import Session

from app.db.models.user import User
from app.services.audit_service import audit_service
from app.services.marzban_client import MarzbanError, marzban_client
from app.services.marzban_link_service import marzban_link_service


class ConfigService:
    def get_configs(self, db: Session, user: User) -> list[dict[str, str]]:
        marzban_username = marzban_link_service.resolve_username(db=db, user=user, auto_create=True)
        remote_user = None
        try:
            if marzban_username:
                remote_user = marzban_client.get_user(marzban_username)
        except MarzbanError as exc:
            audit_service.log(
                db=db,
                user_id=user.external_id,
                action="configs.read.marzban_error",
                details=str(exc),
            )
            remote_user = None

        if remote_user and remote_user.get("subscription_url"):
            resolved_subscription_url = self._resolve_subscription_url(
                remote_user["subscription_url"]
            )
            items = self._build_subscription_items(resolved_subscription_url)
        else:
            items = self._build_placeholder_items()

        audit_service.log(
            db=db,
            user_id=user.external_id,
            action="configs.read",
            details=f"items={len(items)}",
        )
        return items

    def _build_subscription_items(self, subscription_url: str) -> list[dict[str, str]]:
        sing_box_url = self._build_sing_box_url(subscription_url)
        return [
            {
                "protocol": "subscription",
                "label": "Primary subscription",
                "value": subscription_url,
            },
            {
                "protocol": "sing-box-subscription",
                "label": "Sing-box runtime profile",
                "value": sing_box_url,
            },
        ]

    def _build_placeholder_items(self) -> list[dict[str, str]]:
        return [
            {
                "protocol": "subscription",
                "label": "Development placeholder",
                "value": "https://example.com/sub/REPLACE_ME",
            }
        ]

    def _resolve_subscription_url(self, subscription_url: str) -> str:
        value = subscription_url.strip()
        if value.startswith("https://") or value.startswith("http://"):
            return value
        if value.startswith("/"):
            return f"{marzban_client.base_url}{value}"
        return f"{marzban_client.base_url}/{value}"

    def _build_sing_box_url(self, subscription_url: str) -> str:
        separator = "&" if "?" in subscription_url else "?"
        return f"{subscription_url}{separator}format=sing-box"


config_service = ConfigService()
