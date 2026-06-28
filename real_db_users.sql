-- =====================================================================
-- Project      : RealEstate360 - Property Management & Real Estate Ops
-- File         : realestate360_users.sql
-- Purpose      : Create one MySQL user per bounded context with the
--                minimum privileges that context's microservice needs.
--                This enforces logical separation at the database
--                level: a service connecting as 'leasing_user' simply
--                cannot touch tables outside the leasing context, even
--                if a developer writes the wrong query.
-- DBMS         : MySQL 8.0+
-- Run as       : root / admin user, AFTER realestate3601_schema.sql
--
-- Privilege model
--   * Owns its own context tables : SELECT, INSERT, UPDATE, DELETE
--   * Cross-context lookups       : SELECT only (no writes outside ctx)
--   * audit_logs                  : SELECT, INSERT only (append-only;
--                                   triggers also block UPDATE/DELETE)
--   * Reference tables (countries, states, cities, payment_methods,
--     document_types) are SELECT-only for almost every service.
--
-- IMPORTANT: Replace every 'CHANGE_ME_*' password before running this
-- in any non-throwaway environment. For dev you can keep the defaults,
-- but rotate them before staging/prod and load from a secret manager.
--
-- The 11 users created here:
--   iam_user, property_user, asset_user, leasing_user, tenant_user,
--   accounting_user, maintenance_user, notifications_user,
--   analytics_user, compliance_user, reference_user
-- =====================================================================

USE realestate3601;

-- =====================================================================
-- 0. CLEAN SLATE  (idempotent re-runs)
-- =====================================================================

DROP USER IF EXISTS 'iam_user'@'%';
DROP USER IF EXISTS 'property_user'@'%';
DROP USER IF EXISTS 'asset_user'@'%';
DROP USER IF EXISTS 'leasing_user'@'%';
DROP USER IF EXISTS 'tenant_user'@'%';
DROP USER IF EXISTS 'accounting_user'@'%';
DROP USER IF EXISTS 'maintenance_user'@'%';
DROP USER IF EXISTS 'notifications_user'@'%';
DROP USER IF EXISTS 'analytics_user'@'%';
DROP USER IF EXISTS 'reporting_user'@'%';
DROP USER IF EXISTS 'compliance_user'@'%';
DROP USER IF EXISTS 'reference_user'@'%';

-- =====================================================================
-- 1. CREATE USERS  (replace passwords before any non-dev environment)
-- =====================================================================

CREATE USER 'iam_user'@'%'           IDENTIFIED BY 'CHANGE_ME_iam_pwd';
CREATE USER 'property_user'@'%'      IDENTIFIED BY 'CHANGE_ME_property_pwd';
CREATE USER 'asset_user'@'%'         IDENTIFIED BY 'asset_pass';
CREATE USER 'leasing_user'@'%'       IDENTIFIED BY 'CHANGE_ME_leasing_pwd';
CREATE USER 'tenant_user'@'%'        IDENTIFIED BY 'CHANGE_ME_tenant_pwd';
CREATE USER 'accounting_user'@'%'    IDENTIFIED BY 'CHANGE_ME_accounting_pwd';
CREATE USER 'maintenance_user'@'%'   IDENTIFIED BY 'CHANGE_ME_maintenance_pwd';
CREATE USER 'notifications_user'@'%' IDENTIFIED BY 'CHANGE_ME_notifications_pwd';
CREATE USER 'analytics_user'@'%'     IDENTIFIED BY 'CHANGE_ME_analytics_pwd';
CREATE USER 'reporting_user'@'%'     IDENTIFIED BY 'reporting_pass';
CREATE USER 'compliance_user'@'%'    IDENTIFIED BY 'CHANGE_ME_compliance_pwd';
CREATE USER 'reference_user'@'%'     IDENTIFIED BY 'CHANGE_ME_reference_pwd';

-- =====================================================================
-- 2. IAM CONTEXT
--    Owns: users, roles, user_roles, audit_logs
--    audit_logs is append-only (INSERT + SELECT only; triggers also
--    enforce this at row level)
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.users      TO 'iam_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.roles      TO 'iam_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.user_roles TO 'iam_user'@'%';
GRANT SELECT, INSERT                 ON realestate3601.audit_logs TO 'iam_user'@'%';

-- =====================================================================
-- 3. PROPERTY CONTEXT
--    Owns: properties, units, amenities, property_photos, floor_plans,
--          unit_holds, unit_availability_calendar
--    Note: assets, asset_documents, space_utilization_records moved
--    to the asset bounded context (see section 3a). property-service no
--    longer touches those tables.
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.properties                 TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.units                      TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.amenities                  TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.property_photos            TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.floor_plans                TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.unit_holds                 TO 'property_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.unit_availability_calendar TO 'property_user'@'%';

