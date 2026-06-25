{{
  config(
    materialized = 'table',
    schema = 'ajera_gold'
  )
}}

-- ============================================================
-- gold_projects
-- Grain: one row per project (project_key)
--
-- Curated project dimension for Retool / reporting.
-- Straight projection of slv_projects, limited to the columns
-- marked "keep for gold". No business logic, no aggregation.
-- project_id intentionally excluded (sparse, free-text, silver-only).
-- ============================================================

WITH gold AS (
    SELECT
        -- ===== Identity =====
        project_key,
        project_description,
        project_status,

        -- ===== Classification =====
        project_type_key,
        project_type_description,
        project_location,

        -- ===== Contract & budget =====
        total_contract_amount,
        labor_contract_amount,
        expense_contract_amount,
        consultant_contract_amount,
        labor_cost_budget,
        expense_cost_budget,
        consultant_cost_budget,
        hours_cost_budget,

        -- ===== Progress =====
        reported_percent_complete,
        reported_percent_complete_date,

        -- ===== Milestone dates =====
        estimated_start_date,
        estimated_completion_date,
        actual_start_date,
        actual_completion_date,

        -- ===== Billing =====
        billing_type,
        bill_labor_as_te,
        rate_table_key,
        rate_table_description,

        -- ===== Managers (keys only) =====
        project_manager_employee_key,
        principal_in_charge_employee_key,
        marketing_contact_employee_key,

        -- ===== Quality flags =====
        has_valid_project_key,
        has_contract_value,
        has_actual_start

    FROM {{ ref('slv_projects') }}
)

SELECT * FROM gold