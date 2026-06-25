

{{ config(materialized='table', schema='ajera_gold') }}

-- ============================================================
-- gld_timesheet_project_daily
-- Grain: one row per (timesheet × project × phase × work_date),
--        inherited unchanged from slv_timesheet_project_daily.
--
-- Purpose: curated serving model for the Staff Forecaster / Retool.
--   - Projects the columns the tool needs (no joins, no aggregation)
--   - Adds the business metric `time_actualized`
--
-- Business logic lives here (gold), not in silver:
--   time_actualized = 'YES' only when a timesheet has cleared BOTH
--   the supervisor and accounting approval gates; otherwise 'NO'.
--   NULL / unknown approvals fall to 'NO' (never actualize on unknown).
--
-- Grain note: supervisor_approved / accounting_approved are
--   timesheet-level rollups, so time_actualized is a timesheet-level
--   status repeated across every daily row of that timesheet.
--
-- Materialization: view (pure projection, always reflects silver).
--   Switch to 'table' above if Retool query performance needs it.
-- ============================================================

WITH gold AS (
    SELECT
        -- ===== Natural key for this grain =====
        timesheet_key,
        project_key,
        phase_key,
        ajera_employee_key,
        work_date,

        -- ===== Week context =====
        week_start_date,
        week_end_date,

        -- ===== Project & phase context =====
        project_description,
        phase_description,
        project_status,
        phase_status,
        activity_name,
        activity_key,

        -- ===== Daily measures =====
        hours_regular,
        hours_overtime,
        hours_total_worked,

        -- ===== Approval flags (timesheet-level rollups) =====
        supervisor_approved,
        accounting_approved,

        -- ===== Derived metric: time_actualized =====
        -- Both gates TRUE -> 'YES'; one/both FALSE or NULL -> 'NO'.
        CASE
            WHEN supervisor_approved AND accounting_approved THEN 'YES'
            ELSE 'NO'
        END AS time_actualized

    FROM {{ ref('slv_timesheet_project_daily') }}
)

SELECT * FROM gold