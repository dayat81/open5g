ALTER TABLE subscriber_sync DROP CONSTRAINT IF EXISTS subscriber_sync_state_check;
ALTER TABLE subscriber_sync ADD CONSTRAINT subscriber_sync_state_check
    CHECK (state IN ('pending', 'written', 'unavailable', 'conflict', 'rejected', 'compensated'));
