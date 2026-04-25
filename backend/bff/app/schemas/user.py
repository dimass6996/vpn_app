from pydantic import BaseModel


class MeResponse(BaseModel):
    user_id: str
    username: str
    auth_provider: str
