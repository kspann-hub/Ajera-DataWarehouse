/*
  Model:   slv_project_totals
  Layer:   silver (ajera_silver)
  Grain:   one row per project  -> project_key (also natural string key: id)
  Source:  source('ajera_bronze','raw_project_totals') -- append-only raw landing; nested ARRAY/STRUCT preserved
  Purpose: faithful silver of the project-level fields from raw_project_totals.
           Typed, standardized, single-value structs flattened. No business logic,
           no grain change, no CURRENT_DATE math (those live in gold).

  Decisions / flags (decision log):
    - InvoiceGroups[] and Contacts[] are arrays -> excluded here; modeled as
      slv_project_invoice_groups and slv_project_contacts respectively.
    - Person structs (PrincipalInCharge / ProjectManager / MarketingContact)
      flattened to 4 columns each; display-name concat deferred to gold.
    - CF_* wrapper structs reduced to .Value. The .Values (dropdown options) and
      .AllowEdit (UI permission) are interface metadata, not project facts -> dropped.
    - "+" in source names rendered as "_plus_" (e.g. cost_plus_premium_burdened).
    - LastModifiedDate is STRING in bronze -> parsed to TIMESTAMP last_modified_at.
      VERIFY the source string format before trusting it (SAFE parse -> NULL on miss):
        select last_modified_date_raw from ... limit 5;  (see TODO below)
*/

{{ config(schema='ajera_silver', materialized='table') }}

with source as (

    select * from {{ source('ajera_bronze', 'raw_project_totals') }}

),

