-- =====================================================================
-- Notification schema patch — adds the columns the JPA entity expects
-- but the original real_db_schema.sql never created.
--
-- Why this file exists:
--   notification-service's Notification.java entity was extended to
--   support SLA escalation + a richer inbox (subject, severity, event_key,
--   escalated_from_id, escalation_count, read_at). MySQL's notifications
--   table never grew those columns, so every Hibernate SELECT fails with:
--     "Unknown column 'n1_0.escalated_from_id' in 'field list'"
--   which surfaces as HTTP 500 on the /notifications endpoints.
--
-- Idempotent: each ADD COLUMN is gated on information_schema, so
-- re-running on an already-patched schema is silent. MySQL 8.0 doesn't
-- support `ADD COLUMN IF NOT EXISTS`, hence the conditional dance.
-- Apply: mysql -uroot -proot < seed_notification_columns.sql
-- =====================================================================

USE realestate3601;

-- Helper macro pattern: check information_schema, prepare an ALTER, execute.
-- Repeated for each new column.

-- 1a. subject
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='subject');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD COLUMN subject VARCHAR(255) NULL AFTER rule_id',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 1b. severity
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='severity');
SET @sql := IF(@has=0,
  "ALTER TABLE notifications ADD COLUMN severity ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM' AFTER status",
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 1c. event_key
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='event_key');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD COLUMN event_key VARCHAR(200) NULL AFTER severity',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 1d. escalated_from_id
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='escalated_from_id');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD COLUMN escalated_from_id BIGINT UNSIGNED NULL AFTER event_key',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 1e. escalation_count
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='escalation_count');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD COLUMN escalation_count INT NOT NULL DEFAULT 0 AFTER escalated_from_id',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 1f. read_at
SET @has := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND COLUMN_NAME='read_at');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD COLUMN read_at DATETIME NULL AFTER acknowledged_at',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 2. Extend the status enum to include UNREAD (entity's @PrePersist default).
--    MODIFY is idempotent — re-applying with the same definition is silent.
ALTER TABLE notifications
  MODIFY COLUMN status
        ENUM('UNREAD','PENDING','SENT','DELIVERED','READ','ACKNOWLEDGED','FAILED')
        NOT NULL DEFAULT 'UNREAD';

-- 3. UNIQUE on event_key (idempotency key). Conditional add.
SET @has := (SELECT COUNT(*) FROM information_schema.STATISTICS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND INDEX_NAME='uk_notifications_event_key');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD UNIQUE KEY uk_notifications_event_key (event_key)',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 4. Self-FK for escalated_from_id.
SET @has := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
             WHERE TABLE_SCHEMA='realestate3601' AND TABLE_NAME='notifications'
               AND CONSTRAINT_NAME='fk_notifications_escalated_from');
SET @sql := IF(@has=0,
  'ALTER TABLE notifications ADD CONSTRAINT fk_notifications_escalated_from
     FOREIGN KEY (escalated_from_id) REFERENCES notifications(notification_id)',
  'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 5. Sanity check — describe the final table state.
DESCRIBE notifications;
