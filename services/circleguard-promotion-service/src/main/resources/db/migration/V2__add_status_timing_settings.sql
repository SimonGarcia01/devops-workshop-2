CREATE TABLE system_settings (
    id BIGSERIAL PRIMARY KEY,
    unconfirmed_fencing_enabled BOOLEAN NOT NULL DEFAULT false,
    auto_threshold_seconds BIGINT NOT NULL DEFAULT 0,
    mandatory_fence_days INTEGER NOT NULL DEFAULT 14,
    encounter_window_days INTEGER NOT NULL DEFAULT 14
);

-- Seed initial values if not present
UPDATE system_settings SET mandatory_fence_days = 14, encounter_window_days = 14 WHERE mandatory_fence_days IS NULL;
