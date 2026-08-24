-- ============================================================================
-- Inno Chem Bangladesh ERP — Supabase / Postgres schema
-- ============================================================================
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.
-- ============================================================================

create extension if not exists "pgcrypto"; -- for gen_random_uuid()

-- ----------------------------------------------------------------------------
-- BUSINESS PROFILE  (single row — shown on every receipt/statement header)
-- ----------------------------------------------------------------------------
create table if not exists business_profile (
  id          int primary key default 1,
  name        text default 'Inno Chem Bangladesh',
  tagline     text default 'Your Textile Partner',
  address     text,
  phone       text,
  email       text,
  bin         text,
  updated_at  timestamptz default now(),
  constraint single_row check (id = 1)
);
insert into business_profile (id) values (1) on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- USERS  (app-level accounts — see README "Security" section before relying
-- on this for anything beyond an internal/trusted-network tool)
-- ----------------------------------------------------------------------------
create table if not exists app_users (
  id            uuid primary key default gen_random_uuid(),
  username      text unique not null,
  password      text not null,          -- stored in plain text — see README security note
  role          text not null default 'staff' check (role in ('admin','staff')),
  permissions   jsonb not null default '{}'::jsonb,  -- { companies: {view,edit}, sales: {view,edit}, ... }
  created_at    timestamptz default now()
);
create index if not exists idx_app_users_username on app_users (username);

-- ----------------------------------------------------------------------------
-- COMPANIES  (buyers / suppliers / both)
-- ----------------------------------------------------------------------------
create table if not exists companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  type        text not null default 'Supplier' check (type in ('Supplier','Buyer','Both')),
  opening     numeric(14,2) not null default 0,   -- opening balance; +ve = they owe you
  contact     text,
  phone       text,
  email       text,
  address     text,
  notes       text,
  created_at  timestamptz default now()
);
create index if not exists idx_companies_name  on companies (name);
create index if not exists idx_companies_type  on companies (type);
create index if not exists idx_companies_phone on companies (phone);

-- ----------------------------------------------------------------------------
-- PRODUCTS  (chemical catalogue)
-- ----------------------------------------------------------------------------
create table if not exists products (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  category       text,
  unit           text not null default 'kg',
  opening_stock  numeric(14,3) not null default 0,
  purchase_rate  numeric(14,2) not null default 0,
  sales_rate     numeric(14,2) not null default 0,
  reorder_level  numeric(14,3) default 0,
  notes          text,
  created_at     timestamptz default now()
);
create index if not exists idx_products_name     on products (name);
create index if not exists idx_products_category on products (category);

-- ----------------------------------------------------------------------------
-- PURCHASES  (one product per purchase line, supplier-facing)
-- ----------------------------------------------------------------------------
create table if not exists purchases (
  id           uuid primary key default gen_random_uuid(),
  date         date not null default current_date,
  invoice_no   text,
  company_id   uuid references companies(id) on delete set null,
  company_name text not null,                 -- snapshot, survives company deletion
  product_id   uuid references products(id) on delete set null,
  product_name text not null,                 -- snapshot
  qty          numeric(14,3) not null default 0,
  rate         numeric(14,2) not null default 0,
  total        numeric(14,2) not null default 0,
  paid         numeric(14,2) not null default 0,
  due          numeric(14,2) not null default 0,
  notes        text,
  created_at   timestamptz default now()
);
create index if not exists idx_purchases_company  on purchases (company_id);
create index if not exists idx_purchases_product  on purchases (product_id);
create index if not exists idx_purchases_date     on purchases (date desc);
create index if not exists idx_purchases_invoice  on purchases (invoice_no);
create index if not exists idx_purchases_due      on purchases (due) where due > 0;

-- ----------------------------------------------------------------------------
-- SALES  (invoice header — one row per invoice, can have many items)
-- ----------------------------------------------------------------------------
create table if not exists sales (
  id              uuid primary key default gen_random_uuid(),
  date            date not null default current_date,
  invoice_no      text not null,
  company_id      uuid references companies(id) on delete set null,
  company_name    text not null,               -- snapshot
  company_address text,
  company_phone   text,
  total           numeric(14,2) not null default 0,
  received        numeric(14,2) not null default 0,
  due             numeric(14,2) not null default 0,
  notes           text,
  created_at      timestamptz default now()
);
create unique index if not exists idx_sales_invoice_no on sales (invoice_no);
create index if not exists idx_sales_company on sales (company_id);
create index if not exists idx_sales_date    on sales (date desc);
create index if not exists idx_sales_due     on sales (due) where due > 0;

