CREATE TABLE emulator_screen_status (
    ue_id text PRIMARY KEY CHECK (ue_id ~ '^[a-z][a-z0-9-]{0,31}$'),
    status text NOT NULL CHECK (status IN ('up', 'down')),
    checked_at timestamptz NOT NULL
);
