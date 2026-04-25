# Arbuz VPN Mobile App Handoff (2026-04-24)

Этот файл можно отправить в новый чат целиком.

---

## 1) Готовый промпт для нового чата

```text
Ты senior mobile + backend engineer. Нужна разработка мобильного приложения для Arbuz VPN (iOS/Android) с продуманной архитектурой, безопасной авторизацией и удобным UX.

Контекст:
- VPN backend: Marzban (Xray), Caddy reverse proxy.
- Telegram-боты уже работают, VPN называется Arbuz VPN.
- На сервере уже есть активные inbound протоколы:
  - VLESS_REALITY (2053/tcp)
  - WIREGUARD_INBOUND (51820/udp)
  - Shadowsocks TCP (1080/tcp+udp)
  - VMESS_WS_TLS (2087/tcp)
  - TROJAN_TLS (8443/tcp)
- Пользовательская подписка в Marzban выдается как /sub/... URL.

Что нужно сделать:
1) Предложить production-архитектуру мобильного приложения, где мобильное приложение НЕ хранит sudo-учетку Marzban.
2) Сразу спроектировать backend-gateway (BFF API), через который мобильное приложение будет:
   - авторизовывать пользователя;
   - получать профиль и статус подписки;
   - получать безопасно список конфигов/ссылок подключения;
   - обновлять подписку (когда будет подключена оплата).
3) Продумать UX и flow:
   - onboarding;
   - вход (по номеру/telegram/deeplink/код подтверждения — предложи лучший вариант);
   - экран статуса подписки;
   - экран “быстрое подключение”;
   - экран “поддержка”.
4) Подготовить MVP roadmap с этапами, оценками и рисками.
5) Подготовить структуру репозитория и базовый код (если возможно).

Ограничения/требования:
- Не использовать в клиентском приложении SUDO_USERNAME/SUDO_PASSWORD.
- Добавить rate limit, audit log, idempotency для критичных операций.
- Поддержать iOS/Android.
- Объяснить, какие данные надо взять с сервера и в каком формате.

Формат ответа:
- Сначала короткая целевая архитектура (схема по компонентам).
- Потом API-контракт BFF (эндпоинты, request/response, auth).
- Потом план реализации по неделям.
- Потом список конкретных данных, которые надо запросить у владельца сервера.
```

---

## 2) Текущая инфраструктура (актуально)

- Сервер: `194.50.94.81`
- Домен панели/API через Caddy: `dimass6996-vps.duckdns.org`
- Панель Marzban (локально): `http://127.0.0.1:8000`
- Основная БД Marzban: `/var/lib/marzban/db.sqlite3`
- Xray config path: `/var/lib/marzban/xray_config.json`

Docker-контейнеры:
- `marzban_panel`
- `marzban_client_bot`
- `marzban_admin_bot`
- `marzban_backup_bot`

---

## 3) Доступные протоколы/порты (факт на сервере)

- `VLESS_REALITY` -> `2053/tcp`
- `WIREGUARD_INBOUND` -> `51820/udp`
- `Shadowsocks TCP` -> `1080/tcp` и `1080/udp`
- `VMESS_WS_TLS` -> `2087/tcp`
- `TROJAN_TLS` -> `8443/tcp`

UFW currently allows:
- `22/tcp`, `80/tcp`, `443/tcp`, `443/udp`,
- `2053/tcp`, `51820/udp`,
- `1080/tcp`, `1080/udp`,
- `2087/tcp`, `8443/tcp`.

---

## 4) Как сейчас работает пользовательская модель

- Пользователи хранятся в Marzban.
- Для пользователя есть `subscription_url` формата `/sub/...`.
- Ключевое поле подписки: `expire` (unix timestamp).

Используемые API (через bearer token):
- `POST /api/admin/token`
- `GET /api/users`
- `GET /api/user/{username}`
- `PUT /api/user/{username}`
- `POST /api/user`
- `DELETE /api/user/{username}`

---

## 5) Что запросить с сервера для мобильного проекта

Ниже чеклист данных, которые нужно получить перед началом разработки:

### A. Продукт/бизнес
- Какой способ идентификации пользователя в мобильном приложении выбран (телефон, Telegram, email, другое).
- Тарифы и правила продления.
- Нужна ли trial-подписка.

### B. Технические данные
- Целевой стек мобильного приложения (Flutter или React Native или native).
- Где будет размещен BFF backend (домен, сервер, runtime).
- Финальный auth-метод для BFF:
  - JWT + refresh;
  - OTP;
  - Telegram Login/deeplink.

### C. VPN данные
- Какие протоколы показывать в приложении как основные/резервные.
- Нужен ли WireGuard-first для части пользователей.
- Политика выдачи конфигов: только subscription URL или генерация отдельных профилей.

### D. Security
- Политика хранения логов и PII.
- Rate limit требования.
- Нужна ли 2FA для админ-панели BFF.

### E. Интеграции
- Подключена ли оплата (ЮKassa) и какие webhook события нужны для mobile-flow.

---

## 6) Рекомендуемая архитектура (коротко)

`Mobile App -> BFF API -> Marzban API`

Почему так:
- мобильный клиент не хранит SUDO credentials;
- можно ограничить набор операций и добавить аудит;
- проще безопасно масштабировать и менять auth/payment.

Минимальный BFF API для MVP:
- `POST /auth/start`
- `POST /auth/verify`
- `GET /me`
- `GET /subscription`
- `GET /configs`
- `POST /support/request`

Admin/Billing (внутренние):
- `POST /admin/provision`
- `POST /admin/extend`
- `POST /billing/webhook/yookassa`

---

## 7) Что уже улучшено на сервере (важно для нового чата)

- Включен firewall и ограничены входящие порты.
- Усилены права на `.env`, backup и БД файлы.
- Backup-бот переведен на безопасную модель (`full` и `safe` архивы).
- Клиент-бот Arbuz VPN:
  - обновленный onboarding/UI;
  - аутентификация пользователя по `/sub/...` ссылке;
  - защита «одна VPN-привязка -> один Telegram ID».
- Админ-бот:
  - проведен UX-рефакторинг;
  - кнопочное управление пользователями, карточки, пагинация.

---

## 8) Важные ограничения

- Не публиковать и не передавать в мобильный клиент `SUDO_USERNAME/SUDO_PASSWORD`.
- Не коммитить секреты в git.
- Не использовать формулировки в UI про «доступ ко всем сайтам».

---

## 9) Полезные файлы на сервере

- `/root/SERVER_OVERVIEW.txt`
- `/root/PLAN_TASK.txt`
- `/root/MOBILE_APP_HANDOFF_2026-04-24.md`
- `/opt/marzban/bot_src/main.py`
- `/opt/marzban/admin_bot/main.py`
- `/var/lib/marzban/xray_config.json`

