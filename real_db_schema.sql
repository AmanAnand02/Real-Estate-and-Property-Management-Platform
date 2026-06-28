-- =====================================================================
-- Project      : RealEstate360 - Property Management & Real Estate Ops
-- File         : realestate360_schema.sql
-- Purpose      : Schema only (DDL + lookup seed data).
--                Run AS THE ROOT/ADMIN MySQL user.
--                After this completes, run realestate360_users.sql to
--                create the per-bounded-context database users.
-- DBMS         : MySQL 8.0+
-- Engine       : InnoDB
-- Charset      : utf8mb4
-- Scope        : 51 tables, Phase 0 compliant, split-ready
--
-- Run order
--   1. realestate360_schema.sql   (this file - tables, triggers, seeds)
--   2. realestate360_users.sql    (per-context users + GRANTs)
--
-- Phase 0 alignment summary
--   * BIGINT UNSIGNED for all internal PKs/FKs (id columns)
--   * CHAR(36) UUID for all public identifiers (*_uuid columns)
--   * DECIMAL(19,4) for all monetary columns
--   * DATETIME (UTC) for all timestamps; created_at/updated_at on every
--     transactional table
--   * Foreign-key constraints exist ONLY within a bounded context.
--     Cross-context references store the id but DO NOT declare an FK,
--     so each bounded context can be lifted into its own database with
--     zero refactoring (the "schema-per-service tomorrow" rule).
--   * Indexes added on every cross-context id column to compensate for
--     the dropped FK indexes and to support high-frequency filters.
--   * audit_logs is append-only; UPDATE/DELETE blocked by triggers.
--   * Soft deletes via status enums (no DELETEs from transactional rows).
--
-- Bounded contexts (future microservices)
--   iam            users, roles, user_roles, audit_logs
--   property       properties, units, amenities, property_photos,
--                  floor_plans,
--                  unit_holds, unit_availability_calendar
--   asset          assets, asset_documents, maintenance_plans,
--                  asset_service_history, space_utilization_records
--   leasing        listings, applications, application_documents,
--                  leases, lease_terms, lease_documents,
--                  screening_rules, screening_scores,
--                  lease_workflow_events
--   tenant         tenant_profiles
--   maintenance    work_orders, maintenance_schedules, part_inventory,
--                  work_order_attachments, maintenance_logs,
--                  vendors, vendor_assignments, part_reservations
--   accounting     accounts, invoices, invoice_lines, receipts, ledger_entries,
--                  deposits, charge_adjustments, arrears_snapshots,
--                  payment_methods
--   notifications  notifications, alert_rules
--   analytics      kpi_reports, analytics_datasets
--   compliance     compliance_reports, retention_policies
--   reference      countries, states, cities, document_types
-- =====================================================================

DROP DATABASE IF EXISTS realestate3601;
CREATE DATABASE realestate3601
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE realestate3601;

-- =====================================================================
-- 1. GEOGRAPHY LOOKUPS  (reference context)
-- =====================================================================

CREATE TABLE countries (
    country_code   CHAR(2)             NOT NULL,
    name           VARCHAR(100)        NOT NULL,
    PRIMARY KEY (country_code),
    UNIQUE KEY uk_countries_name (name)
) ENGINE=InnoDB;

