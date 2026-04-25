from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models.subscription import Subscription
from app.core.security import unix_timestamp_now, utcnow
from app.services.audit_service import audit_service
from app.services.marzban_client import (
    MarzbanError,
    MarzbanUnavailableError,
    MarzbanUnauthorizedError,
    marzban_client,
)


class SubscriptionService:
    def resolve_expire_timestamp(self, plan_code: str | None = None, extra_days: int | None = None) -> int:
        if extra_days is not None:
            return unix_timestamp_now() + max(extra_days, 0) * 86400

        plan_days_map = {
            "trial": 3,
            "weekly": 7,
            "monthly": 30,
            "quarterly": 90,
            "annual": 365,
        }
        selected_days = plan_days_map.get((plan_code or "").lower(), settings.default_provision_days)
        return unix_timestamp_now() + selected_days * 86400

    def get_subscription(self, db: Session, user_id: str) -> dict[str, bool | int | None]:
        subscription = db.scalar(
            select(Subscription).where(Subscription.user_external_id == user_id)
        )
        if subscription is None:
            subscription = self._sync_from_marzban(db=db, user_id=user_id)

        if subscription is None:
            audit_service.log(db=db, user_id=user_id, action="subscription.read.missing")
            return {"is_active": False, "expire_at_unix": None, "days_left": 0}

        days_left = self._calculate_days_left(subscription.expire_at_unix)
        audit_service.log(
            db=db,
            user_id=user_id,
            action="subscription.read",
            details=f"is_active={subscription.is_active};days_left={days_left}",
        )
        return {
            "is_active": subscription.is_active,
            "expire_at_unix": subscription.expire_at_unix,
            "days_left": days_left,
        }

    def set_subscription(
        self,
        db: Session,
        user_id: str,
        is_active: bool,
        expire_at_unix: int | None,
    ) -> Subscription:
        subscription = db.scalar(
            select(Subscription).where(Subscription.user_external_id == user_id)
        )
        if subscription is None:
            subscription = Subscription(user_external_id=user_id)
            db.add(subscription)

        subscription.is_active = is_active
        subscription.expire_at_unix = expire_at_unix
        db.commit()
        db.refresh(subscription)
        return subscription

    def sync_local_subscription(
        self,
        db: Session,
        user_id: str,
        expire_at_unix: int | None,
    ) -> Subscription:
        return self.set_subscription(
            db=db,
            user_id=user_id,
            is_active=bool(expire_at_unix and expire_at_unix > unix_timestamp_now()),
            expire_at_unix=expire_at_unix,
        )

    def _sync_from_marzban(self, db: Session, user_id: str) -> Subscription | None:
        try:
            remote_user = marzban_client.get_user(user_id)
        except MarzbanUnauthorizedError:
            audit_service.log(
                db=db,
                user_id=user_id,
                action="marzban.sync.auth_error",
                details="subscription lookup failed due to invalid Marzban credentials",
            )
            return None
        except MarzbanUnavailableError:
            audit_service.log(
                db=db,
                user_id=user_id,
                action="marzban.sync.unavailable",
                details="subscription lookup failed due to temporary Marzban outage",
            )
            return None
        except MarzbanError as exc:
            audit_service.log(
                db=db,
                user_id=user_id,
                action="marzban.sync.error",
                details=str(exc),
            )
            return None

        if remote_user is None:
            return None

        expire_at = remote_user.get("expire")
        subscription = self.set_subscription(
            db=db,
            user_id=user_id,
            is_active=bool(expire_at and expire_at > unix_timestamp_now()),
            expire_at_unix=expire_at,
        )
        return subscription

    def _calculate_days_left(self, expire_at_unix: int | None) -> int:
        if not expire_at_unix:
            return 0
        now_ts = unix_timestamp_now()
        return max(0, (expire_at_unix - now_ts) // 86400)


subscription_service = SubscriptionService()
