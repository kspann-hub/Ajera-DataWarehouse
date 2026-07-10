{{
  config(
    materialized = 'table',
    schema = 'ajera_gold'
  )
}}

WITH employees AS (
    SELECT * FROM {{ ref('slv_employees') }}
)

SELECT
    employee_id AS ajera_employee_key,
    CONCAT(first_name, ' ', last_name) AS full_name,
    employee_title,
    employee_type_description,
    employment_status,
    employee_email,
    is_project_manager,
    is_accounting_manager,
    is_supervisor,
    employee_supervisor_id AS supervisor_employee_key
FROM employees