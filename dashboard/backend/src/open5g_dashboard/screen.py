"""Screen listener. Bind a host that is not the dashboard host. Cookies ignore ports."""

from open5g_dashboard.emulator_http import create_screen_app
from open5g_dashboard.settings import Settings


def main() -> None:
    import uvicorn

    settings = Settings.from_env()
    if settings.emulator_screen_host in {"", "0.0.0.0", "::"}:
        raise RuntimeError("the screen listener must not bind every interface")
    uvicorn.run(
        create_screen_app(settings),
        host=settings.emulator_screen_host,
        port=settings.emulator_screen_bind_port,
    )


if __name__ == "__main__":
    main()
