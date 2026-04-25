from pydantic import BaseModel


class MeResponse(BaseModel):
    user_id: str
    username: str
    auth_provider: str
    marzban_username: str | None
    marzban_link_status: str


class MarzbanLinkRequest(BaseModel):
    marzban_username: str


class MarzbanLinkResponse(BaseModel):
    marzban_username: str | None
    marzban_link_status: str
