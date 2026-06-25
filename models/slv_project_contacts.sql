/*
  Model:   slv_project_contacts
  Layer:   silver (ajera_silver)
  Grain:   one row per project x external contact -> (project_key, contact_key)
  Source:  source('ajera_bronze','raw_project_totals'), UNNEST(Contacts)
  Purpose: faithful silver of the project Contacts[] array (external parties:
           carry contact_key + company, distinct from internal staff structs).

  Profile at load (215 projects): 88 projects have contacts; 91 contact rows total.
    Fully populated: contact_order, first_name, last_name, company, contact_key (91/91).
    Partial: title (75/91).
    Empty as of this load (kept per flag-don't-filter): middle_name, contact_text (0/91).

  id: deterministic surrogate for Retool ('<project_key>-<contact_key>').
*/

{{ config(schema='ajera_silver', materialized='table') }}

with source as (

    select * from {{ source('ajera_bronze', 'raw_project_totals') }}

),

unnested as (

    select
    s.ProjectKey as project_key,
    c.`Order` as contact_order,
    c.Title as title,
    c.LastName as last_name,
    c.FirstName as first_name,
    c.Company as company,
    c.Text as contact_text,
    c.MiddleName as middle_name,
    c.ContactKey as contact_key

    from source as s, unnest(s.Contacts) as c

),

final as (

    select
        concat(cast(project_key as string), '-', cast(contact_key as string)) as id,
        *
    from unnested

)

select * from final