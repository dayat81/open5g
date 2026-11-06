"""Create one admin from the environment. Refuses an empty password."""

import os
import sys

from psycopg import connect
from psycopg.rows import dict_row

from open5g_dashboard.api import HASHER
from open5g_dashboard.db import apply_migrations, insert_user
from open5g_dashboard.settings import Settings


def main() -> int:
    password = os.environ.get("OPEN5G_BOOTSTRAP_PASSWORD", "")
    email = os.environ.get("OPEN5G_BOOTSTRAP_EMAIL", "")
    if len(password) < 12 or not email:
        print("Set OPEN5G_BOOTSTRAP_EMAIL and OPEN5G_BOOTSTRAP_PASSWORD (12+ characters).", file=sys.stderr)
        return 2
    settings = Settings.from_env()
    with connect(settings.database_url, row_factory=dict_row) as conn:
        apply_migrations(conn)
        user_id = insert_user(conn, email, email, "admin", None, HASHER.hash(password))
    print(user_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
