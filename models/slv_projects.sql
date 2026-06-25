{{
  config(
    materialized = 'table',
    schema = 'ajera_silver'
  )
}}

-- ============================================================
-- slv_projects
-- Grain: one row per project (project_key)
--
-- Bronze -> silver:
--   - Project-level scalars only; the nested InvoiceGroups array
--     is dropped here and handled by slv_project_phases.
--   - Manager STRUCTs flattened to convenience columns (Retool ergonomics).
--   - Type cast (LastModifiedDate STRING -> TIMESTAMP via SAFE_CAST),
--     snake_case, _key convention.
--   - Quality flags, no business logic, no CURRENT_DATE() (that's gold).
--
-- Validate: confirm one row per project_key before trusting joins.
-- ============================================================

WITH

source AS (
    SELECT *
    FROM {{ source('ajera_bronze', 'raw_projects_detailed') }}
),

cleaned AS (
    SELECT
        -- ===== Identity =====
        p.ProjectKey                              AS project_key,
        p.ID                                      AS project_id,
        p.Description                             AS project_description,
        p.Status                                  AS project_status,

        -- ===== Classification =====
        p.ProjectTypeKey                          AS project_type_key,
        p.ProjectTypeDescription                  AS project_type_description,
        p.DepartmentKey                           AS department_key,
        p.DepartmentDescription                   AS department_description,
        p.CompanyKey                              AS company_key,
        p.CompanyDescription                      AS company_description,
        p.Location                                AS project_location,

        -- ===== Contract & budget ($) =====
        p.TotalContractAmount                     AS total_contract_amount,
        p.LaborContractAmount                     AS labor_contract_amount,
        p.ExpenseContractAmount                   AS expense_contract_amount,
        p.ConsultantContractAmount                AS consultant_contract_amount,
        p.LaborCostBudget                         AS labor_cost_budget,
        p.ExpenseCostBudget                       AS expense_cost_budget,
        p.ConsultantCostBudget                    AS consultant_cost_budget,
        p.HoursCostBudget                         AS hours_cost_budget,
        p.ConstructionCost                        AS construction_cost,
        p.PercentOfConstructionCost               AS percent_of_construction_cost,
        p.BudgetedOverheadRate                    AS budgeted_overhead_rate,

        -- ===== Progress =====
        p.ReportedPercentComplete                 AS reported_percent_complete,
        p.ReportedPercentCompleteDate             AS reported_percent_complete_date,

        -- ===== Milestone dates =====
        p.EstimatedStartDate                      AS estimated_start_date,
        p.EstimatedCompletionDate                 AS estimated_completion_date,
        p.ActualStartDate                         AS actual_start_date,
        p.ActualCompletionDate                    AS actual_completion_date,

        -- ===== Billing & tax =====
        p.BillingType                             AS billing_type,
        p.BillLaborAsTE                           AS bill_labor_as_te,
        p.BillExpenseAsTE                         AS bill_expense_as_te,
        p.BillConsultantAsTE                      AS bill_consultant_as_te,
        p.ApplySalesTax                           AS apply_sales_tax,
        p.SalesTaxRate                            AS sales_tax_rate,
        p.SalesTaxCode                            AS sales_tax_code,
        p.TaxState                                AS tax_state,
        p.RateTableKey                            AS rate_table_key,
        p.RateTableDescription                    AS rate_table_description,
        p.WageTableKey                            AS wage_table_key,
        p.WageTableDescription                    AS wage_table_description,

        -- ===== Flags =====
        p.IsCertified                             AS is_certified,
        p.IsFinalBudget                           AS is_final_budget,
        p.LockFee                                 AS lock_fee,
        p.RequireTimesheetNotes                   AS require_timesheet_notes,
        p.RestrictTimeEntryToResourcesOnly        AS restrict_time_entry_to_resources_only,
        p.LaborEntry                              AS labor_entry,
        p.ExpenseConsultantEntry                  AS expense_consultant_entry,
        p.SummarizeBillingGroup                   AS summarize_billing_group,

        -- ===== Managers (flattened from STRUCTs) =====
        p.ProjectManager.EmployeeKey              AS project_manager_employee_key,
        p.ProjectManager.LastName                 AS project_manager_last_name,
        p.ProjectManager.FirstName                AS project_manager_first_name,
        p.PrincipalInCharge.EmployeeKey           AS principal_in_charge_employee_key,
        p.PrincipalInCharge.LastName              AS principal_in_charge_last_name,
        p.PrincipalInCharge.FirstName             AS principal_in_charge_first_name,
        p.MarketingContact.EmployeeKey            AS marketing_contact_employee_key,
        p.MarketingContact.LastName               AS marketing_contact_last_name,
        p.MarketingContact.FirstName              AS marketing_contact_first_name,

        -- ===== Custom fields (flattened; .Value of the custom-field object) =====
        p.CF_ProjectLocation.Value                AS cf_project_location,
        p.CF_SquareFootage                        AS cf_square_footage,
        p.CF_ProjectUsesParttimeEmployees         AS cf_uses_parttime_employees,
        p.CF_RequiresCustomFormat                 AS cf_requires_custom_format,
        p.CF_ClientBillingInstructions            AS cf_client_billing_instructions,
        p.CF_ProjectSetupReviewedBy.Value         AS cf_project_setup_reviewed_by,

        -- ===== Notes & audit =====
        p.Notes                                   AS project_notes,
        SAFE_CAST(p.LastModifiedDate AS TIMESTAMP) AS source_last_modified_at

    FROM source p
),

final AS (
    SELECT
        *,
        -- Quality flags (flag, don't filter)
        (project_key IS NOT NULL)                                   AS has_valid_project_key,
        (total_contract_amount IS NOT NULL AND total_contract_amount > 0) AS has_contract_value,
        (actual_start_date IS NOT NULL)                             AS has_actual_start
    FROM cleaned
)

SELECT * FROM final