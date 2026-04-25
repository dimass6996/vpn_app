# Arbuz VPN Mobile Stack Handoff (Flutter + FastAPI)

Дата: 2026-04-24

Этот файл можно отправить в новый чат целиком.

---

## 1) Готовый промпт для нового чата

```text
Ты senior engineer (Flutter + FastAPI + DevOps). Нужен production-ready MVP мобильного приложения Arbuz VPN.

Стек зафиксирован:
- Mobile: Flutter (Dart)
- Backend BFF: FastAPI (Python)
- DB BFF: PostgreSQL
- Cache/ratelimit: Redis
- Infra: Docker Compose (MVP), далее migration в k8s опционально

Цель:
Сделать мобильное приложение iOS/Android, которое работает через BFF API и НЕ хранит SUDO доступ к Marzban в клиенте.

Серверный контекст:
- Marzban API локально: http://127.0.0.1:8000
- Домен панели через Caddy: dimass6996-vps.duckdns.org
- Активные inbound:
  - VLESS_REALITY (2053/tcp)
  - WIREGUARD_INBOUND (51820/udp)
  - Shadowsocks TCP (1080/tcp+udp)
  - VMESS_WS_TLS (2087/tcp)
  - TROJAN_TLS (8443/tcp)

Требования к результату:
1) Дай финальную архитектуру компонентов (Flutter app, BFF, DB, Redis, Marzban integration).
2) Спроектируй BFF API-контракт:
   - /auth/start, /auth/verify, /auth/refresh
   - /me
   - /subscription
   - /configs
   - /support/request
   - admin/private endpoints для provisioning и продления
3) Сгенерируй skeleton проекта:
   - monorepo структура
   - docker-compose для dev
   - базовые модели/роуты/сервисы FastAPI
   - базовая архитектура Flutter (feature-first + state management)
4) Добавь безопасность:
   - JWT access/refresh
   - rate limiting
   - audit log
   - idempotency для важных операций
5) Подготовь пошаговый план реализации (2-4 недели) с приоритетами MVP.

Важно:
- Нельзя использовать SUDO_USERNAME/SUDO_PASSWORD в мобильном приложении.
- Нельзя коммитить секреты.
- Все операции с Marzban только через backend BFF.

Формат ответа:
- сначала итоговая архитектура;
- затем файловая структура и код-скелет;
- затем API-спека;
- затем roadmap;
- затем чеклист "что запросить у владельца сервера".
```

---

## 2) Рекомендуемая монорепа структура

```text
arbuz-vpn/
  mobile/
    app/                       # Flutter app
      lib/
        core/
          config/
          networking/
          storage/
          ui/
        features/
          auth/
          profile/
          subscription/
          configs/
          support/
        main.dart
      test/
      pubspec.yaml
  backend/
    bff/
      app/
        api/
          v1/
            auth.py
            users.py
            subscription.py
            configs.py
            support.py
            admin.py
        core/
          config.py
          security.py
          logging.py
          rate_limit.py
        db/
          base.py
          session.py
          models/
            user.py
            auth_session.py
            subscription.py
            audit_log.py
        services/
          marzban_client.py
          auth_service.py
          subscription_service.py
          config_service.py
        schemas/
        main.py
      migrations/
      tests/
      requirements.txt
      Dockerfile
  infra/
    docker-compose.yml
    .env.example
  docs/
    ARCHITECTURE.md
    API.md
    SECURITY.md
  README.md
```

---

## 3) Минимальный BFF API (MVP)

### Auth
- `POST /api/v1/auth/start`
  - request: `{ "login": "..." }`
  - response: `{ "challenge_id": "...", "method": "otp|telegram" }`

- `POST /api/v1/auth/verify`
  - request: `{ "challenge_id": "...", "code": "123456" }`
  - response: `{ "access_token": "...", "refresh_token": "...", "expires_in": 900 }`

- `POST /api/v1/auth/refresh`
  - request: `{ "refresh_token": "..." }`
  - response: `{ "access_token": "...", "expires_in": 900 }`

### User
- `GET /api/v1/me`
- `GET /api/v1/subscription`
- `GET /api/v1/configs`
  - response: протоколы + ссылки/параметры для клиента

### Support
- `POST /api/v1/support/request`
  - request: `{ "subject": "...", "message": "..." }`

### Internal Admin (private)
- `POST /internal/admin/provision`
- `POST /internal/admin/extend`

---

## 4) Marzban integration policy

BFF должен использовать отдельные env:
- `MARZBAN_BASE_URL=http://127.0.0.1:8000`
- `MARZBAN_SUDO_USERNAME=...`
- `MARZBAN_SUDO_PASSWORD=...`

Разрешенные операции BFF -> Marzban:
- `POST /api/admin/token`
- `GET /api/user/{username}`
- `PUT /api/user/{username}`
- `GET /api/users` (по необходимости)
- `POST /api/user` (только internal admin flow)

Запрещено:
- передавать `MARZBAN_SUDO_*` в mobile client;
- отдавать чувствительные внутренние поля Marzban напрямую в app.

---

## 5) Flutter app screens (MVP)

1. Splash + version check
2. Onboarding
3. Auth (start/verify)
4. Home dashboard
   - статус подписки
   - days left
   - quick actions
5. Configs screen
   - протоколы
   - copy/share/import config
6. Support screen
7. Settings
   - language/theme
   - logout

---

## 6) Security baseline

- JWT access (15m) + refresh (30d)
- Hash refresh tokens в БД
- Device/session binding (по device_id)
- Redis rate limit на auth endpoints
- Audit log:
  - login success/fail
  - config access
  - subscription mutations
- Idempotency key на billing/provision endpoints

---

## 7) Dev docker-compose (MVP)

Сервисы:
- `bff` (FastAPI)
- `postgres`
- `redis`
- `nginx` (optional local reverse proxy)

В `.env.example`:
- `BFF_ENV=dev`
- `BFF_SECRET_KEY=...`
- `DATABASE_URL=postgresql+psycopg://...`
- `REDIS_URL=redis://redis:6379/0`
- `MARZBAN_BASE_URL=http://host.docker.internal:8000` (для локальной разработки)
- `MARZBAN_SUDO_USERNAME=...`
- `MARZBAN_SUDO_PASSWORD=...`

---

## 8) План реализации (предложение)

Неделя 1:
- BFF skeleton + auth + DB schema + Redis rate limit.
- Flutter skeleton + routing + auth screens.

Неделя 2:
- Subscription/config endpoints + UI screens.
- Support endpoint + support UI.

Неделя 3:
- Harden: audit, token rotation, error handling, retry/backoff.
- E2E smoke tests + release candidate.

Неделя 4 (опционально):
- Billing flow integration (YooKassa webhook + app UX).

---

## 9) Что запросить у владельца сервера (чеклист)

1. Выбранный метод авторизации (Telegram / phone OTP / email).
2. Mapping user identity -> marzban username.
3. Какие протоколы по умолчанию в mobile app (VLESS main, WireGuard fallback и т.п.).
4. Тарифы, trial, правила продления.
5. Нужны ли push-уведомления (FCM/APNs) и тексты шаблонов.
6. Политика хранения логов и срок retention.
7. Домен для BFF и TLS сертификаты.

---

## 10) Локальные справочные файлы на сервере

- /root/MOBILE_APP_HANDOFF_2026-04-24.md
- /root/SERVER_OVERVIEW.txt
- /root/PLAN_TASK.txt
- /var/lib/marzban/xray_config.json
- /opt/marzban/bot_src/main.py
- /opt/marzban/admin_bot/main.py

