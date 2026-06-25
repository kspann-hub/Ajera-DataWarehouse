{{
  config(
    materialized = 'table',
    schema = 'ajera_silver'
  )
}}

-- ============================================================
-- slv_project_phases
-- Grain: one row per phase, at ANY level of the hierarchy
--        (level 1 stages, level 2 sub-phases, level 3 sub-sub-phases).
--
-- Bronze -> silver:
--   Ajera nests phases recursively under InvoiceGroups:
--     InvoiceGroups[].Phases[]                   -> level 1
--     InvoiceGroups[].Phases[].Phases[]          -> level 2
--     InvoiceGroups[].Phases[].Phases[].Phases[] -> level 3 (deepest; no level 4)
--   Each level is flattened separately and UNION ALL'd into one phase table.
--   Every row carries phase_level (1/2/3) and parent_phase_key
--   (NULL at level 1; the parent phase's key at levels 2/3) so the full
--   tree is preserved and children can be rolled up to parents in gold.
--
--   Verified counts: L1=1044, L2=3007, L3=258  -> ~4309 rows.
--   This is required: ~2,889 timesheet rows log time against level-2/3
--   phase keys that a level-1-only table could not resolve.
--
--   project_key / invoice_group_key / client_* are denormalized onto
--   every phase row. Inner UNNEST: phases with no children simply
--   produce no deeper-level rows. Hours live in slv_timesheet_project_daily
--   and join here on phase_key; rolling children up to a parent is gold.
-- ============================================================

WITH

source AS (
    SELECT *
    FROM {{ source('ajera_bronze', 'raw_projects_detailed') }}
),

-- ===== Level 1: top-level phases (stages) =====
phases_l1 AS (
    SELECT
        -- Identity & hierarchy
        p.ProjectKey                          AS project_key,
        ig.InvoiceGroupKey                    AS invoice_group_key,
        ph.PhaseKey                           AS phase_key,
        CAST(NULL AS INT64)                   AS parent_phase_key,
        1                                     AS phase_level,
        ph.ID                                 AS phase_id,
        ph.Description                         AS phase_description,
        ph.Status                             AS phase_status,
        -- Client (denormalized)
        ig.Client.ClientKey                   AS client_key,
        ig.Client.Description                 AS client_description,
        -- Contract & budget
        ph.TotalContractAmount                AS total_contract_amount,
        ph.LaborContractAmount                AS labor_contract_amount,
        ph.ExpenseContractAmount              AS expense_contract_amount,
        ph.ConsultantContractAmount           AS consultant_contract_amount,
        ph.LaborCostBudget                    AS labor_cost_budget,
        ph.ExpenseCostBudget                  AS expense_cost_budget,
        ph.ConsultantCostBudget               AS consultant_cost_budget,
        ph.HoursCostBudget                    AS hours_cost_budget,
        -- Progress
        ph.ReportedPercentComplete            AS reported_percent_complete,
        ph.ReportedPercentCompleteDate        AS reported_percent_complete_date,
        -- Milestone dates
        ph.EstimatedStartDate                 AS estimated_start_date,
        ph.EstimatedCompletionDate            AS estimated_completion_date,
        ph.ActualStartDate                    AS actual_start_date,
        ph.ActualCompletionDate               AS actual_completion_date,
        -- Billing
        ph.BillingType                        AS billing_type,
        ph.BillLaborAsTE                      AS bill_labor_as_te,
        ph.BillExpenseAsTE                    AS bill_expense_as_te,
        ph.BillConsultantAsTE                 AS bill_consultant_as_te,
        ph.RateTableKey                       AS rate_table_key,
        ph.RateTableDescription               AS rate_table_description,
        -- Phase manager (flattened)
        ph.ProjectManager.EmployeeKey         AS phase_manager_employee_key,
        ph.ProjectManager.LastName            AS phase_manager_last_name,
        ph.ProjectManager.FirstName           AS phase_manager_first_name,
        -- Custom fields
        ph.CF_ProjectLocation.Value           AS cf_project_location,
        ph.CF_SquareFootage                   AS cf_square_footage,
        -- Flags
        ph.IsFinalBudget                      AS is_final_budget,
        ph.IsCertified                        AS is_certified,
        ph.IsBillingGroup                     AS is_billing_group,
        -- Audit
        SAFE_CAST(ph.LastModifiedDate AS TIMESTAMP) AS source_last_modified_at
    FROM source p,
        UNNEST(p.InvoiceGroups) AS ig,
        UNNEST(ig.Phases)       AS ph
),

-- ===== Level 2: sub-phases (parent = level-1 phase) =====
phases_l2 AS (
    SELECT
        p.ProjectKey                          AS project_key,
        ig.InvoiceGroupKey                    AS invoice_group_key,
        ph2.PhaseKey                          AS phase_key,
        ph.PhaseKey                           AS parent_phase_key,
        2                                     AS phase_level,
        ph2.ID                                AS phase_id,
        ph2.Description                        AS phase_description,
        ph2.Status                            AS phase_status,
        ig.Client.ClientKey                   AS client_key,
        ig.Client.Description                 AS client_description,
        ph2.TotalContractAmount               AS total_contract_amount,
        ph2.LaborContractAmount               AS labor_contract_amount,
        ph2.ExpenseContractAmount             AS expense_contract_amount,
        ph2.ConsultantContractAmount          AS consultant_contract_amount,
        ph2.LaborCostBudget                   AS labor_cost_budget,
        ph2.ExpenseCostBudget                 AS expense_cost_budget,
        ph2.ConsultantCostBudget              AS consultant_cost_budget,
        ph2.HoursCostBudget                   AS hours_cost_budget,
        ph2.ReportedPercentComplete           AS reported_percent_complete,
        ph2.ReportedPercentCompleteDate       AS reported_percent_complete_date,
        ph2.EstimatedStartDate                AS estimated_start_date,
        ph2.EstimatedCompletionDate           AS estimated_completion_date,
        ph2.ActualStartDate                   AS actual_start_date,
        ph2.ActualCompletionDate              AS actual_completion_date,
        ph2.BillingType                       AS billing_type,
        ph2.BillLaborAsTE                     AS bill_labor_as_te,
        ph2.BillExpenseAsTE                   AS bill_expense_as_te,
        ph2.BillConsultantAsTE                AS bill_consultant_as_te,
        ph2.RateTableKey                      AS rate_table_key,
        ph2.RateTableDescription              AS rate_table_description,
        ph2.ProjectManager.EmployeeKey        AS phase_manager_employee_key,
        ph2.ProjectManager.LastName           AS phase_manager_last_name,
        ph2.ProjectManager.FirstName          AS phase_manager_first_name,
        ph2.CF_ProjectLocation.Value          AS cf_project_location,
        ph2.CF_SquareFootage                  AS cf_square_footage,
        ph2.IsFinalBudget                     AS is_final_budget,
        ph2.IsCertified                       AS is_certified,
        ph2.IsBillingGroup                    AS is_billing_group,
        SAFE_CAST(ph2.LastModifiedDate AS TIMESTAMP) AS source_last_modified_at
    FROM source p,
        UNNEST(p.InvoiceGroups) AS ig,
        UNNEST(ig.Phases)       AS ph,
        UNNEST(ph.Phases)       AS ph2
),

-- ===== Level 3: sub-sub-phases (parent = level-2 phase) =====
phases_l3 AS (
    SELECT
        p.ProjectKey                          AS project_key,
        ig.InvoiceGroupKey                    AS invoice_group_key,
        ph3.PhaseKey                          AS phase_key,
        ph2.PhaseKey                          AS parent_phase_key,
        3                                     AS phase_level,
        ph3.ID                                AS phase_id,
        ph3.Description                        AS phase_description,
        ph3.Status                            AS phase_status,
        ig.Client.ClientKey                   AS client_key,
        ig.Client.Description                 AS client_description,
        ph3.TotalContractAmount               AS total_contract_amount,
        ph3.LaborContractAmount               AS labor_contract_amount,
        ph3.ExpenseContractAmount             AS expense_contract_amount,
        ph3.ConsultantContractAmount          AS consultant_contract_amount,
        ph3.LaborCostBudget                   AS labor_cost_budget,
        ph3.ExpenseCostBudget                 AS expense_cost_budget,
        ph3.ConsultantCostBudget              AS consultant_cost_budget,
        ph3.HoursCostBudget                   AS hours_cost_budget,
        ph3.ReportedPercentComplete           AS reported_percent_complete,
        ph3.ReportedPercentCompleteDate       AS reported_percent_complete_date,
        ph3.EstimatedStartDate                AS estimated_start_date,
        ph3.EstimatedCompletionDate           AS estimated_completion_date,
        ph3.ActualStartDate                   AS actual_start_date,
        ph3.ActualCompletionDate              AS actual_completion_date,
        ph3.BillingType                       AS billing_type,
        ph3.BillLaborAsTE                     AS bill_labor_as_te,
        ph3.BillExpenseAsTE                   AS bill_expense_as_te,
        ph3.BillConsultantAsTE                AS bill_consultant_as_te,
        ph3.RateTableKey                      AS rate_table_key,
        ph3.RateTableDescription              AS rate_table_description,
        ph3.ProjectManager.EmployeeKey        AS phase_manager_employee_key,
        ph3.ProjectManager.LastName           AS phase_manager_last_name,
        ph3.ProjectManager.FirstName          AS phase_manager_first_name,
        ph3.CF_ProjectLocation.Value          AS cf_project_location,
        ph3.CF_SquareFootage                  AS cf_square_footage,
        ph3.IsFinalBudget                     AS is_final_budget,
        ph3.IsCertified                       AS is_certified,
        ph3.IsBillingGroup                    AS is_billing_group,
        SAFE_CAST(ph3.LastModifiedDate AS TIMESTAMP) AS source_last_modified_at
    FROM source p,
        UNNEST(p.InvoiceGroups) AS ig,
        UNNEST(ig.Phases)       AS ph,
        UNNEST(ph.Phases)       AS ph2,
        UNNEST(ph2.Phases)      AS ph3
),

all_phases AS (
    SELECT * FROM phases_l1
    UNION ALL
    SELECT * FROM phases_l2
    UNION ALL
    SELECT * FROM phases_l3
)

SELECT
    *,
    -- Quality flags
    (phase_key IS NOT NULL)                  AS has_valid_phase_key,
    (parent_phase_key IS NOT NULL)           AS is_sub_phase,
    (hours_cost_budget IS NOT NULL AND hours_cost_budget > 0) AS has_hours_budget
FROM all_phases