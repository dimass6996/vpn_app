from pydantic import BaseModel


class SubscriptionResponse(BaseModel):
    is_active: bool
    expire_at_unix: int | None
    days_left: int
