from pydantic import BaseModel


class CleanupResponse(BaseModel):
    deleted_challenges: int
    deleted_sessions: int
