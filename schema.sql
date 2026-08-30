-- ============================================================================
-- Inno Chem Bangladesh ERP — Production + Sales-cost add-on (combined)
-- ============================================================================
-- Run this ONCE in: Supabase Dashboard -> SQL Editor -> New query -> Run
-- Safe to re-run. Combines:
--   1) Mix Recipes / Production Log tables + product_stock_summary view
--   2) sale_items.cost column for profit/margin tracking
-- ============================================================================

-- ============================================================================
-- Inno Chem Bangladesh ERP — Production / Mix Recipes add-on
-- ============================================================================
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.
-- Requires the base schema (products, purchases, sales, sale_items, audit_log)
-- to already exist.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- MIX RECIPES (BOM)  — one row per component in a finished product's recipe.
-- Several rows share the same finished_product_id (2–6 components typical).
-- ----------------------------------------------------------------------------
create table if not exists product_recipes (
  id                   uuid primary key default gen_random_uuid(),
  finished_product_id  uuid not null references products(id) on delete cascade,
  component_product_id uuid not null references products(id) on delete restrict,
  qty_per_unit         numeric(14,4) not null default 0,   -- qty of component needed per 1 unit of finished product
  sort_order           int not null default 0,
  created_at           timestamptz default now(),
  constraint no_self_mix check (finished_product_id <> component_product_id),
  constraint uq_recipe_component unique (finished_product_id, component_product_id)
);
create index if not exists idx_recipes_finished  on product_recipes (finished_product_id);
create index if not exists idx_recipes_component on product_recipes (component_product_id);

-- ----------------------------------------------------------------------------
-- PRODUCTION BATCHES  — one row per production run (mixing session).
-- ----------------------------------------------------------------------------
create table if not exists production_batches (
  id                  uuid primary key default gen_random_uuid(),
  date                date not null default current_date,
  batch_no            text,
  product_id          uuid references products(id) on delete set null,
  product_name        text not null,                -- snapshot
  qty_produced        numeric(14,3) not null default 0,
  total_material_cost numeric(14,2) not null default 0,
  unit_cost           numeric(14,4) not null default 0,   -- total_material_cost / qty_produced
  notes               text,
  created_at          timestamptz default now()
);
create index if not exists idx_prod_batches_product on production_batches (product_id);
create index if not exists idx_prod_batches_date    on production_batches (date desc);

-- ----------------------------------------------------------------------------
-- PRODUCTION BATCH ITEMS  — the component consumption lines for a batch.
-- ----------------------------------------------------------------------------
create table if not exists production_batch_items (
  id                    uuid primary key default gen_random_uuid(),
  batch_id              uuid not null references production_batches(id) on delete cascade,
  component_product_id  uuid references products(id) on delete set null,
  component_name        text not null,               -- snapshot
  rate                  numeric(14,4) not null default 0,  -- component's avg cost at time of production
  used_qty              numeric(14,3) not null default 0,
  cost                  numeric(14,2) not null default 0   -- rate * used_qty
);
create index if not exists idx_prod_items_batch     on production_batch_items (batch_id);
create index if not exists idx_prod_items_component on production_batch_items (component_product_id);

-- ============================================================================
-- ROW LEVEL SECURITY  (same "anon full access" trade-off as the base schema)
-- ============================================================================
alter table product_recipes        enable row level security;
alter table production_batches     enable row level security;
alter table production_batch_items enable row level security;

drop policy if exists "anon full access" on product_recipes;
drop policy if exists "anon full access" on production_batches;
drop policy if exists "anon full access" on production_batch_items;

create policy "anon full access" on product_recipes        for all using (true) with check (true);
create policy "anon full access" on production_batches     for all using (true) with check (true);
create policy "anon full access" on production_batch_items for all using (true) with check (true);

-- ============================================================================
-- HELPER VIEW: product stock summary — purchases + production − sales − consumption
-- Same formula as the "Mix Inventory Summary" tab in the spreadsheet.
-- Replaces the simpler inventory_live view (products that are only ever
-- purchased, never produced, still work fine — produced/consumed just read 0).
-- ============================================================================
create or replace view product_stock_summary as
select
  p.id,
  p.name,
  p.category,
  p.unit,
  p.opening_stock,
  p.reorder_level,
  coalesce(pur.qty, 0)          as purchase_qty,
  coalesce(pur.amount, 0)       as purchase_amount,
  coalesce(prod.qty, 0)         as produced_qty,
  coalesce(prod.amount, 0)      as produced_amount,
  coalesce(sal.qty, 0)          as sales_qty,
  coalesce(sal.amount, 0)       as sales_amount,
  coalesce(cons.qty, 0)         as consumed_qty,
  p.opening_stock + coalesce(pur.qty,0) + coalesce(prod.qty,0)
    - coalesce(sal.qty,0) - coalesce(cons.qty,0)            as net_stock_qty,
  case when (coalesce(pur.qty,0) + coalesce(prod.qty,0)) > 0
    then (coalesce(pur.amount,0) + coalesce(prod.amount,0))
         / (coalesce(pur.qty,0) + coalesce(prod.qty,0))
    else 0
  end as avg_cost
from products p
left join (
  select product_id, sum(qty) as qty, sum(total) as amount
  from purchases group by product_id
) pur on pur.product_id = p.id
left join (
  select product_id, sum(qty_produced) as qty, sum(total_material_cost) as amount
  from production_batches group by product_id
) prod on prod.product_id = p.id
left join (
  select product_id, sum(qty) as qty, sum(amount) as amount
  from sale_items group by product_id
) sal on sal.product_id = p.id
left join (
  select component_product_id as product_id, sum(used_qty) as qty
  from production_batch_items group by component_product_id
) cons on cons.product_id = p.id;

-- ============================================================================
-- SALES COST/PROFIT TIE-IN — captures each sale line's cost basis (the
-- product's average cost at the moment it was sold) so profit/margin can be
-- shown per sale, without recalculating historical sales when costs change later.
-- ============================================================================
alter table sale_items add column if not exists cost numeric(14,4) not null default 0;


-- ============================================================================
-- Inno Chem Bangladesh ERP — Sales cost/profit tracking add-on
-- ============================================================================
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run: uses "add column if not exists".
-- ============================================================================

-- Stores each sale line item's unit cost (its average cost at the moment of
-- sale — whether purchased, produced via a mix recipe, or both). The app
-- uses this to show Unit Cost / Total Cost / Profit / Margin per sale.
alter table sale_items
  add column if not exists cost numeric(14,4) not null default 0;
