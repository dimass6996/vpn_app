from pydantic import BaseModel


class ProvisionRequest(BaseModel):
    username: str
    plan_code: str


class ExtendRequest(BaseModel):
    username: str
    extra_days: int


class AdminActionResponse(BaseModel):
    success: bool
    action_id: str
