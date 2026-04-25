from pydantic import BaseModel, Field


class SupportRequest(BaseModel):
    subject: str = Field(min_length=3, max_length=128)
    message: str = Field(min_length=5, max_length=4000)


class SupportResponse(BaseModel):
    ticket_id: str
    accepted: bool
