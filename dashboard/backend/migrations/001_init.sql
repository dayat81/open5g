CREATE TABLE groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE
);

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text NOT NULL UNIQUE,
    display_name text NOT NULL,
    role text NOT NULL CHECK (role IN ('student', 'instructor', 'admin')),
    group_id uuid REFERENCES groups (id),
    password_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (role = 'admin' AND group_id IS NULL)
        OR (role IN ('student', 'instructor') AND group_id IS NOT NULL)
    )
);

CREATE TABLE sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users (id),
    token_hash text NOT NULL UNIQUE,
    csrf_token text NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE imsi_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    imsi text NOT NULL UNIQUE CHECK (imsi ~ '^[0-9]{15}$'),
    owner_user_id uuid NOT NULL REFERENCES users (id),
    group_id uuid NOT NULL REFERENCES groups (id),
    assigned_by uuid NOT NULL REFERENCES users (id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id uuid NOT NULL UNIQUE REFERENCES imsi_assignments (id),
    owner_user_id uuid NOT NULL,
    group_id uuid NOT NULL,
    desired_version integer NOT NULL CHECK (desired_version > 0),
    version_etag text NOT NULL,
    lifecycle text NOT NULL CHECK (
        lifecycle IN ('saved', 'validated', 'queued', 'pushed', 'active', 'failed', 'drift')
    ),
    content jsonb NOT NULL,
    applied_content jsonb,
    applied_version integer,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profile_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id uuid NOT NULL REFERENCES profiles (id),
    version integer NOT NULL CHECK (version > 0),
    version_etag text NOT NULL,
    content jsonb NOT NULL,
    actor_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    action text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (profile_id, version)
);

CREATE TABLE apply_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id uuid NOT NULL REFERENCES profiles (id),
    profile_version integer NOT NULL,
    actor_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    path text NOT NULL,
    status text NOT NULL,
    reasons jsonb NOT NULL,
    executed boolean NOT NULL,
    core_restart boolean NOT NULL,
    data_origin text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (actor_id, idempotency_key)
);

CREATE TABLE apply_targets (
    job_id uuid NOT NULL REFERENCES apply_jobs (id),
    target text NOT NULL,
    desired_version integer,
    applied_version integer,
    observed_version integer,
    freshness timestamptz,
    error text,
    evidence jsonb NOT NULL,
    state text NOT NULL,
    PRIMARY KEY (job_id, target)
);

CREATE TABLE audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at timestamptz NOT NULL DEFAULT now(),
    actor_id uuid,
    owner_user_id uuid,
    group_id uuid,
    action text NOT NULL,
    resource text NOT NULL,
    outcome text NOT NULL,
    reason text,
    detail jsonb NOT NULL
);

CREATE TABLE catalog_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind text NOT NULL,
    name text NOT NULL UNIQUE,
    max_ambr_dl_bps bigint,
    enforced boolean NOT NULL DEFAULT false,
    example_pending_environment_sizing boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_events_resource_idx ON audit_events (resource, at);
CREATE INDEX audit_events_actor_idx ON audit_events (actor_id, at);

CREATE OR REPLACE FUNCTION open5g_forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'immutable table %', TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER profile_versions_immutable
    BEFORE UPDATE OR DELETE ON profile_versions
    FOR EACH ROW EXECUTE FUNCTION open5g_forbid_mutation();

CREATE TRIGGER audit_events_immutable
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION open5g_forbid_mutation();

CREATE TRIGGER apply_jobs_immutable
    BEFORE UPDATE OR DELETE ON apply_jobs
    FOR EACH ROW EXECUTE FUNCTION open5g_forbid_mutation();

CREATE TRIGGER apply_targets_immutable
    BEFORE UPDATE OR DELETE ON apply_targets
    FOR EACH ROW EXECUTE FUNCTION open5g_forbid_mutation();
