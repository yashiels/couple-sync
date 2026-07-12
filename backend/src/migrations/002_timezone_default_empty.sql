-- Couple Sync — change the users.timezone default from 'UTC' to '' so new
-- users hit the timezone-onboarding guard (hasTimezone is false on '').
-- Existing rows are NOT touched: a stored 'UTC' is ambiguous (could be a
-- legit user whose device-TZ detection failed and who saved 'UTC'), so a
-- blanket flip would wrongly re-onboard them. The default change is enough
-- to fix new signups.
ALTER TABLE users ALTER COLUMN timezone SET DEFAULT '';