-- Cross-context read-only (resolve owner_user_id, uploaded_by, etc.)
GRANT SELECT ON realestate3601.users          TO 'property_user'@'%';
-- Reference lookups
GRANT SELECT ON realestate3601.countries      TO 'property_user'@'%';
GRANT SELECT ON realestate3601.states         TO 'property_user'@'%';
GRANT SELECT ON realestate3601.cities         TO 'property_user'@'%';
GRANT SELECT ON realestate3601.document_types TO 'property_user'@'%';

-- =====================================================================
-- 3a. ASSET CONTEXT
--      Owns: assets, asset_documents, maintenance_plans,
--            asset_service_history, space_utilization_records
--      Used by asset-service (port 8088).
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.assets                     TO 'asset_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.asset_documents            TO 'asset_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.maintenance_plans          TO 'asset_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.asset_service_history      TO 'asset_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.space_utilization_records  TO 'asset_user'@'%';

-- Cross-context read-only: validate that a propertyId in a request body
-- actually references a real property, and resolve user-id columns for
-- audit/UX purposes.
GRANT SELECT ON realestate3601.properties     TO 'asset_user'@'%';
GRANT SELECT ON realestate3601.units          TO 'asset_user'@'%';
GRANT SELECT ON realestate3601.users          TO 'asset_user'@'%';
GRANT SELECT ON realestate3601.document_types TO 'asset_user'@'%';

-- =====================================================================
-- 4. LEASING CONTEXT
--    Owns: listings, applications, application_documents,
--          screening_rules, screening_scores,
--          leases, lease_terms, lease_documents, lease_workflow_events
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.listings               TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.applications           TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.application_documents  TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.screening_rules        TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.screening_scores       TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.leases                 TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.lease_terms            TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.lease_documents           TO 'leasing_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.lease_workflow_events   TO 'leasing_user'@'%';

-- Cross-context read-only
GRANT SELECT ON realestate3601.units           TO 'leasing_user'@'%';
GRANT SELECT ON realestate3601.tenant_profiles TO 'leasing_user'@'%';
GRANT SELECT ON realestate3601.users           TO 'leasing_user'@'%';
GRANT SELECT ON realestate3601.document_types  TO 'leasing_user'@'%';

-- =====================================================================
-- 5. TENANT CONTEXT
--    Owns: tenant_profiles
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.tenant_profiles TO 'tenant_user'@'%';

-- Cross-context read-only
GRANT SELECT ON realestate3601.users TO 'tenant_user'@'%';

-- =====================================================================
-- 6. ACCOUNTING CONTEXT
--    Owns: accounts, invoices, invoice_lines, receipts, ledger_entries,
--          deposits, charge_adjustments, arrears_snapshots
--    Note: payment_methods is reference data; accounting can SELECT it.
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.accounts            TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.invoices            TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.invoice_lines       TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.receipts            TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.ledger_entries      TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.deposits            TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.charge_adjustments  TO 'accounting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.arrears_snapshots   TO 'accounting_user'@'%';
GRANT SELECT                         ON realestate3601.payment_methods     TO 'accounting_user'@'%';

-- Cross-context read-only
GRANT SELECT ON realestate3601.leases          TO 'accounting_user'@'%';
GRANT SELECT ON realestate3601.tenant_profiles TO 'accounting_user'@'%';
GRANT SELECT ON realestate3601.users           TO 'accounting_user'@'%';

-- =====================================================================
-- 7. MAINTENANCE CONTEXT
--    Owns: work_orders, maintenance_schedules, part_inventory,
--          work_order_attachments, maintenance_logs,
--          vendors, vendor_assignments, part_reservations
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.work_orders            TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.maintenance_schedules  TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.part_inventory         TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.work_order_attachments TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.maintenance_logs       TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.vendors                TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.vendor_assignments     TO 'maintenance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.part_reservations      TO 'maintenance_user'@'%';

-- Cross-context read-only
GRANT SELECT ON realestate3601.units              TO 'maintenance_user'@'%';
GRANT SELECT ON realestate3601.properties         TO 'maintenance_user'@'%';
GRANT SELECT ON realestate3601.assets             TO 'maintenance_user'@'%';
GRANT SELECT ON realestate3601.maintenance_plans  TO 'maintenance_user'@'%';
GRANT SELECT ON realestate3601.users              TO 'maintenance_user'@'%';
-- Needed by the notification dispatcher to resolve tenant_id -> user_id
-- when maintenance-service publishes "work order scheduled/completed"
-- notifications to the tenant.
GRANT SELECT ON realestate3601.tenant_profiles    TO 'maintenance_user'@'%';

