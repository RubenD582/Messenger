-- Add verified and developer columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS developer BOOLEAN DEFAULT FALSE;

-- Optionally, set some test users as verified/developer
-- UPDATE users SET verified = TRUE WHERE email = 'test@example.com';
-- UPDATE users SET developer = TRUE WHERE email = 'dev@example.com';
