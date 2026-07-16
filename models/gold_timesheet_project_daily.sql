{{ config(materialized='table', schema='ajera_gold') }}

-- ============================================================
-- gold_timesheet_project_daily
-- Grain: one row per (timesheet × project × phase × work_date × activity).
--        Regrouped from silver to collapse the regular/overtime row-split
--        artifact (OT and regular hours for one activity-day arrived as
--        two rows; SUM folds them into one).
--
-- Purpose: curated serving model for the Staff Forecaster / Retool.
--
-- Business logic (lives here in gold, not silver):
--   time_actualized = 'YES' only when BOTH the supervisor and accounting
--   approval gates are cleared; NULL/unknown approvals fall to 'NO'
--   (never actualize on unknown).
--
-- Materialization: table.
-- ============================================================

WITH aggregated AS (
    SELECT
        timesheet_key,
        project_key,
        phase_key,
        work_date,
        activity_key,
        ANY_VALUE(week_start_date)      AS week_start_date,
        ANY_VALUE(week_end_date)        AS week_end_date,
        ANY_VALUE(project_description)  AS project_description,
        ANY_VALUE(phase_description)    AS phase_description,
        ANY_VALUE(project_status)       AS project_status,
        ANY_VALUE(phase_status)         AS phase_status,
        ANY_VALUE(activity_name)        AS activity_name,
        ANY_VALUE(ajera_employee_key)   AS ajera_employee_key,
        SUM(hours_regular)              AS hours_regular,
        SUM(hours_overtime)             AS hours_overtime,
        SUM(hours_total_worked)         AS hours_total_worked,
        ANY_VALUE(supervisor_approved)  AS supervisor_approved,
        ANY_VALUE(accounting_approved)  AS accounting_approved
    FROM {{ ref('slv_timesheet_project_daily') }}
    GROUP BY timesheet_key, project_key, phase_key, work_date, activity_key
)

SELECT
    *,
    CASE
        WHEN supervisor_approved AND accounting_approved THEN 'YES'
        ELSE 'NO'
    END AS time_actualized
FROM aggregated