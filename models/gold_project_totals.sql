{{ config(materialized='table', schema='ajera_gold') }}

-- ============================================================
-- gold_project_financials
-- Grain: one row per project -> project_key
--        (inherited unchanged from slv_project_totals; no fanout,
--         no aggregation, pure curated projection)
--
-- Purpose: the money-movement panel for the project command center.
--   gold_projects already owns contract amounts, cost budgets, %
--   complete, dates, PM/principal, status. This model fills the gap:
--   WIP -> spent/cost -> billed -> received -> outstanding.
--   Joins to gold_projects on project_key for contract/budget context.
--
-- Values are LIVE current-state (WIP/billed move daily). Correct for a
--   nightly-rebuilt mart mirror; NOT a point-in-time history.
--
-- SPEND DEFINITION (open, Finance to rule): spent / cost / cost_burdened
--   are all carried. Deltek treats these differently (consumed vs. raw
--   cost vs. burdened cost). B. Agosta names the canonical "spend";
--   until then, all three ship so Retool can point at the blessed one.
--
-- Materialization: table.
-- ============================================================

WITH financials AS (

    SELECT
        project_key,

        -- Work in progress (unbilled)
        wip,
        wip_labor,
        wip_expense,
        wip_consultant,

        -- Cost incurred (see SPEND DEFINITION note)
        spent,
        spent_labor,
        spent_expense,
        spent_consultant,
        cost,
        cost_burdened,

        -- Invoiced
        billed,
        billed_labor,
        billed_expense,
        billed_consultant,

        -- Cash received
        receipts,
        receipts_labor,
        receipts_expense,
        receipts_consultant,

        -- Outstanding AR
        receivable_balance,

        -- Planned + effort
        scheduled_dollars,
        regular_hours_worked,
        hours_worked,

        -- Key quality flag (flag, don't filter)
        project_key IS NOT NULL AS has_valid_project_key

    FROM {{ ref('slv_project_totals') }}

)

SELECT * FROM financials