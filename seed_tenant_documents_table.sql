-- =====================================================================
-- seed_tenant_documents_table.sql
-- Idempotent migration: adds tenant_documents table + grants for the
-- tenant-portal "My Documents" upload flow. Safe to re-run.
--
-- Apply with:
--   mysql -u root -p realestate3601 < seed_tenant_documents_table.sql
-- =====================================================================

USE realestate3601;

CREATE TABLE IF NOT EXISTS tenant_documents (
    doc_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- Soft FK -> tenant_profiles.tenant_id (owned by tenant context)
    tenant_id       BIGINT UNSIGNED NOT NULL,
    file_name       VARCHAR(255)    NOT NULL,
    mime_type       VARCHAR(120)    NOT NULL,
    file_size_bytes BIGINT UNSIGNED NOT NULL,
    file_data       LONGBLOB        NOT NULL,
    caption         VARCHAR(500)        NULL,
    uploaded_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (doc_id),
    KEY ix_tenant_documents_tenant (tenant_id),
    CONSTRAINT fk_tenant_documents_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenant_profiles (tenant_id)
) ENGINE=InnoDB;

-- Optional lease / application links so tenants can attach an uploaded
-- document to a specific lease or application. Soft FKs across bounded
-- contexts — no constraint, the leasing-service owns those tables.
-- MySQL 8 does not support `IF NOT EXISTS` on ADD COLUMN / CREATE INDEX, so
-- we guard each step against INFORMATION_SCHEMA to stay idempotent.

SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND COLUMN_NAME = 'linked_lease_id');
SET @sql := IF(@c = 0,
    'ALTER TABLE tenant_documents ADD COLUMN linked_lease_id BIGINT UNSIGNED NULL',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND COLUMN_NAME = 'linked_application_id');
SET @sql := IF(@c = 0,
    'ALTER TABLE tenant_documents ADD COLUMN linked_application_id BIGINT UNSIGNED NULL',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @i := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND INDEX_NAME = 'ix_tenant_documents_lease');
SET @sql := IF(@i = 0,
    'CREATE INDEX ix_tenant_documents_lease ON tenant_documents (linked_lease_id)',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @i := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND INDEX_NAME = 'ix_tenant_documents_application');
SET @sql := IF(@i = 0,
    'CREATE INDEX ix_tenant_documents_application ON tenant_documents (linked_application_id)',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Initial release stored linked_*_id as BIGINT; the public leasing API
-- surfaces UUIDs instead. Coerce the column type when needed.
SET @t := (SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND COLUMN_NAME = 'linked_lease_id');
SET @sql := IF(@t = 'bigint',
    'ALTER TABLE tenant_documents MODIFY COLUMN linked_lease_id VARCHAR(36) NULL',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @t := (SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenant_documents'
             AND COLUMN_NAME = 'linked_application_id');
SET @sql := IF(@t = 'bigint',
    'ALTER TABLE tenant_documents MODIFY COLUMN linked_application_id VARCHAR(36) NULL',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Grants for the tenant-service DB user. CREATE USER may already exist;
-- GRANT is idempotent.
GRANT SELECT, INSERT, UPDATE, DELETE ON realestate3601.tenant_documents TO 'tenant_user'@'%';

FLUSH PRIVILEGES;
