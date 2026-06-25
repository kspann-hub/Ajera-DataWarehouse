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
    EmployeeTypeDescription AS employee_type, 
    Status AS employment_status, 
    DepartmentKey AS department_name
FROM raw_employees