CREATE TABLE subscriber_sync (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id uuid NOT NULL REFERENCES profiles (id),
    desired_version integer NOT NULL,
    state text NOT NULL CHECK (state IN ('pending', 'written', 'unavailable', 'conflict', 'rejected')),
    mongo_generation integer,
    detail jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    observed_at timestamptz
);

CREATE INDEX subscriber_sync_profile_idx ON subscriber_sync (profile_id, created_at);
