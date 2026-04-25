Use this prompt on Codex running on your VPS.

---

You are on Ubuntu/Fedora Linux VPS.  
Goal: deploy Arbuz VPN project from GitHub and run backend for production tests.

Server constants:
- Public server IP: `194.50.94.81`
- Marzban is on the same server
- Backend API must be reachable at `http://194.50.94.81:8001`

Tasks:
1. Clone/update repository:
   - If `/opt/VPNapp` does not exist: `git clone <REPO_URL> /opt/VPNapp`
   - Else: `cd /opt/VPNapp && git pull --ff-only`
2. Create and configure env file:
   - `cp -n infra/.env.example infra/.env`
   - Set in `infra/.env`:
     - `APP_ENV=prod`
     - `DATABASE_URL=sqlite+pysqlite:///./arbuz.db` (or postgres DSN if available)
     - `AUTH_PROVIDER=telegram`
     - `AUTH_TELEGRAM_BOT_TOKEN=<REAL_TOKEN>`
     - `AUTH_TELEGRAM_BOT_USERNAME=arbuz_auth_bot`
     - `AUTH_TELEGRAM_API_BASE=https://api.telegram.org`
     - `AUTH_TELEGRAM_TRUST_ENV=true`
     - `AUTH_MAGIC_LINK_BASE_URL=http://194.50.94.81/auth`
     - `MARZBAN_BASE_URL=http://194.50.94.81`
     - `MARZBAN_SUDO_USERNAME=<REAL_USERNAME>`
     - `MARZBAN_SUDO_PASSWORD=<REAL_PASSWORD>`
     - `SECRET_KEY=<LONG_RANDOM>`
3. Install backend dependencies:
   - `cd /opt/VPNapp/backend/bff`
   - `python3 -m venv .venv`
   - `source .venv/bin/activate`
   - `python -m pip install -U pip`
   - `python -m pip install -r requirements.txt`
4. Run migrations:
   - `export PYTHONPATH=.`
   - `set -a && source /opt/VPNapp/infra/.env && set +a`
   - `alembic upgrade head`
5. Run backend (systemd service preferred):
   - Create `/etc/systemd/system/arbuz-bff.service`:
     - WorkingDirectory=`/opt/VPNapp/backend/bff`
     - EnvironmentFile=`/opt/VPNapp/infra/.env`
     - Environment=`PYTHONPATH=.`
     - ExecStart=`/opt/VPNapp/backend/bff/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8001`
     - Restart=always
   - `sudo systemctl daemon-reload`
   - `sudo systemctl enable --now arbuz-bff`
6. Validate:
   - `curl -sS http://127.0.0.1:8001/health`
   - `curl -sS http://194.50.94.81:8001/health`
   - Run smoke:
     - `cd /opt/VPNapp`
     - `SMOKE_LOGIN=<telegram_username> make backend-smoke-console`
7. Print final report:
   - service status
   - health response
   - smoke result
   - any errors with exact logs and fixes applied

Rules:
- Do not skip failed steps; fix and continue.
- Keep all edits in repository files where appropriate.
- Do not hardcode secrets in tracked files; only put secrets into `infra/.env` on server.

---
