{{
  config(
    materialized = 'table',
    schema = 'ajera_gold'
  )
}}

-- ============================================================
-- gold_project_phases
-- Grain: one row per phase (any level). Curated phase dimension
--        with the hierarchy linkage flattened onto every row.
--
-- Derived linkage (depth capped at 3, so no recursion needed):
--   parent_phase_description : name of the immediate parent phase
--   root_phase_key           : the level-1 stage this phase rolls up to
--                              (itself if level 1; parent if 2; grandparent if 3)
--   root_phase_description   : name of that stage
--   phase_path               : readable "Stage > Sub > SubSub" string
--
-- Rollup pattern: join hours from gold_timesheet_project_daily on
--   phase_key, then GROUP BY root_phase_key for true stage totals.
--   Hours roll up safely (one phase_key per timesheet line). Budgets/
--   contract amounts are left at native level -- do NOT sum up the tree
--   until it's confirmed whether a parent already includes its children.
--
-- has_contract_value re-derived here (silver carries has_hours_budget).
-- Self-joins match on (project_key, phase_key) defensively.
-- ============================================================

WITH phases AS (
    SELECT * FROM {{ ref('slv_project_phases') }}
),

-- Attach immediate-parent name + grandparent key (for level-3 roots)
linked AS (
    SELECT
        ph.*,
        par.phase_description  AS parent_phase_description,
        par.parent_phase_key   AS grandparent_phase_key
    FROM phases ph
    LEFT JOIN phases par
        ON  ph.parent_phase_key = par.phase_key
        AND ph.project_key      = par.project_key
),

-- Resolve the level-1 stage (root) for every phase
rooted AS (
    SELECT
        *,
        CASE phase_level
            WHEN 1 THEN phase_key
            WHEN 2 THEN parent_phase_key
            WHEN 3 THEN grandparent_phase_key
        END AS root_phase_key
    FROM linked
),

final AS (
    SELECT
        -- ===== Identity & hierarchy =====
        r.project_key,
        r.invoice_group_key,
        r.phase_key,
        r.parent_phase_key,
        r.root_phase_key,
        r.phase_level,
        r.phase_description,
        r.parent_phase_description,
        root.phase_description AS root_phase_description,
        CASE r.phase_level
            WHEN 1 THEN r.phase_description
            WHEN 2 THEN CONCAT(root.phase_description, ' > ', r.phase_description)
            WHEN 3 THEN CONCAT(root.phase_description, ' > ', r.parent_phase_description, ' > ', r.phase_description)
        END AS phase_path,
        r.phase_status,

        -- ===== Client (denormalized) =====
        r.client_key,
        r.client_description,

        -- ===== Contract & budget (native level -- do not roll up blindly) =====
        r.total_contract_amount,
        r.labor_contract_amount,
        r.expense_contract_amount,
        r.consultant_contract_amount,
        r.labor_cost_budget,
        r.expense_cost_budget,
        r.consultant_cost_budget,
        r.hours_cost_budget,

        -- ===== Progress =====
        r.reported_percent_complete,
        r.reported_percent_complete_date,

        -- ===== Milestone dates =====
        r.estimated_start_date,
        r.estimated_completion_date,
        r.actual_start_date,
        r.actual_completion_date,

        -- ===== Billing =====
        r.billing_type,
        r.rate_table_key,
        r.rate_table_description,

        -- ===== Phase manager (key only) =====
        r.phase_manager_employee_key,

        -- ===== Flags =====
        r.has_valid_phase_key,
        r.is_sub_phase,
        r.has_hours_budget,
        (r.total_contract_amount IS NOT NULL AND r.total_contract_amount > 0) AS has_contract_value

    FROM rooted r
    LEFT JOIN phases root
        ON  r.root_phase_key = root.phase_key
        AND r.project_key    = root.project_key
)

SELECT * FROM final