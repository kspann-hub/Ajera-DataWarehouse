{{
  config(
    materialized = 'table'
  )
}}

-- ============================================================
-- slv_timesheet_project_daily
-- Grain: one row per (timesheet × project × phase × work_date)
-- 
-- Bronze→silver transformation:
--   1. UNNEST Project.Detail[] → one row per (timesheet × project × phase)
--   2. UNPIVOT D1–D7 wide columns → one row per work_date
--   3. Type cast, snake_case rename, derive calendar dates
--   4. Add quality flags and audit fields
--
-- Header fields locked per chunk 1 review.
-- Project.Detail.* fields are provisional pending chunk 2 review.
-- Days with zero hours logged are excluded.
-- ============================================================

WITH

-- 1. SOURCE: bronze landing zone, untouched
source AS (
    SELECT *
    FROM {{ source('ajera_bronze', 'raw_timesheets_detailed') }}
),

-- 2. UNNEST Project.Detail[] and rename to snake_case
--    Grain at this step: one row per (timesheet × project × phase), still wide D1–D7
unnested AS (
    SELECT
        -- ===== Header fields (chunk 1: locked) =====
        s.TimesheetKey                          AS timesheet_key,
        s.EmployeeKey                           AS ajera_employee_key,
        s.FirstName                             AS employee_first_name,
        s.LastName                              AS employee_last_name,
        s.EmployeeStatus                        AS employee_status,
        CAST(s.TimesheetDate AS DATE)           AS week_end_date,
        CAST(s.SubmittedDate AS DATE)           AS submitted_at,
        s.SubmittedBy                           AS submitted_by_name,
        s.ProjectManagerApproved                AS pm_approved_timesheet_rollup,
        s.ProjectManagerApprovedValue           AS pm_approved_value_raw,
        s.SupervisorApproved                    AS supervisor_approved,
        s.SupervisorApprovedBy                  AS supervisor_approved_by,
        CAST(s.SupervisorApprovedDate AS DATE)  AS supervisor_approved_at,
        s.AccountingApproved                    AS accounting_approved,
        s.AccountingApprovedBy                  AS accounting_approved_by,
        CAST(s.AccountingApprovedDate AS DATE)  AS accounting_approved_at,

        -- ===== Project-level fields from Project.Detail (chunk 2: provisional) =====
        d.`Project Key`                         AS project_key,
        d.`Phase Key`                           AS phase_key,
        d.`Project Description`                 AS project_description,
        d.`Phase Description`                   AS phase_description,
        d.Activity                              AS activity_name,
        d.`Activity Key`                        AS activity_key,
        d.`Project Status`                      AS project_status,
        d.`Phase Status`                        AS phase_status,
        d.`Project Manager Approved`            AS pm_approved_project_rollup,

        -- ===== Wide D1–D7 columns: renamed for the unpivot below =====
        -- Worked hours (FLOAT)
        d.`D1 Regular`  AS d1_regular,  d.`D2 Regular`  AS d2_regular,
        d.`D3 Regular`  AS d3_regular,  d.`D4 Regular`  AS d4_regular,
        d.`D5 Regular`  AS d5_regular,  d.`D6 Regular`  AS d6_regular,
        d.`D7 Regular`  AS d7_regular,
        -- Overtime hours (only Sun, Thu, Fri, Sat exist in source)
        d.`D1 Overtime`            AS d1_overtime,
        CAST(NULL AS FLOAT64)      AS d2_overtime,
        CAST(NULL AS FLOAT64)      AS d3_overtime,
        CAST(NULL AS FLOAT64)      AS d4_overtime,
        d.`D5 Overtime`            AS d5_overtime,
        d.`D6 Overtime`            AS d6_overtime,
        d.`D7 Overtime`            AS d7_overtime,

        -- Paid hours (INT, from payroll)
        d.`D1 Paid`    AS d1_paid,    d.`D2 Paid`    AS d2_paid,
        d.`D3 Paid`    AS d3_paid,    d.`D4 Paid`    AS d4_paid,
        d.`D5 Paid`    AS d5_paid,    d.`D6 Paid`    AS d6_paid,
        d.`D7 Paid`    AS d7_paid,
        d.`D1 OT Paid`             AS d1_ot_paid,
        CAST(NULL AS INT64)        AS d2_ot_paid,
        CAST(NULL AS INT64)        AS d3_ot_paid,
        CAST(NULL AS INT64)        AS d4_ot_paid,
        d.`D5 OT Paid`             AS d5_ot_paid,
        d.`D6 OT Paid`             AS d6_ot_paid,
        d.`D7 OT Paid`             AS d7_ot_paid,

        -- Billed hours (INT, to client)
        d.`D1 Billed`    AS d1_billed,    d.`D2 Billed`    AS d2_billed,
        d.`D3 Billed`    AS d3_billed,    d.`D4 Billed`    AS d4_billed,
        d.`D5 Billed`    AS d5_billed,    d.`D6 Billed`    AS d6_billed,
        d.`D7 Billed`    AS d7_billed,
        d.`D1 OT Billed`           AS d1_ot_billed,
        CAST(NULL AS INT64)        AS d2_ot_billed,
        CAST(NULL AS INT64)        AS d3_ot_billed,
        CAST(NULL AS INT64)        AS d4_ot_billed,
        CAST(NULL AS INT64)        AS d5_ot_billed,
        d.`D6 OT Billed`           AS d6_ot_billed,
        d.`D7 OT Billed`           AS d7_ot_billed,

        -- Notes
        d.`D1 Notes` AS d1_notes, d.`D2 Notes` AS d2_notes,
        d.`D3 Notes` AS d3_notes, d.`D4 Notes` AS d4_notes,
        d.`D5 Notes` AS d5_notes, d.`D6 Notes` AS d6_notes,
        d.`D7 Notes` AS d7_notes,

        -- PM approval, regular hours
        d.`D1 PM Approved By`   AS d1_reg_approved_by,
        d.`D2 PM Approved By`   AS d2_reg_approved_by,
        d.`D3 PM Approved By`   AS d3_reg_approved_by,
        d.`D4 PM Approved By`   AS d4_reg_approved_by,
        d.`D5 PM Approved By`   AS d5_reg_approved_by,
        d.`D6 PM Approved By`   AS d6_reg_approved_by,
        d.`D7 PM Approved By`   AS d7_reg_approved_by,
        d.`D1 PM Approved Date` AS d1_reg_approved_at,
        d.`D2 PM Approved Date` AS d2_reg_approved_at,
        d.`D3 PM Approved Date` AS d3_reg_approved_at,
        d.`D4 PM Approved Date` AS d4_reg_approved_at,
        d.`D5 PM Approved Date` AS d5_reg_approved_at,
        d.`D6 PM Approved Date` AS d6_reg_approved_at,
        d.`D7 PM Approved Date` AS d7_reg_approved_at,

        -- PM approval, overtime hours (only Sun, Thu, Fri, Sat exist in source)
        d.`D1 OT PM Approved By`     AS d1_ot_approved_by,
        CAST(NULL AS INT64)          AS d2_ot_approved_by,
        CAST(NULL AS INT64)          AS d3_ot_approved_by,
        CAST(NULL AS INT64)          AS d4_ot_approved_by,
        d.`D5 OT PM Approved By`     AS d5_ot_approved_by,
        d.`D6 OT PM Approved By`     AS d6_ot_approved_by,
        d.`D7 OT PM Approved By`     AS d7_ot_approved_by,
        d.`D1 OT PM Approved Date`   AS d1_ot_approved_at,
        CAST(NULL AS DATE)           AS d2_ot_approved_at,
        CAST(NULL AS DATE)           AS d3_ot_approved_at,
        CAST(NULL AS DATE)           AS d4_ot_approved_at,
        d.`D5 OT PM Approved Date`   AS d5_ot_approved_at,
        d.`D6 OT PM Approved Date`   AS d6_ot_approved_at,
        d.`D7 OT PM Approved Date`   AS d7_ot_approved_at

    FROM source s
    LEFT JOIN UNNEST(s.Project.Detail) AS d
),

