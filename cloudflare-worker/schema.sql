-- FCM Device Tokens Database Schema
-- Stores device tokens for Firebase Cloud Messaging push notifications

CREATE TABLE IF NOT EXISTS fcm_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT UNIQUE NOT NULL,                     -- FCM device token
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),  -- Device platform
  region TEXT DEFAULT 'AT',                       -- User's region (AT, DE, etc.)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- First registration
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- Last update/ping
  active INTEGER DEFAULT 1                        -- 1=active, 0=deactivated
);

-- Index for fast lookups of active tokens
CREATE INDEX IF NOT EXISTS idx_active_tokens
ON fcm_tokens(active)
WHERE active = 1;

-- Index for filtering by region
CREATE INDEX IF NOT EXISTS idx_region
ON fcm_tokens(region, active);
