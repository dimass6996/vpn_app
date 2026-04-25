import secrets

from sqlalchemy.orm import Session

from app.services.audit_service import audit_service


class SupportService:
    def create_ticket(
        self,
        db: Session,
        user_id: str,
        subject: str,
        message: str,
    ) -> dict[str, str | bool]:
        ticket_id = secrets.token_hex(8)
        audit_service.log(
            db=db,
            user_id=user_id,
            action="support.ticket.created",
            details=f"ticket_id={ticket_id};subject={subject};message_length={len(message)}",
        )
        return {"ticket_id": ticket_id, "accepted": True}


support_service = SupportService()