-- ----------------------------------------------------------------------------
-- SALE ITEMS  (line items — the multi-product part of an invoice)
-- ----------------------------------------------------------------------------
create table if not exists sale_items (
  id           uuid primary key default gen_random_uuid(),
  sale_id      uuid not null references sales(id) on delete cascade,
  product_id   uuid references products(id) on delete set null,
  product_name text not null,                  -- snapshot
  unit         text,
  qty          numeric(14,3) not null default 0,
  rate         numeric(14,2) not null default 0,
  amount       numeric(14,2) not null default 0
);
create index if not exists idx_sale_items_sale    on sale_items (sale_id);
create index if not exists idx_sale_items_product on sale_items (product_id);

-- ----------------------------------------------------------------------------
-- PAYMENTS  (received from / paid to a company; optionally linked to one invoice)
-- ----------------------------------------------------------------------------
create table if not exists payments (
  id              uuid primary key default gen_random_uuid(),
  receipt_no      text,
  date            date not null default current_date,
  type            text not null check (type in ('received','paid')),
  company_id      uuid references companies(id) on delete set null,
  company_name    text not null,                -- snapshot
  company_address text,
  company_phone   text,
  amount          numeric(14,2) not null check (amount > 0),
  method          text default 'Cash',
  applied_type    text check (applied_type in ('sale','purchase')),  -- which table applied_id points to
  applied_id      uuid,                          -- sales.id or purchases.id depending on applied_type
  applied_label   text,                           -- snapshot of invoice label at time of payment
  notes           text,
  created_at      timestamptz default now()
);
create index if not exists idx_payments_company on payments (company_id);
create index if not exists idx_payments_date    on payments (date desc);
create index if not exists idx_payments_applied on payments (applied_type, applied_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
-- IMPORTANT — read this before deploying publicly.
--
-- This app does its own custom username/password check in JavaScript against
-- the app_users table — it does NOT use Supabase Auth. That means there is no
-- `auth.role() = 'authenticated'` session to check at the database level; the
-- browser talks to Supabase using only the public anon key, all the time,
-- whether or not someone is "logged in" inside the app's UI.
--
-- Practical result: the policies below allow full read/write access to anyone
-- holding your anon key — which is anyone who opens your deployed site and
-- looks at browser dev tools. Permissions and login are enforced by the app's
-- UI only, not by the database.
--
-- This is an acceptable trade-off for a small internal tool on a private URL.
-- It is NOT safe for a publicly-linked site with real business data you care
-- about keeping private. If that's you, upgrade to real Supabase Auth first
-- (see README "Security" section) — then swap `using (true)` below for
-- `using (auth.role() = 'authenticated')` and add role-based checks that
-- join to app_users.
-- ============================================================================

alter table business_profile enable row level security;
alter table app_users        enable row level security;
alter table companies        enable row level security;
alter table products         enable row level security;
alter table purchases        enable row level security;
alter table sales            enable row level security;
alter table sale_items       enable row level security;
alter table payments         enable row level security;

create policy "anon full access" on business_profile for all using (true) with check (true);
create policy "anon full access" on app_users        for all using (true) with check (true);
create policy "anon full access" on companies        for all using (true) with check (true);
create policy "anon full access" on products         for all using (true) with check (true);
create policy "anon full access" on purchases        for all using (true) with check (true);
create policy "anon full access" on sales            for all using (true) with check (true);
create policy "anon full access" on sale_items       for all using (true) with check (true);
create policy "anon full access" on payments         for all using (true) with check (true);

-- ============================================================================
-- HELPER VIEW: live inventory (optional, but saves you recomputing in JS)
-- ============================================================================
create or replace view inventory_live as
select
  p.id,
  p.name,
  p.category,
  p.unit,
  p.opening_stock,
  coalesce(pur.qty_in, 0)  as purchased_qty,
  coalesce(si.qty_out, 0)  as sold_qty,
  p.opening_stock + coalesce(pur.qty_in,0) - coalesce(si.qty_out,0) as current_stock,
  p.reorder_level
from products p
left join (
  select product_id, sum(qty) as qty_in
  from purchases group by product_id
) pur on pur.product_id = p.id
left join (
  select product_id, sum(qty) as qty_out
  from sale_items group by product_id
) si on si.product_id = p.id;