CREATE TABLE states (
    state_id       INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    country_code   CHAR(2)             NOT NULL,
    state_code     VARCHAR(10)         NOT NULL,
    name           VARCHAR(100)        NOT NULL,
    PRIMARY KEY (state_id),
    UNIQUE KEY uk_states_country_code (country_code, state_code),
    CONSTRAINT fk_states_country
      FOREIGN KEY (country_code) REFERENCES countries(country_code)
      ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE cities (
    city_id        INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    state_id       INT UNSIGNED        NOT NULL,
    name           VARCHAR(100)        NOT NULL,
    PRIMARY KEY (city_id),
    UNIQUE KEY uk_cities_state_name (state_id, name),
    CONSTRAINT fk_cities_state
      FOREIGN KEY (state_id) REFERENCES states(state_id)
      ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- =====================================================================
-- 2. REFERENCE LOOKUPS
-- =====================================================================

CREATE TABLE payment_methods (
    method_id      INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    name           VARCHAR(50)         NOT NULL,
    description    VARCHAR(255)            NULL,
    is_active      TINYINT(1)          NOT NULL DEFAULT 1,
    PRIMARY KEY (method_id),
    UNIQUE KEY uk_payment_methods_name (name)
) ENGINE=InnoDB;

CREATE TABLE document_types (
    doc_type_id    INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    name           VARCHAR(100)        NOT NULL,
    description    VARCHAR(255)            NULL,
    PRIMARY KEY (doc_type_id),
    UNIQUE KEY uk_document_types_name (name)
) ENGINE=InnoDB;

-- =====================================================================
-- 3. IDENTITY & ACCESS  (iam bounded context)
-- =====================================================================

CREATE TABLE roles (
    role_id          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    name             VARCHAR(50)       NOT NULL,
    description      VARCHAR(255)          NULL,
    permissions_json JSON                  NULL,
    PRIMARY KEY (role_id),
    UNIQUE KEY uk_roles_name (name)
) ENGINE=InnoDB;

CREATE TABLE users (
    user_id        BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    -- Public identifier: BIGINT internal PK + UUID public identifier
    -- (per IAM contract). uuid is generated by iam-service in @PrePersist.
    uuid           CHAR(36)            NOT NULL,
    full_name      VARCHAR(150)        NOT NULL,
    email          VARCHAR(255)        NOT NULL,
    phone          VARCHAR(30)             NULL,
    password_hash  VARCHAR(255)        NOT NULL,
    status         ENUM('ACTIVE','SUSPENDED','LOCKED','DEACTIVATED') NOT NULL DEFAULT 'ACTIVE',
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uk_users_email (email),
    UNIQUE KEY uk_users_uuid  (uuid)
) ENGINE=InnoDB;

CREATE TABLE user_roles (
    user_id        BIGINT UNSIGNED     NOT NULL,
    role_id        INT UNSIGNED        NOT NULL,
    assigned_at    DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_roles_user
      FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role
      FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
    audit_id       BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    user_id        BIGINT UNSIGNED         NULL,
    action         VARCHAR(100)        NOT NULL,
    resource_type  VARCHAR(100)        NOT NULL,
    resource_id    VARCHAR(100)            NULL,
    details        TEXT                    NULL,
    ts             DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id),
    KEY ix_audit_user_time  (user_id, ts),
    KEY ix_audit_resource   (resource_type, resource_id),
    CONSTRAINT fk_audit_logs_user
      FOREIGN KEY (user_id) REFERENCES users(user_id)
      ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- Append-only enforcement: block UPDATE and DELETE on audit_logs
DELIMITER $$
CREATE TRIGGER trg_audit_logs_no_update
BEFORE UPDATE ON audit_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'audit_logs is append-only: UPDATE not allowed';
END$$

CREATE TRIGGER trg_audit_logs_no_delete
BEFORE DELETE ON audit_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'audit_logs is append-only: DELETE not allowed';
END$$
DELIMITER ;

-- =====================================================================
-- 4. PROPERTY & UNIT  (property bounded context)
-- =====================================================================

CREATE TABLE properties (
    property_id    BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    property_uuid  CHAR(36)            NOT NULL,
    name           VARCHAR(200)        NOT NULL,
    address_line1  VARCHAR(200)        NOT NULL,
    address_line2  VARCHAR(200)            NULL,
    city_id        INT UNSIGNED        NOT NULL,
    state_id       INT UNSIGNED        NOT NULL,
    country_code   CHAR(2)             NOT NULL,
    postal_code    VARCHAR(20)             NULL,
    -- Cross-context: references iam.users; soft FK only
    owner_user_id  BIGINT UNSIGNED     NOT NULL,
    status         ENUM('ACTIVE','INACTIVE','UNDER_CONSTRUCTION','SOLD') NOT NULL DEFAULT 'ACTIVE',
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (property_id),
    UNIQUE KEY uk_properties_uuid (property_uuid),
    KEY ix_properties_owner  (owner_user_id),
    KEY ix_properties_status (status),
    CONSTRAINT fk_properties_city
      FOREIGN KEY (city_id)      REFERENCES cities(city_id),
    CONSTRAINT fk_properties_state
      FOREIGN KEY (state_id)     REFERENCES states(state_id),
    CONSTRAINT fk_properties_country
      FOREIGN KEY (country_code) REFERENCES countries(country_code)
) ENGINE=InnoDB;

CREATE TABLE units (
    unit_id        BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    unit_uuid      CHAR(36)            NOT NULL,
    property_id    BIGINT UNSIGNED     NOT NULL,
    unit_number    VARCHAR(30)         NOT NULL,
    type           VARCHAR(50)         NOT NULL,
    area_sqft      DECIMAL(10,2)           NULL,
    bedrooms       SMALLINT UNSIGNED       NULL,
    bathrooms      SMALLINT UNSIGNED       NULL,
    floor          SMALLINT                NULL,
    status         ENUM('AVAILABLE','HELD','LEASED','UNDER_MAINTENANCE','DECOMMISSIONED') NOT NULL DEFAULT 'AVAILABLE',
    rent_amount    DECIMAL(19,4)       NOT NULL DEFAULT 0,
    deposit_amount DECIMAL(19,4)       NOT NULL DEFAULT 0,
    available_from DATE                    NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (unit_id),
    UNIQUE KEY uk_units_uuid (unit_uuid),
    UNIQUE KEY uk_units_property_number (property_id, unit_number),
    KEY ix_units_status (status),
    CONSTRAINT fk_units_property
      FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE amenities (
    amenity_id     INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    property_id    BIGINT UNSIGNED     NOT NULL,
    name           VARCHAR(100)        NOT NULL,
    description    VARCHAR(255)            NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (amenity_id),
    UNIQUE KEY uk_amenities_property_name (property_id, name),
    CONSTRAINT fk_amenities_property
      FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE property_photos (
    photo_id        BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    property_id     BIGINT UNSIGNED    NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    mime_type       VARCHAR(100)       NOT NULL,
    file_size_bytes BIGINT UNSIGNED    NOT NULL,
    -- file_data is legacy: new uploads go via StorageService and populate
    -- file_ref instead. Existing rows keep working via the LONGBLOB path.
    file_data       LONGBLOB               NULL,
    file_ref        VARCHAR(512)           NULL,
    caption         VARCHAR(255)           NULL,
    -- Cross-context: references iam.users; soft FK only
    uploaded_by     BIGINT UNSIGNED    NOT NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (photo_id),
    KEY ix_property_photos_uploader (uploaded_by),
    CONSTRAINT fk_property_photos_property
      FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE floor_plans (
    floor_plan_id   BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    property_id     BIGINT UNSIGNED    NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    mime_type       VARCHAR(100)       NOT NULL,
    file_size_bytes BIGINT UNSIGNED    NOT NULL,
    -- file_data is legacy: new uploads go via StorageService and populate
    -- file_ref instead. Existing rows keep working via the LONGBLOB path.
    file_data       LONGBLOB               NULL,
    file_ref        VARCHAR(512)           NULL,
    description     VARCHAR(255)           NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (floor_plan_id),
    CONSTRAINT fk_floor_plans_property
      FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
-- 5. ASSETS & SPACE  (asset bounded context)
-- =====================================================================
-- These tables are owned by asset-service. They live in the same physical
-- database for Phase 0 but use only soft FKs to property/iam, so the
-- asset context can be split into its own DB tomorrow without refactoring.

CREATE TABLE assets (
    asset_id            BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    asset_uuid          CHAR(36)           NOT NULL,
    -- Cross-context: references property.properties; soft FK only
    property_id         BIGINT UNSIGNED    NOT NULL,
    name                VARCHAR(150)       NOT NULL,
    type                VARCHAR(50)        NOT NULL,
    serial_number       VARCHAR(100)           NULL,
    manufacturer        VARCHAR(150)           NULL,
    model               VARCHAR(150)           NULL,
    purchase_date       DATE                   NULL,
    install_date        DATE                   NULL,
    warranty_start_date DATE                   NULL,
    warranty_expiry     DATE                   NULL,
    location            VARCHAR(200)           NULL,
    -- Cross-context: typically references property.units; soft FK only
    space_id            BIGINT UNSIGNED        NULL,
    status              VARCHAR(32)        NOT NULL DEFAULT 'OPERATIONAL',
    cost                DECIMAL(19,4)          NULL,
    notes               TEXT                   NULL,
    created_at          DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- Cross-context: references iam.users; soft FK only
    created_by          BIGINT UNSIGNED        NULL,
    -- Cross-context: references iam.users; soft FK only
    updated_by          BIGINT UNSIGNED        NULL,
    -- Optimistic locking column populated by JPA's @Version
    version             BIGINT UNSIGNED    NOT NULL DEFAULT 0,
    PRIMARY KEY (asset_id),
    UNIQUE KEY uk_assets_uuid (asset_uuid),
    -- Enforces the AC: duplicate serial within a property -> 409. NULL
    -- serial numbers are excluded from uniqueness checks per SQL semantics,
    -- so assets without serial numbers don't conflict with each other.
    UNIQUE KEY uk_assets_property_serial (property_id, serial_number),
    KEY ix_assets_property (property_id),
    KEY ix_assets_status   (status),
    KEY ix_assets_space    (space_id)
) ENGINE=InnoDB;

CREATE TABLE asset_documents (
    doc_id          BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    document_uuid   CHAR(36)           NOT NULL,
    -- Same-context FK -> assets.asset_id
    asset_id        BIGINT UNSIGNED    NOT NULL,
    -- Free-form: WARRANTY, INSPECTION_REPORT, MANUAL, etc. Not an FK so
    -- the service stays independent of the (reference) document_types table.
    document_type   VARCHAR(64)        NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    -- Object-store reference (e.g. "s3://asset-docs/2026/uuid.pdf").
    -- This table stores metadata only; file bytes live in object storage.
    file_ref        VARCHAR(512)       NOT NULL,
    content_type    VARCHAR(128)           NULL,
    file_size       BIGINT UNSIGNED        NULL,
    description     VARCHAR(1024)          NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Cross-context: references iam.users; soft FK only
    uploaded_by     BIGINT UNSIGNED        NULL,
    PRIMARY KEY (doc_id),
    UNIQUE KEY uk_asset_documents_uuid (document_uuid),
    KEY ix_asset_documents_asset (asset_id),
    CONSTRAINT fk_asset_docs_asset
      FOREIGN KEY (asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- maintenance_plans (asset bounded context)
-- Preventive maintenance plan templates ("Annual HVAC inspection every
-- 12 months"), owned by Facilities. Distinct from maintenance-service's
-- maintenance_schedules table which is the execution queue.
-- ---------------------------------------------------------------------
CREATE TABLE maintenance_plans (
    plan_id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    plan_uuid                  CHAR(36)        NOT NULL,
    -- Same-context FK -> assets.asset_id
    asset_id                   BIGINT UNSIGNED NOT NULL,
    name                       VARCHAR(200)    NOT NULL,
    description                TEXT                NULL,
    -- Free-form: MONTHLY, QUARTERLY, YEARLY, ...
    frequency                  VARCHAR(32)     NOT NULL,
    -- frequency_interval=3 + frequency=MONTHLY -> every 3 months
    frequency_interval         INT UNSIGNED    NOT NULL DEFAULT 1,
    next_due_date              DATE                NULL,
    last_performed_date        DATE                NULL,
    -- Cross-context: references iam.users; soft FK only
    assigned_to                BIGINT UNSIGNED     NULL,
    estimated_duration_minutes INT UNSIGNED        NULL,
    estimated_cost             DECIMAL(19,4)       NULL,
    status                     VARCHAR(32)     NOT NULL DEFAULT 'ACTIVE',
    created_at                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- Cross-context: references iam.users; soft FK only
    created_by                 BIGINT UNSIGNED     NULL,
    -- Cross-context: references iam.users; soft FK only
    updated_by                 BIGINT UNSIGNED     NULL,
    version                    BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (plan_id),
    UNIQUE KEY uk_maintenance_plans_uuid (plan_uuid),
    KEY ix_maintenance_plans_asset    (asset_id),
    KEY ix_maintenance_plans_due_date (next_due_date),
    CONSTRAINT fk_maint_plans_asset
      FOREIGN KEY (asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- asset_service_history (asset bounded context)
-- One row per service event performed on an asset (preventive or reactive).
-- Source of truth for asset service history; consumed by Compliance for
-- inspection-readiness reports.
-- ---------------------------------------------------------------------
CREATE TABLE asset_service_history (
    history_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    history_uuid      CHAR(36)        NOT NULL,
    -- Same-context FK -> assets.asset_id
    asset_id          BIGINT UNSIGNED NOT NULL,
    -- Same-context FK -> maintenance_plans.plan_id; nullable for ad-hoc events
    plan_id           BIGINT UNSIGNED     NULL,
    service_date      DATE            NOT NULL,
    service_type      VARCHAR(64)     NOT NULL,
    -- Free-form: technician name, vendor name, etc.
    performed_by      VARCHAR(200)        NULL,
    cost              DECIMAL(19,4)       NULL,
    description       TEXT                NULL,
    -- Free-form: RESOLVED, PENDING, ESCALATED, ...
    outcome           VARCHAR(64)         NULL,
    next_service_date DATE                NULL,
    -- Reference to a doc in asset_documents or object storage path
    document_ref      VARCHAR(512)        NULL,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Cross-context: references iam.users; soft FK only
    created_by        BIGINT UNSIGNED     NULL,
    PRIMARY KEY (history_id),
    UNIQUE KEY uk_asset_history_uuid (history_uuid),
    KEY ix_asset_history_asset      (asset_id, service_date),
    KEY ix_asset_history_plan       (plan_id),
    CONSTRAINT fk_asset_history_asset
      FOREIGN KEY (asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    CONSTRAINT fk_asset_history_plan
      FOREIGN KEY (plan_id)  REFERENCES maintenance_plans(plan_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- space_utilization_records (asset bounded context)
-- Tracks utilization data points per space/property/date. Extended from
-- the original simple "occupancy_percent only" shape to support occupancy
-- count / capacity / duration / purpose, per asset-service contract.
-- ---------------------------------------------------------------------
CREATE TABLE space_utilization_records (
    record_id         BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    record_uuid       CHAR(36)         NOT NULL,
    -- Cross-context: typically references property.units; soft FK only.
    -- Nullable when measuring utilization at the property (building) level.
    space_id          BIGINT UNSIGNED      NULL,
    -- Cross-context: references property.properties; soft FK only
    property_id       BIGINT UNSIGNED  NOT NULL,
    record_date       DATE             NOT NULL,
    occupancy_count   INT UNSIGNED         NULL,
    capacity          INT UNSIGNED         NULL,
    occupancy_percent DECIMAL(5,2)         NULL,
    duration_minutes  INT UNSIGNED         NULL,
    purpose           VARCHAR(150)         NULL,
    -- Cross-context: references iam.users; soft FK only
    recorded_by       BIGINT UNSIGNED      NULL,
    notes             VARCHAR(255)         NULL,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (record_id),
    UNIQUE KEY uk_sur_uuid (record_uuid),
    -- Allow multiple rows per (property, date) when space_id differs; the
    -- uniqueness is on the full triple. NULL space_id rows compare unequal
    -- under SQL semantics, so multiple property-level snapshots are allowed.
    UNIQUE KEY uk_sur_space_property_date (space_id, property_id, record_date),
    KEY ix_sur_property_date (property_id, record_date),
    KEY ix_sur_space         (space_id),
    CONSTRAINT fk_sur_property
      FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    CONSTRAINT ck_sur_percent CHECK (occupancy_percent IS NULL OR occupancy_percent BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- =====================================================================
-- 6. UNIT HOLDS & AVAILABILITY  (property bounded context)
-- =====================================================================

CREATE TABLE unit_holds (
    hold_id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    hold_uuid            CHAR(36)        NOT NULL,
    unit_id              BIGINT UNSIGNED NOT NULL,
    -- Cross-context: references iam.users; soft FK only
    held_by_user_id      BIGINT UNSIGNED NOT NULL,
    hold_reason          VARCHAR(500)        NULL,
    hold_start_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hold_end_at          DATETIME        NOT NULL,
    status               ENUM('ACTIVE','RELEASED','EXPIRED','CONVERTED') NOT NULL DEFAULT 'ACTIVE',
    released_at          DATETIME            NULL,
    -- Cross-context: references iam.users; soft FK only
    released_by_user_id  BIGINT UNSIGNED     NULL,
    release_notes        VARCHAR(500)        NULL,
    created_at           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (hold_id),
    UNIQUE KEY uk_unit_holds_uuid (hold_uuid),
    KEY ix_unit_holds_unit         (unit_id),
    KEY ix_unit_holds_status       (status),
    KEY ix_unit_holds_held_by      (held_by_user_id),
    KEY ix_unit_holds_released_by  (released_by_user_id),
    KEY ix_unit_holds_unit_status  (unit_id, status),
    KEY ix_unit_holds_end_at       (hold_end_at),
    CONSTRAINT fk_unit_holds_unit
      FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE,
    CONSTRAINT ck_unit_holds_window CHECK (hold_end_at > hold_start_at)
) ENGINE=InnoDB;

CREATE TABLE unit_availability_calendar (
    calendar_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    unit_id               BIGINT UNSIGNED NOT NULL,
    calendar_date         DATE            NOT NULL,
    availability_status   ENUM('AVAILABLE','UNAVAILABLE','BLOCKED','HELD','LEASED') NOT NULL DEFAULT 'AVAILABLE',
    notes                 VARCHAR(255)        NULL,
    created_at            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (calendar_id),
    UNIQUE KEY uk_uac_unit_date (unit_id, calendar_date),
    KEY ix_uac_date        (calendar_date),
    KEY ix_uac_status_date (availability_status, calendar_date),
    CONSTRAINT fk_uac_unit
      FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
-- 7. TENANT  (tenant bounded context)
-- =====================================================================

CREATE TABLE tenant_profiles (
    tenant_id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- Cross-context: references iam.users; soft FK only
    user_id                 BIGINT UNSIGNED NOT NULL,
    preferred_contact       ENUM('EMAIL','PHONE','IN_APP') NOT NULL DEFAULT 'EMAIL',
    emergency_contact_name  VARCHAR(150)        NULL,
    emergency_contact_phone VARCHAR(30)         NULL,
    documents_vault_ref     VARCHAR(255)        NULL,
    status                  ENUM('PROSPECT','ACTIVE','PAST','BLACKLISTED') NOT NULL DEFAULT 'PROSPECT',
    created_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id),
    UNIQUE KEY uk_tenant_profiles_user (user_id)
) ENGINE=InnoDB;

-- =====================================================================
-- 8. LISTING, APPLICATION, LEASE  (leasing bounded context)
-- =====================================================================

CREATE TABLE listings (
    listing_id     BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    listing_uuid   CHAR(36)            NOT NULL,
    -- Cross-context: references property.units; soft FK only
    unit_id        BIGINT UNSIGNED     NOT NULL,
    title          VARCHAR(200)        NOT NULL,
    description    TEXT                    NULL,
    price          DECIMAL(19,4)       NOT NULL,
    available_from DATE                    NULL,
    status         ENUM('DRAFT','PUBLISHED','PAUSED','CLOSED','EXPIRED') NOT NULL DEFAULT 'DRAFT',
    -- Cross-context: references iam.users; soft FK only
    created_by     BIGINT UNSIGNED     NOT NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    expires_at     DATETIME                NULL,
    PRIMARY KEY (listing_id),
    UNIQUE KEY uk_listings_uuid (listing_uuid),
    KEY ix_listings_unit    (unit_id),
    KEY ix_listings_creator (created_by),
    KEY ix_listings_status  (status)
) ENGINE=InnoDB;

CREATE TABLE applications (
    application_id    BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    application_uuid  CHAR(36)         NOT NULL,
    listing_id        BIGINT UNSIGNED  NOT NULL,
    -- Cross-context: references iam.users; soft FK only
    applicant_user_id BIGINT UNSIGNED  NOT NULL,
    submitted_at      DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status            ENUM('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','WITHDRAWN') NOT NULL DEFAULT 'SUBMITTED',
    score             DECIMAL(6,2)         NULL,
    screening_notes   TEXT                 NULL,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (application_id),
    UNIQUE KEY uk_applications_uuid (application_uuid),
    UNIQUE KEY uk_applications_listing_applicant (listing_id, applicant_user_id),
    KEY ix_applications_applicant (applicant_user_id),
    CONSTRAINT fk_applications_listing
      FOREIGN KEY (listing_id) REFERENCES listings(listing_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE application_documents (
    doc_id          BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    application_id  BIGINT UNSIGNED    NOT NULL,
    doc_type_id     INT UNSIGNED       NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    mime_type       VARCHAR(100)       NOT NULL,
    file_size_bytes BIGINT UNSIGNED    NOT NULL,
    file_data       LONGBLOB           NOT NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (doc_id),
    CONSTRAINT fk_app_docs_application
      FOREIGN KEY (application_id) REFERENCES applications(application_id) ON DELETE CASCADE,
    CONSTRAINT fk_app_docs_type
      FOREIGN KEY (doc_type_id)    REFERENCES document_types(doc_type_id)
) ENGINE=InnoDB;

CREATE TABLE screening_rules (
    rule_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    rule_uuid      CHAR(36)        NOT NULL,
    name           VARCHAR(150)    NOT NULL,
    description    VARCHAR(500)        NULL,
    weight         DECIMAL(6,2)    NOT NULL DEFAULT 1.00,
    min_score      DECIMAL(6,2)    NOT NULL DEFAULT 0.00,
    max_score      DECIMAL(6,2)    NOT NULL DEFAULT 100.00,
    active         TINYINT(1)      NOT NULL DEFAULT 1,
    created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (rule_id),
    UNIQUE KEY uk_screening_rules_uuid (rule_uuid),
    UNIQUE KEY uk_screening_rules_name (name)
) ENGINE=InnoDB;

CREATE TABLE screening_scores (
    score_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    application_id  BIGINT UNSIGNED NOT NULL,
    rule_id         BIGINT UNSIGNED     NULL,
    rule_name       VARCHAR(150)    NOT NULL,
    raw_score       DECIMAL(6,2)    NOT NULL,
    weighted_score  DECIMAL(8,2)    NOT NULL,
    notes           VARCHAR(500)        NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (score_id),
    KEY ix_scoring_application (application_id),
    KEY ix_scoring_rule        (rule_id),
    CONSTRAINT fk_scoring_application
      FOREIGN KEY (application_id) REFERENCES applications(application_id) ON DELETE CASCADE,
    CONSTRAINT fk_scoring_rule
      FOREIGN KEY (rule_id) REFERENCES screening_rules(rule_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE leases (
    lease_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    lease_uuid         CHAR(36)        NOT NULL,
    -- Cross-context: references property.units; soft FK only
    unit_id            BIGINT UNSIGNED NOT NULL,
    -- Cross-context: references property.properties; soft FK only.
    -- Denormalized from unit_id at lease-creation time so consumers
    -- (billing, maintenance) don't need to call property-service to
    -- know which property the unit belongs to. Nullable to keep this
    -- column backward-compatible with older lease rows.
    property_id        BIGINT UNSIGNED     NULL,
    -- Cross-context: references tenant.tenant_profiles; soft FK only
    tenant_id          BIGINT UNSIGNED NOT NULL,
    -- Same-context: references leasing.applications (nullable; not all
    -- leases originate from an application). Soft FK to keep activation
    -- writes simple even if the row is set later.
    application_id     BIGINT UNSIGNED     NULL,
    start_date         DATE            NOT NULL,
    end_date           DATE            NOT NULL,
    rent_amount        DECIMAL(19,4)   NOT NULL,
    deposit_amount     DECIMAL(19,4)   NOT NULL,
    terms              TEXT                NULL,
    status             ENUM('DRAFT','ACTIVE','RENEWED','TERMINATED','EXPIRED') NOT NULL DEFAULT 'DRAFT',
    activated_at       DATETIME            NULL,
    -- Cross-context: references iam.users; soft FK only
    activated_by       BIGINT UNSIGNED     NULL,
    terminated_at      DATETIME            NULL,
    -- Cross-context: references iam.users; soft FK only
    terminated_by      BIGINT UNSIGNED     NULL,
    termination_reason VARCHAR(500)        NULL,
    created_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (lease_id),
    UNIQUE KEY uk_leases_uuid (lease_uuid),
    KEY ix_leases_unit_status     (unit_id, status),
    KEY ix_leases_tenant_status   (tenant_id, status),
    KEY ix_leases_application     (application_id),
    KEY ix_leases_property        (property_id),
    KEY ix_leases_activated_by    (activated_by),
    KEY ix_leases_terminated_by   (terminated_by),
    CONSTRAINT ck_leases_dates CHECK (end_date > start_date)
) ENGINE=InnoDB;

CREATE TABLE lease_terms (
    lease_term_id  BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    lease_id       BIGINT UNSIGNED     NOT NULL,
    term_name      VARCHAR(100)        NOT NULL,
    value          VARCHAR(500)        NOT NULL,
    effective_from DATE                NOT NULL,
    effective_to   DATE                    NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (lease_term_id),
    CONSTRAINT fk_lease_terms_lease
      FOREIGN KEY (lease_id) REFERENCES leases(lease_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE lease_documents (
    lease_doc_id    BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    lease_id        BIGINT UNSIGNED    NOT NULL,
    doc_type_id     INT UNSIGNED       NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    mime_type       VARCHAR(100)       NOT NULL,
    file_size_bytes BIGINT UNSIGNED    NOT NULL,
    file_data       LONGBLOB           NOT NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (lease_doc_id),
    CONSTRAINT fk_lease_docs_lease
      FOREIGN KEY (lease_id)    REFERENCES leases(lease_id) ON DELETE CASCADE,
    CONSTRAINT fk_lease_docs_type
      FOREIGN KEY (doc_type_id) REFERENCES document_types(doc_type_id)
) ENGINE=InnoDB;

CREATE TABLE lease_workflow_events (
    event_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    lease_id       BIGINT UNSIGNED NOT NULL,
    event_type     ENUM('CREATED','ACTIVATED','RENEWED','TERMINATED','EXPIRED','UPDATED') NOT NULL,
    from_status    VARCHAR(30)         NULL,
    to_status      VARCHAR(30)         NULL,
    -- Cross-context: references iam.users; soft FK only
    actor_user_id  BIGINT UNSIGNED     NULL,
    notes          VARCHAR(1000)       NULL,
    correlation_id VARCHAR(64)         NULL,
    occurred_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    KEY ix_lwe_lease (lease_id, occurred_at),
    KEY ix_lwe_actor (actor_user_id),
    CONSTRAINT fk_lwe_lease
      FOREIGN KEY (lease_id) REFERENCES leases(lease_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
-- 9. ACCOUNTING & BILLING  (accounting bounded context)
-- =====================================================================

-- ---------------------------------------------------------------------
-- accounts  (chart-of-accounts for double-entry-style ledger postings)
-- A small, stable set of accounts. Seeded in the SEED DATA block below.
-- ---------------------------------------------------------------------
CREATE TABLE accounts (
    account_id     INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    code           VARCHAR(30)         NOT NULL,
    name           VARCHAR(150)        NOT NULL,
    account_type   ENUM('ASSET','LIABILITY','REVENUE','EXPENSE','EQUITY') NOT NULL,
    description    VARCHAR(255)            NULL,
    PRIMARY KEY (account_id),
    UNIQUE KEY uk_accounts_code (code)
) ENGINE=InnoDB;

CREATE TABLE invoices (
    invoice_id     BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    -- Cross-context: tenant.tenant_profiles; soft FK
    tenant_id      BIGINT UNSIGNED     NOT NULL,
    -- Cross-context: leasing.leases; soft FK
    lease_id       BIGINT UNSIGNED     NOT NULL,
    period_start   DATE                NOT NULL,
    period_end     DATE                NOT NULL,
    amount_due     DECIMAL(19,4)       NOT NULL,
    due_date       DATE                NOT NULL,
    status         ENUM('DRAFT','ISSUED','PARTIALLY_PAID','PAID','OVERDUE','CANCELLED','VOIDED') NOT NULL DEFAULT 'DRAFT',
    -- Set when status -> VOIDED. Free-form admin note.
    void_reason    VARCHAR(500)            NULL,
    voided_at      DATETIME                NULL,
    issued_at      DATETIME                NULL,
    generated_at   DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (invoice_id),
    UNIQUE KEY uk_invoices_public_id (public_id),
    KEY ix_invoices_tenant       (tenant_id),
    KEY ix_invoices_lease_period (lease_id, period_start),
    KEY ix_invoices_status_due   (status, due_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- invoice_lines (optional itemization - one invoice can have many lines:
-- base rent, late fee, prorated month, utilities, etc.)
-- amount_due on invoices is the running total; the lines describe how.
-- ---------------------------------------------------------------------
CREATE TABLE invoice_lines (
    line_id        BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    invoice_id     BIGINT UNSIGNED     NOT NULL,
    description    VARCHAR(255)        NOT NULL,
    quantity       DECIMAL(10,2)       NOT NULL DEFAULT 1.00,
    unit_amount    DECIMAL(19,4)       NOT NULL,
    line_total     DECIMAL(19,4)       NOT NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (line_id),
    KEY ix_invoice_lines_invoice (invoice_id),
    CONSTRAINT fk_invoice_lines_invoice
      FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE receipts (
    receipt_id     BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    invoice_id     BIGINT UNSIGNED     NOT NULL,
    -- Cross-context: tenant.tenant_profiles; soft FK
    tenant_id      BIGINT UNSIGNED     NOT NULL,
    amount_paid    DECIMAL(19,4)       NOT NULL,
    paid_at        DATETIME            NOT NULL,
    method_id      INT UNSIGNED        NOT NULL,
    reference      VARCHAR(100)            NULL,
    status         ENUM('PENDING','COMPLETED','FAILED','REVERSED','REFUNDED') NOT NULL DEFAULT 'COMPLETED',
    -- Set when status -> REVERSED
    reversal_reason VARCHAR(500)           NULL,
    reversed_at     DATETIME               NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (receipt_id),
    UNIQUE KEY uk_receipts_public_id (public_id),
    KEY ix_receipts_tenant (tenant_id),
    CONSTRAINT fk_receipts_invoice
      FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id),
    CONSTRAINT fk_receipts_method
      FOREIGN KEY (method_id)  REFERENCES payment_methods(method_id)
) ENGINE=InnoDB;

CREATE TABLE ledger_entries (
    entry_id       BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    account_id     INT UNSIGNED        NOT NULL,
    entry_type     ENUM('DEBIT','CREDIT') NOT NULL,
    amount         DECIMAL(19,4)       NOT NULL,
    entry_date     DATE                NOT NULL,
    reference_type VARCHAR(50)             NULL,
    reference_id   BIGINT UNSIGNED         NULL,
    description    VARCHAR(255)            NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (entry_id),
    UNIQUE KEY uk_ledger_public_id (public_id),
    KEY ix_ledger_account_date (account_id, entry_date),
    KEY ix_ledger_reference    (reference_type, reference_id),
    CONSTRAINT fk_ledger_account
      FOREIGN KEY (account_id) REFERENCES accounts(account_id)
) ENGINE=InnoDB;

CREATE TABLE deposits (
    deposit_id     BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    -- Cross-context: leasing.leases; soft FK
    lease_id       BIGINT UNSIGNED     NOT NULL,
    -- Cross-context: tenant.tenant_profiles; soft FK
    tenant_id      BIGINT UNSIGNED     NOT NULL,
    amount         DECIMAL(19,4)       NOT NULL,
    -- Amount already refunded (allows partial refunds).
    refunded_amount DECIMAL(19,4)      NOT NULL DEFAULT 0,
    held_since     DATE                NOT NULL,
    status         ENUM('HELD','PARTIALLY_REFUNDED','REFUNDED','FORFEITED') NOT NULL DEFAULT 'HELD',
    refund_date    DATE                    NULL,
    -- Free-form reason captured on refund (deducting damages, etc.)
    refund_reason  VARCHAR(500)            NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (deposit_id),
    UNIQUE KEY uk_deposits_public_id (public_id),
    KEY ix_deposits_lease  (lease_id),
    KEY ix_deposits_tenant (tenant_id)
) ENGINE=InnoDB;

CREATE TABLE charge_adjustments (
    adjustment_id  BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    invoice_id     BIGINT UNSIGNED     NOT NULL,
    -- Signed: positive = additional charge, negative = credit/discount.
    amount         DECIMAL(19,4)       NOT NULL,
    reason         VARCHAR(255)        NOT NULL,
    -- Cross-context: iam.users; soft FK
    created_by     BIGINT UNSIGNED     NOT NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (adjustment_id),
    UNIQUE KEY uk_adjustments_public_id (public_id),
    KEY ix_adjustments_creator (created_by),
    CONSTRAINT fk_adjustments_invoice
      FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- arrears_snapshots (point-in-time totals of overdue amounts per tenant)
-- Generated by a billing-service job; useful for collections workflows.
-- ---------------------------------------------------------------------
CREATE TABLE arrears_snapshots (
    snapshot_id    BIGINT UNSIGNED     NOT NULL AUTO_INCREMENT,
    public_id      CHAR(36)            NOT NULL,
    -- Cross-context: tenant.tenant_profiles; soft FK
    tenant_id      BIGINT UNSIGNED     NOT NULL,
    snapshot_date  DATE                NOT NULL,
    total_overdue  DECIMAL(19,4)       NOT NULL,
    invoice_count  INT UNSIGNED        NOT NULL,
    oldest_due_date DATE                   NULL,
    created_at     DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (snapshot_id),
    UNIQUE KEY uk_arrears_public_id (public_id),
    UNIQUE KEY uk_arrears_tenant_date (tenant_id, snapshot_date),
    KEY ix_arrears_date (snapshot_date)
) ENGINE=InnoDB;

-- =====================================================================
-- 10. MAINTENANCE & WORK ORDERS  (maintenance bounded context)
-- =====================================================================

CREATE TABLE work_orders (
    work_order_id   BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    public_id       CHAR(36)           NOT NULL,
    source          ENUM('TENANT_REQUEST','PREVENTIVE','INSPECTION','MANUAL') NOT NULL,
    -- Cross-context: property.units; soft FK
    unit_id         BIGINT UNSIGNED        NULL,
    -- Cross-context: property.properties; soft FK.
    -- Nullable: a TENANT_REQUEST submitted without an active lease has no
    -- property to attach to; tenant-service forwards null in that case.
    property_id     BIGINT UNSIGNED        NULL,
    priority        ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM',
    category        VARCHAR(80)        NOT NULL,
    description     TEXT               NOT NULL,
    -- Cross-context: iam.users; soft FK
    assigned_to     BIGINT UNSIGNED        NULL,
    -- Cross-context: tenant.tenant_profiles; soft FK.
    -- Nullable: PREVENTIVE / INSPECTION / MANUAL sources have no tenant;
    -- only TENANT_REQUEST rows are required to carry one. Filtering this
    -- column is what enforces AC5 tenant isolation in /me/maintenance.
    tenant_id       BIGINT UNSIGNED        NULL,
    status          ENUM('NEW','TRIAGED','SCHEDULED','IN_PROGRESS','ON_HOLD','CLOSED','CANCELLED') NOT NULL DEFAULT 'NEW',
    created_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    scheduled_at    DATETIME               NULL,
    closed_at       DATETIME               NULL,
    -- SLA target deadline (used by maintenance-service for breach reporting)
    sla_due_at      DATETIME               NULL,
    -- Free-form internal notes (not visible to tenants)
    notes           TEXT                   NULL,
    PRIMARY KEY (work_order_id),
    UNIQUE KEY uk_work_orders_public_id (public_id),
    KEY ix_work_orders_status      (status),
    KEY ix_work_orders_assigned    (assigned_to),
    KEY ix_work_orders_tenant      (tenant_id),
    KEY ix_work_orders_unit        (unit_id),
    KEY ix_work_orders_prop_status (property_id, status),
    KEY ix_work_orders_sla_due     (sla_due_at)
) ENGINE=InnoDB;

CREATE TABLE maintenance_schedules (
    schedule_id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    public_id           CHAR(36)        NOT NULL,
    -- Cross-context: property.assets; soft FK
    asset_id            BIGINT UNSIGNED     NULL,
    -- Cross-context: property.units; soft FK
    unit_id             BIGINT UNSIGNED     NULL,
    title               VARCHAR(200)    NOT NULL,
    description         TEXT                NULL,
    frequency           VARCHAR(50)     NOT NULL,
    next_due_date       DATE            NOT NULL,
    last_completed_date DATE                NULL,
    status              ENUM('ACTIVE','PAUSED','CANCELLED') NOT NULL DEFAULT 'ACTIVE',
    created_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (schedule_id),
    UNIQUE KEY uk_ms_public_id (public_id),
    -- Enforces the AC: "preventive schedule already exists for the same
    -- assetId/unitId and frequency" -> 409 at the DB layer.
    UNIQUE KEY uk_ms_asset_unit_freq (asset_id, unit_id, frequency),
    KEY ix_ms_asset (asset_id),
    KEY ix_ms_unit  (unit_id),
    KEY ix_ms_due   (next_due_date),
    CONSTRAINT ck_ms_target CHECK (asset_id IS NOT NULL OR unit_id IS NOT NULL)
) ENGINE=InnoDB;

CREATE TABLE part_inventory (
    part_id          BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    public_id        CHAR(36)          NOT NULL,
    name             VARCHAR(150)      NOT NULL,
    sku              VARCHAR(50)       NOT NULL,
    quantity_on_hand INT UNSIGNED      NOT NULL DEFAULT 0,
    reorder_level    INT UNSIGNED      NOT NULL DEFAULT 0,
    unit_cost        DECIMAL(19,4)     NOT NULL DEFAULT 0,
    location         VARCHAR(100)          NULL,
    description      VARCHAR(255)          NULL,
    created_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated     DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (part_id),
    UNIQUE KEY uk_part_inventory_sku       (sku),
    UNIQUE KEY uk_part_inventory_public_id (public_id)
) ENGINE=InnoDB;

CREATE TABLE work_order_attachments (
    attachment_id   BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    public_id       CHAR(36)           NOT NULL,
    work_order_id   BIGINT UNSIGNED    NOT NULL,
    file_name       VARCHAR(255)       NOT NULL,
    mime_type       VARCHAR(100)       NOT NULL,
    file_size_bytes BIGINT UNSIGNED    NOT NULL,
    -- Storage: Internal object store; persist file_ref only (per user story).
    -- This deliberately does not store binary bytes; the actual file lives
    -- in the object store and is fetched/streamed via file_ref.
    file_ref        VARCHAR(512)       NOT NULL,
    -- Cross-context: iam.users; soft FK
    uploaded_by     BIGINT UNSIGNED    NOT NULL,
    uploaded_at     DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (attachment_id),
    UNIQUE KEY uk_wo_attach_public_id (public_id),
    KEY ix_wo_attach_uploader (uploaded_by),
    KEY ix_wo_attach_wo       (work_order_id),
    CONSTRAINT fk_wo_attach_wo
      FOREIGN KEY (work_order_id) REFERENCES work_orders(work_order_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE maintenance_logs (
    log_id          BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    public_id       CHAR(36)           NOT NULL,
    work_order_id   BIGINT UNSIGNED    NOT NULL,
    -- Cross-context: iam.users; soft FK
    technician_id   BIGINT UNSIGNED    NOT NULL,
    parts_used_json JSON                   NULL,
    labor_hours     DECIMAL(6,2)       NOT NULL DEFAULT 0,
    cost            DECIMAL(19,4)      NOT NULL DEFAULT 0,
    notes           TEXT                   NULL,
    completed_at    DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id),
    UNIQUE KEY uk_maint_logs_public_id (public_id),
    KEY ix_maint_logs_tech (technician_id),
    CONSTRAINT fk_maint_logs_wo
      FOREIGN KEY (work_order_id) REFERENCES work_orders(work_order_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- vendors  (maintenance bounded context)
-- External service providers (plumbers, HVAC techs, etc.) that may be
-- assigned to work orders alongside or instead of internal technicians.
-- ---------------------------------------------------------------------
CREATE TABLE vendors (
    vendor_id    BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    public_id    CHAR(36)           NOT NULL,
    name         VARCHAR(200)       NOT NULL,
    contact_name VARCHAR(150)           NULL,
    email        VARCHAR(255)           NULL,
    phone        VARCHAR(30)            NULL,
    specialty    VARCHAR(100)           NULL,
    status       ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at   DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (vendor_id),
    UNIQUE KEY uk_vendors_public_id (public_id),
    UNIQUE KEY uk_vendors_name      (name)
) ENGINE=InnoDB;

CREATE TABLE vendor_assignments (
    assignment_id   BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    public_id       CHAR(36)         NOT NULL,
    work_order_id   BIGINT UNSIGNED  NOT NULL,
    vendor_id       BIGINT UNSIGNED  NOT NULL,
    assigned_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes           VARCHAR(500)         NULL,
    PRIMARY KEY (assignment_id),
    UNIQUE KEY uk_vendor_assignments_public_id (public_id),
    KEY ix_va_work_order (work_order_id),
    KEY ix_va_vendor     (vendor_id),
    CONSTRAINT fk_va_work_order
      FOREIGN KEY (work_order_id) REFERENCES work_orders(work_order_id) ON DELETE CASCADE,
    CONSTRAINT fk_va_vendor
      FOREIGN KEY (vendor_id) REFERENCES vendors(vendor_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- part_reservations  (maintenance bounded context)
-- Two-phase parts allocation: parts are RESERVED when a work order is
-- scheduled, then CONSUMED on completion (decrementing part_inventory)
-- or RELEASED if the work order is cancelled.
-- ---------------------------------------------------------------------
CREATE TABLE part_reservations (
    reservation_id  BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    public_id       CHAR(36)         NOT NULL,
    work_order_id   BIGINT UNSIGNED  NOT NULL,
    part_id         BIGINT UNSIGNED  NOT NULL,
    quantity        INT UNSIGNED     NOT NULL,
    status          ENUM('RESERVED','CONSUMED','RELEASED') NOT NULL DEFAULT 'RESERVED',
    reserved_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (reservation_id),
    UNIQUE KEY uk_part_reservations_public_id (public_id),
    KEY ix_pr_work_order (work_order_id),
    KEY ix_pr_part       (part_id),
    CONSTRAINT fk_pr_work_order
      FOREIGN KEY (work_order_id) REFERENCES work_orders(work_order_id) ON DELETE CASCADE,
    CONSTRAINT fk_pr_part
      FOREIGN KEY (part_id) REFERENCES part_inventory(part_id)
) ENGINE=InnoDB;

-- =====================================================================
-- 11. NOTIFICATIONS & ALERTS  (notifications bounded context)
-- =====================================================================

CREATE TABLE alert_rules (
    rule_id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name                   VARCHAR(150)    NOT NULL,
    trigger_type           VARCHAR(80)     NOT NULL,
    trigger_config_json    JSON                NULL,
    recipients_json        JSON                NULL,
    severity               ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM',
    escalation_policy_json JSON                NULL,
    active                 TINYINT(1)      NOT NULL DEFAULT 1,
    created_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (rule_id),
    UNIQUE KEY uk_alert_rules_name (name)
) ENGINE=InnoDB;

CREATE TABLE notifications (
    notification_id    BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    -- Cross-context: iam.users; soft FK
    recipient_user_id  BIGINT UNSIGNED  NOT NULL,
    rule_id            BIGINT UNSIGNED      NULL,
    message            TEXT             NOT NULL,
    channel            ENUM('IN_APP','EMAIL_SIM','SMS_SIM') NOT NULL DEFAULT 'IN_APP',
    status             ENUM('PENDING','SENT','DELIVERED','READ','ACKNOWLEDGED','FAILED') NOT NULL DEFAULT 'PENDING',
    created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    sent_at            DATETIME             NULL,
    acknowledged_at    DATETIME             NULL,
    PRIMARY KEY (notification_id),
    KEY ix_notifications_user_status (recipient_user_id, status),
    CONSTRAINT fk_notifications_rule
      FOREIGN KEY (rule_id) REFERENCES alert_rules(rule_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =====================================================================
-- 12. ANALYTICS & COMPLIANCE  (analytics + compliance contexts)
-- =====================================================================

CREATE TABLE analytics_datasets (
    dataset_id        BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    name              VARCHAR(150)     NOT NULL,
    schema_ref        VARCHAR(255)         NULL,
    last_refreshed_at DATETIME             NULL,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (dataset_id),
    UNIQUE KEY uk_datasets_name (name)
) ENGINE=InnoDB;

CREATE TABLE kpi_reports (
    report_id       BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    name            VARCHAR(150)       NOT NULL,
    scope           VARCHAR(100)       NOT NULL,
    window_start    DATE                   NULL,
    window_end      DATE                   NULL,
    metrics_json    JSON                   NULL,
    generated_date  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Cross-context: iam.users; soft FK
    generated_by    BIGINT UNSIGNED    NOT NULL,
    file_name       VARCHAR(255)           NULL,
    mime_type       VARCHAR(100)           NULL,
    file_size_bytes BIGINT UNSIGNED        NULL,
    file_data       LONGBLOB               NULL,
    created_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (report_id),
    KEY ix_kpi_reports_user (generated_by)
) ENGINE=InnoDB;

-- Owned by reporting-service; soft FK to kpi_reports + iam.users.
CREATE TABLE report_jobs (
    job_id        BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    job_uuid      CHAR(36)           NOT NULL,
    name          VARCHAR(150)       NOT NULL,
    scope         VARCHAR(100)       NOT NULL,
    schedule_cron VARCHAR(100)           NULL,
    window_start  DATE                   NULL,
    window_end    DATE                   NULL,
    status        ENUM('SCHEDULED','RUNNING','COMPLETED','FAILED','PAUSED')
                  NOT NULL DEFAULT 'SCHEDULED',
    last_run_at   DATETIME               NULL,
    next_run_at   DATETIME               NULL,
    -- Cross-context: iam.users; soft FK
    created_by    BIGINT UNSIGNED    NOT NULL,
    created_at    DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (job_id),
    UNIQUE KEY uk_report_jobs_uuid       (job_uuid),
    UNIQUE KEY uk_report_jobs_scope_cron (scope, schedule_cron),
    KEY ix_report_jobs_status            (status),
    KEY ix_report_jobs_next_run          (next_run_at)
) ENGINE=InnoDB;

CREATE TABLE report_exports (
    export_id       BIGINT UNSIGNED    NOT NULL AUTO_INCREMENT,
    export_uuid     CHAR(36)           NOT NULL,
    report_id       BIGINT UNSIGNED    NOT NULL,
    format          ENUM('CSV','JSON') NOT NULL,
    status          ENUM('PENDING','READY','FAILED')
                    NOT NULL DEFAULT 'PENDING',
    file_ref        VARCHAR(512)           NULL,
    file_name       VARCHAR(255)           NULL,
    file_size_bytes BIGINT UNSIGNED        NULL,
    -- Cross-context: iam.users; soft FK
    created_by      BIGINT UNSIGNED    NOT NULL,
    created_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (export_id),
    UNIQUE KEY uk_report_exports_uuid          (export_uuid),
    -- Plain index on report_id (was previously a UNIQUE composite with
    -- format). Uniqueness was dropped so users can re-export the same
    -- (report, format) any number of times; the FK still needs an index
    -- on its local column to satisfy InnoDB.
    KEY ix_report_exports_report               (report_id),
    KEY ix_report_exports_status               (status),
    CONSTRAINT fk_report_exports_report
        FOREIGN KEY (report_id) REFERENCES kpi_reports(report_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE compliance_reports (
    compliance_report_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    type            VARCHAR(100)       NOT NULL,
    scope           VARCHAR(100)       NOT NULL,
    generated_date  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    file_name       VARCHAR(255)           NULL,
    mime_type       VARCHAR(100)           NULL,
    file_size_bytes BIGINT UNSIGNED        NULL,
    file_data       LONGBLOB               NULL,
    created_at      DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (compliance_report_id)
) ENGINE=InnoDB;

CREATE TABLE retention_policies (
    policy_id             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    data_type             VARCHAR(100)  NOT NULL,
    retention_period_days INT UNSIGNED  NOT NULL,
    applied_from          DATE          NOT NULL,
    notes                 VARCHAR(255)      NULL,
    created_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (policy_id),
    UNIQUE KEY uk_retention_data_type (data_type)
) ENGINE=InnoDB;

-- =====================================================================
-- SEED DATA (lookups + minimal dev seed)
-- =====================================================================

-- =====================================================================
-- Roles - seeded with permissions_json so JWTs minted by iam-service
-- carry the right permission claims for every other service's RBAC checks.
-- Permission naming follows the {DOMAIN}_{ACTION} convention used by
-- @PreAuthorize annotations across the platform.
-- =====================================================================
INSERT INTO roles (name, description, permissions_json) VALUES
  ('ADMIN','System administrator', JSON_ARRAY(
      'IAM_USER_READ',  'IAM_USER_WRITE',
      'IAM_ROLE_READ',  'IAM_ROLE_WRITE',
      'IAM_AUDIT_READ',
      'PROPERTY_READ',  'PROPERTY_WRITE',
      'LEASING_READ',   'LEASING_WRITE',
      'TENANT_READ',    'TENANT_WRITE',
      'COMPLIANCE_READ','COMPLIANCE_WRITE',
      'MAINT_WORKORDER_READ','MAINT_WORKORDER_WRITE',
      'MAINT_SCHEDULE_READ', 'MAINT_SCHEDULE_WRITE',
      'MAINT_INVENTORY_READ','MAINT_INVENTORY_WRITE',
      'MAINT_VENDOR_READ',   'MAINT_VENDOR_WRITE',
      'ACCOUNTING_READ','ACCOUNTING_WRITE',
      'ASSET_READ',     'ASSET_WRITE',
      'REPORTING_READ', 'REPORTING_WRITE'
  )),
  ('PROPERTY_MANAGER','Manages portfolios, leases, tenant relations', JSON_ARRAY(
      'IAM_USER_READ', 'IAM_ROLE_READ',
      'PROPERTY_READ', 'PROPERTY_WRITE',
      'LEASING_READ',  'LEASING_WRITE',
      'TENANT_READ',
      'MAINT_WORKORDER_READ','MAINT_WORKORDER_WRITE',
      'MAINT_SCHEDULE_READ',
      'ASSET_READ',    'ASSET_WRITE',
      -- Reporting access: PM uses the KPI / Report-jobs / Datasets tabs in
      -- the SPA sidebar, so they need both READ and WRITE (the latter for
      -- creating report jobs and triggering exports).
      'REPORTING_READ','REPORTING_WRITE'
  )),
  ('LEASING_AGENT','Handles listings, showings, applications', JSON_ARRAY(
      'PROPERTY_READ',
      'LEASING_READ', 'LEASING_WRITE',
      'TENANT_READ'
  )),
  ('TENANT','End user tenant', JSON_ARRAY(
      'TENANT_READ',
      -- Cross-context reads needed by tenant-service when it acts on the
      -- tenant's behalf. With no service-account model yet, tenant tokens
      -- carry these so tenant-service can forward them to leasing /
      -- maintenance / accounting. Revisit when adopting service accounts
      -- (see PLATFORM_NOTES.md "TENANT permission compromise").
      'LEASING_READ',
      'PROPERTY_READ',
      'MAINT_WORKORDER_READ',
      'MAINT_WORKORDER_WRITE',
      'ACCOUNTING_READ'
  )),
  ('MAINTENANCE_TECH','Executes work orders', JSON_ARRAY(
      'MAINT_WORKORDER_READ', 'MAINT_WORKORDER_WRITE',
      'MAINT_SCHEDULE_READ',
      'MAINT_INVENTORY_READ', 'MAINT_INVENTORY_WRITE',
      'MAINT_VENDOR_READ',
      'ASSET_READ'
  )),
  ('ACCOUNTING_OFFICER','Handles invoicing and financials', JSON_ARRAY(
      'ACCOUNTING_READ', 'ACCOUNTING_WRITE',
      'TENANT_READ',     'LEASING_READ',
      -- Reporting access for financial analytics (same Sidebar gate as PM).
      'REPORTING_READ',  'REPORTING_WRITE'
  )),
  ('FACILITIES_MANAGER','Preventive maintenance and space utilization', JSON_ARRAY(
      'PROPERTY_READ',  'PROPERTY_WRITE',
      'MAINT_WORKORDER_READ','MAINT_WORKORDER_WRITE',
      'MAINT_SCHEDULE_READ', 'MAINT_SCHEDULE_WRITE',
      'MAINT_VENDOR_READ',   'MAINT_VENDOR_WRITE',
      'ASSET_READ',     'ASSET_WRITE'
  ));

-- Minimal chart-of-accounts for billing-service ledger postings.
-- Codes follow common accounting convention (1xxx=assets, 2xxx=liabilities,
-- 4xxx=revenue, 5xxx=expense). Extend as needed.
INSERT INTO accounts (code, name, account_type, description) VALUES
  ('1100','Accounts Receivable',    'ASSET',     'Money owed by tenants (issued invoices)'),
  ('1200','Cash - Operating',       'ASSET',     'Operating cash account'),
  ('1300','Bank - Operating',       'ASSET',     'Operating bank account'),
  ('2100','Security Deposits Held', 'LIABILITY', 'Tenant security deposits held in escrow'),
  ('2200','Unearned Revenue',       'LIABILITY', 'Rent received but not yet earned'),
  ('4100','Rental Revenue',         'REVENUE',   'Rent income recognised on issued invoices'),
  ('4200','Late Fee Revenue',       'REVENUE',   'Late payment fees collected'),
  ('4300','Other Revenue',          'REVENUE',   'Miscellaneous revenue (utilities pass-through, etc.)'),
  ('5100','Bad Debt Expense',       'EXPENSE',   'Written-off uncollectable amounts');

INSERT INTO payment_methods (name, description) VALUES
  ('BANK_TRANSFER','Manual bank transfer'),
  ('CASH','Cash received at office'),
  ('CHEQUE','Cheque deposit'),
  ('INTERNAL_LEDGER','Ledger adjustment only'),
  ('CARD_SIM','Simulated card payment (Phase 1)');

INSERT INTO document_types (name, description) VALUES
  ('LEASE_AGREEMENT','Signed lease document'),
  ('ID_PROOF','Government issued identity proof'),
  ('ADDRESS_PROOF','Address verification document'),
  ('INCOME_PROOF','Income/salary proof'),
  ('WARRANTY','Asset warranty document'),
  ('INSPECTION_REPORT','Property/unit inspection report'),
  ('INVOICE_PDF','Generated invoice'),
  ('MISC','Miscellaneous document');

-- Minimal geo seed for local dev
INSERT INTO countries (country_code, name) VALUES ('IN','India');
INSERT INTO states (country_code, state_code, name) VALUES ('IN','MH','Maharashtra');
INSERT INTO cities (state_id, name) VALUES (1, 'Pune');

-- =====================================================================
-- END OF SCHEMA  (51 tables - Phase 0 compliant, split-ready)
-- Next step: run realestate360_users.sql to create per-context DB users
-- =====================================================================