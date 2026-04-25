from app.services.config_service import ConfigService
from app.services.marzban_client import marzban_client


def test_resolve_subscription_url_keeps_absolute_url() -> None:
    service = ConfigService()
    absolute = "https://example.com/sub/abc"
    assert service._resolve_subscription_url(absolute) == absolute


def test_resolve_subscription_url_converts_relative_path_to_absolute() -> None:
    service = ConfigService()
    base_url = marzban_client.base_url
    assert service._resolve_subscription_url("/sub/token") == f"{base_url}/sub/token"


def test_resolve_subscription_url_converts_plain_relative_value() -> None:
    service = ConfigService()
    base_url = marzban_client.base_url
    assert service._resolve_subscription_url("sub/token") == f"{base_url}/sub/token"


def test_build_sing_box_url_appends_query_param() -> None:
    service = ConfigService()
    assert (
        service._build_sing_box_url("https://example.com/sub/abc")
        == "https://example.com/sub/abc?format=sing-box"
    )


def test_build_sing_box_url_uses_ampersand_for_existing_query() -> None:
    service = ConfigService()
    assert (
        service._build_sing_box_url("https://example.com/sub/abc?token=1")
        == "https://example.com/sub/abc?token=1&format=sing-box"
    )
