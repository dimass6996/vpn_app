from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class TelegramChatLink(Base):
    __tablename__ = "telegram_chat_links"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    telegram_username: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    chat_id: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
