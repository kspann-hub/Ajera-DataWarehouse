/*
  Model:   slv_project_invoice_groups
  Layer:   silver (ajera_silver)
  Grain:   one row per project x invoice group -> (project_key, invoice_group_key)
  Source:  source('ajera_bronze','raw_project_totals'), UNNEST(InvoiceGroups)
  Purpose: faithful silver of the invoice-group BILLING METADATA only.

  Note (verified against the bronze type): the InvoiceGroup struct has 18 top-level
  fields = 3 person/client structs (flattened) + 14 metadata scalars + the Phases[]
  array. There are NO financial roll-ups at the group level; all phase financials
  live inside InvoiceGroups.Phases and are modeled separately in
  slv_invoice_group_phases. This table therefore carries zero $ measures by design.

  id: deterministic surrogate for Retool ('<project_key>-<invoice_group_key>').
*/

{{ config(schema='ajera_silver', materialized='table') }}

with source as (

    select * from {{ source('ajera_bronze', 'raw_project_totals') }}

),

unnested as (

    select
    s.ProjectKey as project_key,
    ig.InvoiceGroupKey as invoice_group_key,
    ig.BillingContact.LastName as billing_contact_last_name,
    ig.BillingContact.FirstName as billing_contact_first_name,
    ig.BillingContact.Company as billing_contact_company,
    ig.BillingContact.MiddleName as billing_contact_middle_name,
    ig.BillingContact.ContactKey as billing_contact_contact_key,
    ig.Client.Description as client_description,
    ig.Client.ClientKey as client_key,
    ig.InvoiceHeaderText as invoice_header_text,
    ig.Notes as notes,
    ig.EmailClientStatementTemplateKey as email_client_statement_template_key,
    ig.BillingManager.LastName as billing_manager_last_name,
    ig.BillingManager.FirstName as billing_manager_first_name,
    ig.BillingManager.MiddleName as billing_manager_middle_name,
    ig.BillingManager.EmployeeKey as billing_manager_employee_key,
    ig.EmailInvoiceTemplateKey as email_invoice_template_key,
    ig.PrintBackup as print_backup,
    ig.InvoiceFooterText as invoice_footer_text,
    ig.EmailInvoiceTemplateDescription as email_invoice_template_description,
    ig.EmailIncludeBackup as email_include_backup,
    ig.EmailClientStatementTemplateDescription as email_client_statement_template_description,
    ig.InvoiceScope as invoice_scope,
    ig.InvoiceFormatDescription as invoice_format_description,
    ig.InvoiceFormatKey as invoice_format_key,
    ig.Description as description

    from source as s, unnest(s.InvoiceGroups) as ig

),

final as (

    select
        concat(cast(project_key as string), '-', cast(invoice_group_key as string)) as id,
        *
    from unnested

)

select * from final