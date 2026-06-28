-- =====================================================================
-- Geography seed — Indian states + major cities.
--
-- Why this file exists:
--   property-service enforces FKs from properties.city_id -> cities.city_id
--   and cities.state_id -> states.state_id. The default schema seed only
--   ships Maharashtra/Pune, which locks the Create Property form to one
--   option. This seed adds 8 more states and 14 more cities so the SPA's
--   dropdowns reflect a usable geography.
--
-- Idempotent: safe to re-run; uses explicit primary-key INSERTs + ON
-- DUPLICATE KEY UPDATE so existing rows are refreshed in place.
-- Connect as root because the schema's per-service grants don't include
-- reference-table writes.
-- =====================================================================

USE realestate3601;

-- ---------- States ----------
INSERT INTO states (state_id, country_code, state_code, name) VALUES
    (1, 'IN', 'MH', 'Maharashtra'),
    (2, 'IN', 'KA', 'Karnataka'),
    (3, 'IN', 'DL', 'Delhi'),
    (4, 'IN', 'TN', 'Tamil Nadu'),
    (5, 'IN', 'TG', 'Telangana'),
    (6, 'IN', 'WB', 'West Bengal'),
    (7, 'IN', 'GJ', 'Gujarat'),
    (8, 'IN', 'UP', 'Uttar Pradesh'),
    (9, 'IN', 'HR', 'Haryana') AS new_row
ON DUPLICATE KEY UPDATE
    country_code = new_row.country_code,
    state_code   = new_row.state_code,
    name         = new_row.name;

-- ---------- Cities ----------
INSERT INTO cities (city_id, state_id, name) VALUES
    (1,  1, 'Pune'),
    (2,  1, 'Mumbai'),
    (3,  1, 'Nagpur'),
    (4,  2, 'Bengaluru'),
    (5,  2, 'Mysuru'),
    (6,  3, 'New Delhi'),
    (7,  4, 'Chennai'),
    (8,  4, 'Coimbatore'),
    (9,  5, 'Hyderabad'),
    (10, 6, 'Kolkata'),
    (11, 7, 'Ahmedabad'),
    (12, 7, 'Surat'),
    (13, 8, 'Lucknow'),
    (14, 8, 'Noida'),
    (15, 9, 'Gurugram') AS new_row
ON DUPLICATE KEY UPDATE
    state_id = new_row.state_id,
    name     = new_row.name;

-- ---------- Sanity ----------
SELECT (SELECT COUNT(*) FROM states) AS states_total,
       (SELECT COUNT(*) FROM cities) AS cities_total;
