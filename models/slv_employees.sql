{{
  config(
    materialized = 'table',
    schema = 'ajera_silver'
  )
}}

WITH raw_employees AS (
    SELECT * FROM {{ source('ajera_bronze', 'raw_employees_detailed') }}
)

SELECT 
    EmployeeKey AS employee_id,
    FirstName AS first_name,
    LastName AS last_name,
    Title AS employee_title,
    EmployeeTypeDescription AS employee_type_description,
    EmployeeTypeKey as employee_type_id,
    DateHired AS hire_date, 
    Status AS employment_status,
    IsAccountingManager AS is_accounting_manager,
    IsProjectManager AS is_project_manager,
    IsSupervisor AS is_supervisor,
    IsPrincipal AS is_principal,
    SupervisorKey as employee_supervisor_id,
    IsMarketingContact AS is_marketing_contact,
    Email AS employee_email
FROM raw_employees