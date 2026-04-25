# Architecture

## High-level

`Flutter App -> FastAPI BFF -> Marzban API`

## Security boundary

- Mobile app never receives `MARZBAN_SUDO_*`.
- Marzban credentials exist only in BFF runtime environment.
- All user operations go through BFF endpoints.

## Planned infra evolution

- MVP: Docker Compose
- Next: separate staging and production deployments
- Optional: migration to Kubernetes