renamed as (

    select
    ProjectKey as project_key,
    ID as id,
    CompanyKey as company_key,
    ConstructionCost as construction_cost,
    ExpenseContractAmount as expense_contract_amount,
    LaborContractAmount as labor_contract_amount,
    TotalContractAmount as total_contract_amount,
    `Written off Expense` as written_off_expense,
    `Written off Consultant` as written_off_consultant,
    WIP as wip,
    `WIP Expense` as wip_expense,
    `WIP Consultant` as wip_consultant,
    Spent as spent,
    `Spent Consultant` as spent_consultant,
    `Scheduled Dollars` as scheduled_dollars,
    Receipts as receipts,
    `Receipts Expense` as receipts_expense,
    `Receipts Credit Memo Labor` as receipts_credit_memo_labor,
    `Receipts Credit Memo Expense` as receipts_credit_memo_expense,
    ReportedPercentCompleteDate as reported_percent_complete_date,
    `Receipts Credit Memo Consultant` as receipts_credit_memo_consultant,
    `Receipts Consultant` as receipts_consultant,
    BillConsultantAsTE as bill_consultant_as_te,
    Status as status,
    `Consultant Billed by Accounting Date` as consultant_billed_by_accounting_date,
    `Receipts Adjustments Labor` as receipts_adjustments_labor,
    `Payments Expense` as payments_expense,
    `Regular Hours Worked` as regular_hours_worked,
    `Labor Billed by Accounting Date` as labor_billed_by_accounting_date,
    `Expense Billed by Accounting Date` as expense_billed_by_accounting_date,
    `Vendor Invoiced` as vendor_invoiced,
    Cost as cost,
    `Receivable Balance` as receivable_balance,
    WageTableKey as wage_table_key,
    `Cost + Premium Burdened` as cost_plus_premium_burdened,
    ReportedPercentComplete as reported_percent_complete,
    Billed as billed,
    TaxState as tax_state,
    `Billed Expense` as billed_expense,
    `Billed Amount By Accounting Date` as billed_amount_by_accounting_date,
    `Cost Labor + Premium` as cost_labor_plus_premium,
    `Billed Adjustments` as billed_adjustments,
    `Billed Adjustments Consultant` as billed_adjustments_consultant,
    `Written off Hours` as written_off_hours,
    BudgetedOverheadRate as budgeted_overhead_rate,
    `WIP Hours` as wip_hours,
    `Receipts Adjustments Expense` as receipts_adjustments_expense,
    `Premium 2 Hours Worked` as premium_2_hours_worked,
    `Premium 3 Hours Worked` as premium_3_hours_worked,
    `Receipts Adjustments` as receipts_adjustments,
    `Premium 1 Hours Worked` as premium_1_hours_worked,
    `Cost Labor + Premium Burdened` as cost_labor_plus_premium_burdened,
    LockFee as lock_fee,
    `Billed Adjustments Labor` as billed_adjustments_labor,
    RestrictTimeEntryToResourcesOnly as restrict_time_entry_to_resources_only,
    `Billed Hours` as billed_hours,
    `Resource Hours` as resource_hours,
    BillExpenseAsTE as bill_expense_as_te,
    CF_RequiresCustomFormat as cf_requires_custom_format,
    CF_ProjectSetupReviewedBy.Value as cf_project_setup_reviewed_by,
    `Written off Labor` as written_off_labor,
    CF_ClientBillingInstructions as cf_client_billing_instructions,
    CF_ProjectLocation.Value as cf_project_location,
    Description as description,
    `Hours Worked` as hours_worked,
    CF_ProjectUsesParttimeEmployees as cf_project_uses_parttime_employees,
    `Receipts Sales Tax` as receipts_sales_tax,
    CF_SquareFootage as cf_square_footage,
    `WIP Labor` as wip_labor,
    `Scheduled Hours` as scheduled_hours,
    `Vendor Invoiced Expense` as vendor_invoiced_expense,
    CompanyDescription as company_description,
    `Spent Expense` as spent_expense,
    RateTableDescription as rate_table_description,
    SalesTaxCode as sales_tax_code,
    ExpenseConsultantEntry as expense_consultant_entry,
    ExpenseCostBudget as expense_cost_budget,
    safe.parse_timestamp('%Y-%m-%d %H:%M:%E*S',
      regexp_extract(LastModifiedDate, r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+')) as last_modified_at,
    TaxLocalKey as tax_local_key,
    HoursCostBudget as hours_cost_budget,
    `Cost Labor` as cost_labor,
    Notes as notes,
    ApplySalesTax as apply_sales_tax,
    `Payments Consultant` as payments_consultant,
    ActualStartDate as actual_start_date,
    `Cost Burdened` as cost_burdened,
    `Billed Labor` as billed_labor,
    RequireTimesheetNotes as require_timesheet_notes,
    IsFinalBudget as is_final_budget,
    PercentDistribution as percent_distribution,
    `Receipts Adjustments Consultant` as receipts_adjustments_consultant,
    EstimatedStartDate as estimated_start_date,
    `Billed Consultant` as billed_consultant,
    `Spent Labor` as spent_labor,
    TaxLocalDescription as tax_local_description,
    `Written off` as written_off,
    `Vendor Invoiced Consultant` as vendor_invoiced_consultant,
    `Receipts Labor` as receipts_labor,
    LaborCostBudget as labor_cost_budget,
    `Cost Labor Burdened` as cost_labor_burdened,
    SalesTaxRate as sales_tax_rate,
    ProjectTypeKey as project_type_key,
    BillingType as billing_type,
    ConsultantContractAmount as consultant_contract_amount,
    Payments as payments,
    SummarizeBillingGroup as summarize_billing_group,
    ProjectTypeDescription as project_type_description,
    PercentOfConstructionCost as percent_of_construction_cost,
    SyncToCRM as sync_to_crm,
    LaborEntry as labor_entry,
    Location as location,
    PrincipalInCharge.LastName as principal_in_charge_last_name,
    PrincipalInCharge.FirstName as principal_in_charge_first_name,
    PrincipalInCharge.MiddleName as principal_in_charge_middle_name,
    PrincipalInCharge.EmployeeKey as principal_in_charge_employee_key,
    `Payable Balance` as payable_balance,
    ConsultantCostBudget as consultant_cost_budget,
    `Cost Consultant` as cost_consultant,
    DepartmentDescription as department_description,
    EstimatedCompletionDate as estimated_completion_date,
    DepartmentKey as department_key,
    `Receipts Credit Memo` as receipts_credit_memo,
    `Cost + Premium` as cost_plus_premium,
    ProjectManager.LastName as project_manager_last_name,
    ProjectManager.FirstName as project_manager_first_name,
    ProjectManager.MiddleName as project_manager_middle_name,
    ProjectManager.EmployeeKey as project_manager_employee_key,
    `Billed Sales Tax` as billed_sales_tax,
    WageTableDescription as wage_table_description,
    MarketingContact.LastName as marketing_contact_last_name,
    MarketingContact.FirstName as marketing_contact_first_name,
    MarketingContact.MiddleName as marketing_contact_middle_name,
    MarketingContact.EmployeeKey as marketing_contact_employee_key,
    `Billed Adjustments Expense` as billed_adjustments_expense,
    BillingDescription as billing_description,
    ActualCompletionDate as actual_completion_date,
    CRMFinalSync as crm_final_sync,
    RateTableKey as rate_table_key,
    BillLaborAsTE as bill_labor_as_te,
    IsCertified as is_certified,
    CreateInCRM as create_in_crm,
    `Cost Expense` as cost_expense

    from source

)

select * from renamed