-- =====================================================================
-- 8. NOTIFICATIONS CONTEXT
--    Owns: notifications, alert_rules
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.notifications TO 'notifications_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.alert_rules   TO 'notifications_user'@'%';

-- Cross-context read-only (recipient lookup)
GRANT SELECT ON realestate3601.users TO 'notifications_user'@'%';

-- =====================================================================
-- 9. ANALYTICS CONTEXT
--    Owns: kpi_reports, analytics_datasets
--    Special case: analytics naturally needs to read from many
--    contexts to compute KPIs, so it gets broad SELECT but writes
--    only to its own tables.
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.kpi_reports        TO 'analytics_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.analytics_datasets TO 'analytics_user'@'%';

-- Read-only across the whole DB for reporting/aggregation
GRANT SELECT ON realestate3601.* TO 'analytics_user'@'%';

-- =====================================================================
-- 9b. REPORTING CONTEXT
--    Owns: kpi_reports, analytics_datasets, report_jobs, report_exports
--    Distinct from analytics_user: reporting-service is the active
--    write-owner of the reporting tables (analytics_user is kept for
--    read-only ad-hoc analytical queries elsewhere).
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.kpi_reports        TO 'reporting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.analytics_datasets TO 'reporting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.report_jobs        TO 'reporting_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.report_exports     TO 'reporting_user'@'%';

-- Cross-context lookup for generated_by / created_by joins
GRANT SELECT ON realestate3601.users TO 'reporting_user'@'%';

-- =====================================================================
-- 10. COMPLIANCE CONTEXT
--    Owns: compliance_reports, retention_policies
--    Reads audit_logs and other tables to assemble evidence packages.
--    NOTE: audit_logs gets INSERT (other services POST audit events to
--    compliance-service which writes the row) but NEVER UPDATE/DELETE -
--    this is the AC4 enforcement layer, on top of the schema triggers.
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.compliance_reports TO 'compliance_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.retention_policies TO 'compliance_user'@'%';

-- Append-only access to audit_logs (AC4: no UPDATE, no DELETE)
GRANT SELECT, INSERT ON realestate3601.audit_logs TO 'compliance_user'@'%';

-- Read-only access to evidence sources (cross-context - no writes)
GRANT SELECT ON realestate3601.users                  TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.leases                 TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.lease_workflow_events  TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.invoices               TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.receipts               TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.work_orders            TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.maintenance_logs       TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.work_order_attachments TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.properties             TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.assets                 TO 'compliance_user'@'%';
GRANT SELECT ON realestate3601.asset_service_history  TO 'compliance_user'@'%';

-- Belt-and-suspenders: explicitly revoke UPDATE/DELETE on audit_logs in
-- case the user already exists with broader grants from a previous run.
REVOKE UPDATE, DELETE ON realestate3601.audit_logs FROM 'compliance_user'@'%';

-- =====================================================================
-- 11. REFERENCE CONTEXT
--    Owns: countries, states, cities, payment_methods, document_types
--    Used by an admin/back-office service to manage lookup data.
-- =====================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.countries       TO 'reference_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.states          TO 'reference_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.cities          TO 'reference_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.payment_methods TO 'reference_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.document_types  TO 'reference_user'@'%';

-- =====================================================================
-- APPLY
-- =====================================================================

FLUSH PRIVILEGES;

-- =====================================================================
-- VERIFICATION SNIPPETS  (run these manually to confirm isolation)
-- =====================================================================
-- 1) Connect as a context user:
--      mysql -u tenant_user -p realestate3601
--
-- 2) Confirm own table works:
--      SELECT COUNT(*) FROM tenant_profiles;        -- should succeed
--
-- 3) Confirm a foreign-context table is blocked:
--      SELECT COUNT(*) FROM leases;                 -- should fail
--      ERROR 1142 (42000): SELECT command denied to user
--      'tenant_user'@'%' for table 'leases'
--
-- 4) Confirm cross-context read-only works (where granted):
--      -- as leasing_user:
--      SELECT COUNT(*) FROM units;                  -- should succeed
--      INSERT INTO units (...) VALUES (...);        -- should fail
--
-- 5) Inspect granted privileges for a user:
--      SHOW GRANTS FOR 'tenant_user'@'%';
-- =====================================================================
-- END OF USERS FILE
-- =====================================================================