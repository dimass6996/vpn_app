from sqlalchemy.orm import Session

from app.db.models.audit_log import AuditLog


class AuditService:
    def log(self, db: Session, user_id: str, action: str, details: str = "") -> None:
        db.add(AuditLog(user_id=user_id, action=action, details=details))
        db.commit()


audit_service = AuditService()