-- 3. UNPIVOT D1–D7 → one row per work_date
--    Grain at this step: one row per (timesheet × project × phase × work_date)
--    Skip-null filter: drop days where no hours were logged on this project.
daily AS (
    SELECT
        -- Header fields (denormalized onto every daily row)
        u.timesheet_key,
        u.ajera_employee_key,
        u.employee_first_name,
        u.employee_last_name,
        u.employee_status,
        u.week_end_date,
        u.submitted_at,
        u.submitted_by_name,
        u.pm_approved_timesheet_rollup,
        u.pm_approved_value_raw,
        u.supervisor_approved,
        u.supervisor_approved_by,
        u.supervisor_approved_at,
        u.accounting_approved,
        u.accounting_approved_by,
        u.accounting_approved_at,

        -- Project & phase context
        u.project_key,
        u.phase_key,
        u.project_description,
        u.phase_description,
        u.activity_name,
        u.activity_key,
        u.project_status,
        u.phase_status,
        u.pm_approved_project_rollup,

        -- Day mapping (this is the heart of the unpivot)
        day.day_number,
        DATE_SUB(u.week_end_date, INTERVAL (7 - day.day_number) DAY) AS work_date,

        -- Daily measures
        day.hours_regular,
        day.hours_overtime,
        day.hours_paid,
        day.hours_ot_paid,
        day.hours_billed,
        day.hours_ot_billed,
        day.notes,
        day.pm_regular_approved_by_emp_key,
        day.pm_regular_approved_at,
        day.pm_overtime_approved_by_emp_key,
        day.pm_overtime_approved_at

    FROM unnested u
    CROSS JOIN UNNEST([
        STRUCT(
            1 AS day_number,
            u.d1_regular  AS hours_regular,
            u.d1_overtime AS hours_overtime,
            u.d1_paid     AS hours_paid,
            u.d1_ot_paid  AS hours_ot_paid,
            u.d1_billed   AS hours_billed,
            u.d1_ot_billed AS hours_ot_billed,
            u.d1_notes    AS notes,
            u.d1_reg_approved_by AS pm_regular_approved_by_emp_key,
            u.d1_reg_approved_at AS pm_regular_approved_at,
            u.d1_ot_approved_by  AS pm_overtime_approved_by_emp_key,
            u.d1_ot_approved_at  AS pm_overtime_approved_at
        ),
        STRUCT(
            2, u.d2_regular, u.d2_overtime, u.d2_paid, u.d2_ot_paid,
            u.d2_billed, u.d2_ot_billed, u.d2_notes,
            u.d2_reg_approved_by, u.d2_reg_approved_at,
            u.d2_ot_approved_by, u.d2_ot_approved_at
        ),
        STRUCT(
            3, u.d3_regular, u.d3_overtime, u.d3_paid, u.d3_ot_paid,
            u.d3_billed, u.d3_ot_billed, u.d3_notes,
            u.d3_reg_approved_by, u.d3_reg_approved_at,
            u.d3_ot_approved_by, u.d3_ot_approved_at
        ),
        STRUCT(
            4, u.d4_regular, u.d4_overtime, u.d4_paid, u.d4_ot_paid,
            u.d4_billed, u.d4_ot_billed, u.d4_notes,
            u.d4_reg_approved_by, u.d4_reg_approved_at,
            u.d4_ot_approved_by, u.d4_ot_approved_at
        ),
        STRUCT(
            5, u.d5_regular, u.d5_overtime, u.d5_paid, u.d5_ot_paid,
            u.d5_billed, u.d5_ot_billed, u.d5_notes,
            u.d5_reg_approved_by, u.d5_reg_approved_at,
            u.d5_ot_approved_by, u.d5_ot_approved_at
        ),
        STRUCT(
            6, u.d6_regular, u.d6_overtime, u.d6_paid, u.d6_ot_paid,
            u.d6_billed, u.d6_ot_billed, u.d6_notes,
            u.d6_reg_approved_by, u.d6_reg_approved_at,
            u.d6_ot_approved_by, u.d6_ot_approved_at
        ),
        STRUCT(
            7, u.d7_regular, u.d7_overtime, u.d7_paid, u.d7_ot_paid,
            u.d7_billed, u.d7_ot_billed, u.d7_notes,
            u.d7_reg_approved_by, u.d7_reg_approved_at,
            u.d7_ot_approved_by, u.d7_ot_approved_at
        )
    ]) AS day
    -- Skip days with no hours logged on this project (notes-only days also dropped)
    WHERE COALESCE(
        day.hours_regular, day.hours_overtime,
        day.hours_paid, day.hours_ot_paid,
        day.hours_billed, day.hours_ot_billed
    ) IS NOT NULL
),

