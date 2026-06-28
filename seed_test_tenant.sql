-- =====================================================================
-- Smoke-test seed for tenant ledger (Issue #1 verification).
--
-- Creates:
--   * users.user_id = 21  (alice.tenant@test.local, ACTIVE)
--   * tenant_profiles.tenant_id = 1, linked to user_id = 21
--   * One placeholder lease so invoices have something to reference
--   * One ISSUED invoice  (Rs. 25000, due 2026-06-01)
--   * One COMPLETED receipt against that invoice (Rs. 15000, paid 2026-05-15)
--
-- Idempotent: uses MySQL 8 aliased INSERT ... ON DUPLICATE KEY UPDATE
-- so re-running is safe and silent (no deprecation warnings).
-- Connect as root because tenant_user / accounting_user grants are
-- scoped and can't INSERT cross-context.
--
-- NOTE: all UUIDs here are valid hex (0-9, a-f only). Earlier versions
-- of this file used readable suffixes like "00000000lea1" — MySQL stored
-- them happily, but Hibernate's UUIDJavaType chokes when it reads back
-- "l" (not hex), 500-ing the entire list endpoint. If you add more rows,
-- keep every character in 0-9 a-f.
-- =====================================================================

USE realestate3601;

-- 1. The user (iam context)
INSERT INTO users
    (user_id, uuid, full_name, email, password_hash, status)
VALUES
    (21, 'aaaaaaaa-0000-0000-0000-000000000021',
     'Alice Tenant', 'alice.tenant@test.local',
     '$2a$10$abcdefghijklmnopqrstuv', 'ACTIVE') AS new_row
ON DUPLICATE KEY UPDATE
    full_name = new_row.full_name,
    status    = new_row.status;

-- 2. The tenant profile (tenant context)
INSERT INTO tenant_profiles
    (tenant_id, user_id, preferred_contact, status)
VALUES
    (1, 21, 'EMAIL', 'ACTIVE') AS new_row
ON DUPLICATE KEY UPDATE
    preferred_contact = new_row.preferred_contact,
    status            = new_row.status;

-- 2b. Grant Alice the TENANT role so her JWT carries roles:["TENANT"]
--     and the SPA's sidebar + dashboard + post-login redirect all see her
--     as a tenant. Idempotent on the (user_id, role_id) composite PK.
INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (21, 4);

-- 3. A placeholder lease so invoices can reference it (lease_id=1).
--    We don't actually exercise the lease flow here, but invoices have
--    a non-null lease_id constraint.
INSERT INTO leases
    (lease_id, lease_uuid, unit_id, property_id, tenant_id,
     start_date, end_date, rent_amount, deposit_amount, status)
VALUES
    (1, 'aaaaaaaa-0001-0000-0000-000000000001',
     1, 1, 1,
     '2026-01-01', '2026-12-31',
     25000.0000, 50000.0000, 'ACTIVE') AS new_row
ON DUPLICATE KEY UPDATE
    lease_uuid = new_row.lease_uuid,
    status     = new_row.status;

-- 4. An invoice for the tenant
INSERT INTO invoices
    (invoice_id, public_id, tenant_id, lease_id,
     period_start, period_end, amount_due, due_date, status)
VALUES
    (1, 'aaaaaaaa-0002-0000-0000-000000000001',
     1, 1,
     '2026-05-01', '2026-05-31',
     25000.0000, '2026-06-01', 'ISSUED') AS new_row
ON DUPLICATE KEY UPDATE
    public_id  = new_row.public_id,
    amount_due = new_row.amount_due,
    status     = new_row.status;

-- 5. A partial-payment receipt against that invoice
--    method_id = 1 is BANK_TRANSFER (seeded by real_db_schema.sql)
INSERT INTO receipts
    (receipt_id, public_id, invoice_id, tenant_id,
     amount_paid, paid_at, method_id, reference, status)
VALUES
    (1, 'aaaaaaaa-0003-0000-0000-000000000001',
     1, 1,
     15000.0000, '2026-05-15 10:00:00',
     1, 'TXN-TEST-001', 'COMPLETED') AS new_row
ON DUPLICATE KEY UPDATE
    public_id   = new_row.public_id,
    amount_paid = new_row.amount_paid,
    status      = new_row.status;

-- Sanity check
SELECT 'users'           AS table_name, COUNT(*) AS rows_for_21 FROM users           WHERE user_id   = 21
UNION ALL
SELECT 'tenant_profiles' AS table_name, COUNT(*)                FROM tenant_profiles WHERE user_id   = 21
UNION ALL
SELECT 'invoices'        AS table_name, COUNT(*)                FROM invoices        WHERE tenant_id = 1
UNION ALL
SELECT 'receipts'        AS table_name, COUNT(*)                FROM receipts        WHERE tenant_id = 1;
