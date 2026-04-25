from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    external_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    username: Mapped[str] = mapped_column(String(128), index=True)
    auth_provider: Mapped[str] = mapped_column(String(32), default="otp")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
