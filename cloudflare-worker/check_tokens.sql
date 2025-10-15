-- Check all FCM tokens with registration dates
SELECT
  id,
  platform,
  region,
  active,
  datetime(created_at) as registered_at,
  datetime(last_seen) as last_seen_at,
  SUBSTR(token, 1, 25) || '...' as token_preview,
  CASE
    WHEN active = 1 THEN '✅ ACTIVE'
    ELSE '❌ INACTIVE'
  END as status
FROM fcm_tokens
ORDER BY created_at DESC;