-- 4. DERIVE final columns and reorder for readability
final AS (
    SELECT
        -- Natural key for this grain
        timesheet_key,
        project_key,
        phase_key,
        work_date,
        day_number,

        -- Employee
        ajera_employee_key,
        employee_first_name,
        employee_last_name,
        employee_status,

        -- Week context (derived)
        DATE_SUB(week_end_date, INTERVAL 6 DAY) AS week_start_date,
        week_end_date,

        -- Project & phase context
        project_description,
        phase_description,
        project_status,
        phase_status,
        activity_name,
        activity_key,

        -- Daily worked hours (FLOAT) + derived total
        hours_regular,
        hours_overtime,
        COALESCE(hours_regular, 0) + COALESCE(hours_overtime, 0) AS hours_total_worked,

        -- Daily paid hours (INT, from payroll)
        hours_paid,
        hours_ot_paid,

        -- Daily billed hours (INT, to client)
        hours_billed,
        hours_ot_billed,

        -- PM approval (per-day, per-category — the authoritative signal)
        pm_regular_approved_by_emp_key,
        pm_regular_approved_at,
        pm_overtime_approved_by_emp_key,
        pm_overtime_approved_at,

        -- Approval rollups (week + project level convenience)
        pm_approved_project_rollup,
        pm_approved_timesheet_rollup,
        pm_approved_value_raw,
        supervisor_approved,
        supervisor_approved_by,
        supervisor_approved_at,
        accounting_approved,
        accounting_approved_by,
        accounting_approved_at,

        -- Submission audit
        submitted_at,
        submitted_by_name,
        DATE_DIFF(submitted_at, week_end_date, DAY) AS days_to_submit,

        -- Notes
        notes,

        -- Quality flags (analyst-friendly)
        (project_key IS NOT NULL AND phase_key IS NOT NULL)
            AS has_valid_project_keys,
        (hours_regular IS NULL OR pm_regular_approved_at IS NOT NULL)
            AS regular_hours_approved,
        (hours_overtime IS NULL OR pm_overtime_approved_at IS NOT NULL)
            AS overtime_hours_approved

    FROM daily
)

SELECT * FROM final