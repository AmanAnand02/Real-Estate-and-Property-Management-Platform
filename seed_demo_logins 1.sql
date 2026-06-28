-- =====================================================================
-- Common demo login accounts — one real, loginable user per role.
--
-- Shared password for ALL four accounts: Demo@1234
--
--   Role              Email                        user_id  role_id
--   ----------------  ---------------------------  -------  -------
--   ADMIN             admin@horizon.local          101      1
--   LEASING_AGENT     leasing@horizon.local        102      3
--   MAINTENANCE_TECH  maintenance@horizon.local    103      5
--   TENANT            tenant@horizon.local          104      4
--   PROPERTY_MANAGER  manager@horizon.local        105      2
--
-- The password_hash below is a real BCryptPasswordEncoder hash (cost=10)
-- of "Demo@1234" — the exact hash iam-service's own encoder produced, so
-- AuthService.login() round-trips correctly for all four accounts.
--
-- Why this file exists:
--   * Anyone who clones the repo and runs `docker compose up -d` gets four
--     ready-to-use logins (one per role) with no manual seeding step.
--   * It is mounted as /docker-entrypoint-initdb.d/03-demo-logins.sql, so
--     MySQL runs it on a FRESH database, after 01-schema.sql (which creates
--     the users/roles/tenant_profiles tables and seeds the role rows whose
--     role_ids are fixed by insertion order: ADMIN=1, PROPERTY_MANAGER=2,
--     LEASING_AGENT=3, TENANT=4, MAINTENANCE_TECH=5).
--
-- WARNING: these are intentionally weak, committed credentials for demo /
-- local development ONLY. Never use them in a real deployment.
--
-- Idempotent: re-running is safe and silent (MySQL 8 aliased syntax).
-- Connect as root because audit/tenant grants are service-scoped.
--
-- NOTE: all UUIDs here are valid hex (0-9, a-f only). Hibernate's
-- UUIDJavaType 500s when it reads back a non-hex char (see seed_test_tenant.sql).
-- =====================================================================

USE realestate3601;

-- ---------------------------------------------------------------------
-- Step 1: Insert / refresh the four demo users (idempotent).
-- ---------------------------------------------------------------------
INSERT INTO users
    (user_id, uuid, full_name, email, password_hash, status)
VALUES
    (101, 'aaaaaaaa-0000-0000-0000-000000000101',
     'Demo Admin', 'admin@horizon.local',
     '$2a$10$U0eR.TvooI6/jHuBO3et3uoZ3Fu7kMvVGug/YYZlViblHyFg5liSS', 'ACTIVE'),
    (102, 'aaaaaaaa-0000-0000-0000-000000000102',
     'Demo Leasing Agent', 'leasing@horizon.local',
     '$2a$10$U0eR.TvooI6/jHuBO3et3uoZ3Fu7kMvVGug/YYZlViblHyFg5liSS', 'ACTIVE'),
    (103, 'aaaaaaaa-0000-0000-0000-000000000103',
     'Demo Maintenance Tech', 'maintenance@horizon.local',
     '$2a$10$U0eR.TvooI6/jHuBO3et3uoZ3Fu7kMvVGug/YYZlViblHyFg5liSS', 'ACTIVE'),
    (104, 'aaaaaaaa-0000-0000-0000-000000000104',
     'Demo Tenant', 'tenant@horizon.local',
     '$2a$10$U0eR.TvooI6/jHuBO3et3uoZ3Fu7kMvVGug/YYZlViblHyFg5liSS', 'ACTIVE'),
    (105, 'aaaaaaaa-0000-0000-0000-000000000105',
     'Demo Property Manager', 'manager@horizon.local',
     '$2a$10$U0eR.TvooI6/jHuBO3et3uoZ3Fu7kMvVGug/YYZlViblHyFg5liSS', 'ACTIVE') AS new_row
ON DUPLICATE KEY UPDATE
    full_name     = new_row.full_name,
    email         = new_row.email,
    password_hash = new_row.password_hash,
    status        = new_row.status;

-- ---------------------------------------------------------------------
-- Step 2: Assign each user its role (idempotent on the composite PK).
--   101 -> ADMIN(1), 102 -> LEASING_AGENT(3),
--   103 -> MAINTENANCE_TECH(5), 104 -> TENANT(4),
--   105 -> PROPERTY_MANAGER(2)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO user_roles (user_id, role_id) VALUES
    (101, 1),
    (102, 3),
    (103, 5),
    (104, 4),
    (105, 2);

-- ---------------------------------------------------------------------
-- Step 3: Back the tenant account with a tenant_profiles row so the
--   tenant dashboard / profile pages (/tenants/me/profile) resolve.
--   tenant_id = 2 to avoid the existing test tenant (tenant_id = 1).
-- ---------------------------------------------------------------------
INSERT INTO tenant_profiles
    (tenant_id, user_id, preferred_contact, status)
VALUES
    (2, 104, 'EMAIL', 'ACTIVE') AS new_row
ON DUPLICATE KEY UPDATE
    preferred_contact = new_row.preferred_contact,
    status            = new_row.status;

-- ---------------------------------------------------------------------
-- Step 4: Sanity check — must return the four users with their roles.
-- ---------------------------------------------------------------------
SELECT u.user_id, u.email, u.status, r.name AS role_name
FROM users u
JOIN user_roles ur ON ur.user_id = u.user_id
JOIN roles r       ON r.role_id  = ur.role_id
WHERE u.user_id BETWEEN 101 AND 105
ORDER BY u.user_id;
