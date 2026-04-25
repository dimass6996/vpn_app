.PHONY: env-init backend-up backend-down backend-logs backend-smoke backend-smoke-http backend-smoke-console otp-contract-check marzban-probe marzban-upsert-user mobile-test mobile-check dev-check mobile-linux mobile-web mobile-android-push-singbox

env-init:
	cp -n infra/.env.example infra/.env || true

backend-up:
	docker compose -f infra/docker-compose.yml --env-file infra/.env up --build -d

backend-down:
	docker compose -f infra/docker-compose.yml --env-file infra/.env down

backend-logs:
	docker compose -f infra/docker-compose.yml --env-file infra/.env logs -f bff

backend-smoke:
	bash scripts/backend_smoke.sh

backend-smoke-http:
	bash scripts/backend_smoke_http.sh

backend-smoke-console:
	bash scripts/backend_smoke_console.sh

otp-contract-check:
	bash scripts/otp_provider_contract_check.sh

marzban-probe:
	bash scripts/marzban_probe.sh

marzban-upsert-user:
	bash scripts/marzban_upsert_user.sh

mobile-test:
	cd mobile/app && env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY -u no_proxy -u NO_PROXY flutter test

mobile-check:
	cd mobile/app && flutter analyze

dev-check: backend-smoke mobile-test mobile-check

mobile-linux:
	cd mobile/app && env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY -u no_proxy -u NO_PROXY flutter run -d linux --dart-define=API_BASE_URL=http://194.50.94.81:8001/api/v1

mobile-web:
	cd mobile/app && env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY -u no_proxy -u NO_PROXY flutter run -d chrome

mobile-android-push-singbox:
	bash scripts/mobile_android_push_singbox.sh
