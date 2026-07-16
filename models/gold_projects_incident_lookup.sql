
{{ config(materialized='table', schema='ajera_gold') }}
-- ============================================================
-- gold_projects_incident_lookup
-- Grain: one row per project (project_key)
--
-- Minimal project lookup for the AppSheet incident report form
-- dropdown. Not a replacement for gold_projects (full dimension) —
-- this is a narrow, purpose-built slice for one consumer.
-- ============================================================
WITH gold AS (
    SELECT
        project_key,
        project_description,
        cf_project_location AS project_state,
        project_status
    FROM {{ ref('slv_projects') }}
)

SELECT * FROM gold