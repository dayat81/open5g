CREATE TABLE emulator_endpoints (
    ue_id text PRIMARY KEY CHECK (ue_id ~ '^[a-z][a-z0-9-]{0,31}$'),
    assignment_id uuid REFERENCES imsi_assignments (id),
    internal_host text,
    internal_port integer,
    apn text,
    attach_ipv4 text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (internal_host IS NULL AND internal_port IS NULL)
        OR (
            internal_host IS NOT NULL
            AND internal_port IS NOT NULL
            AND internal_port BETWEEN 1 AND 65535
            AND internal_host NOT IN ('0.0.0.0', '::', '*')
        )
    )
);

CREATE TABLE emulator_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ue_id text NOT NULL,
    actor_id uuid NOT NULL REFERENCES users (id),
    token_hash text NOT NULL UNIQUE,
    opened_at timestamptz NOT NULL DEFAULT now(),
    last_active_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    close_reason text
);

CREATE UNIQUE INDEX emulator_one_open_control
    ON emulator_sessions (ue_id)
    WHERE closed_at IS NULL;
