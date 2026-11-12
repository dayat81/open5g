"""Screen listener. The default bind is 127.0.0.1:3301. The browser origin is localhost:3301.

Port 3001 is Next inside the web image. This process dials l5gd-screen and
writes up/down into Postgres. The dashboard API only reads that row.
"""

import sys
import threading
import time

from open5g_dashboard.emulator_http import create_screen_app, record_screen_probes
from open5g_dashboard.settings import Settings


def probe_forever(settings: Settings) -> None:
    from psycopg import connect
    from psycopg.rows import dict_row

    interval = max(settings.emulator_probe_seconds, 2.0)
    while True:
        try:
            with connect(settings.database_url, row_factory=dict_row, autocommit=True) as conn:
                record_screen_probes(conn, settings)
        except Exception as exc:
            sys.stderr.write(f"screen probe failed: {exc.__class__.__name__}\n")
        time.sleep(interval)


def main() -> None:
    import uvicorn

    settings = Settings.from_env()
    if settings.emulator_screen_host in {"", "0.0.0.0", "::"}:
        raise RuntimeError("the screen listener must not bind every interface")
    threading.Thread(target=probe_forever, args=(settings,), name="screen-probe", daemon=True).start()
    uvicorn.run(
        create_screen_app(settings),
        host=settings.emulator_screen_host,
        port=settings.emulator_screen_bind_port,
    )


if __name__ == "__main__":
    main()
