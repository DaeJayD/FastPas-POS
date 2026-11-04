-- Read-only. Record these results before applying migration 202611030001.
-- Run in the intended development project's SQL Editor as its database owner.
select
  current_database() as database_name,
  to_regprocedure('public.pos_business_settings(uuid)') is not null as phase_4_installed,
  to_regprocedure('public.pos_post_stock(uuid,uuid,jsonb)') is not null as phase_5_installed,
  (select count(*) from public.pos_businesses) as businesses,
  (select count(*) from public.pos_branches) as branches,
  (select count(*) from public.pos_items) as products,
  (select count(*) from public.pos_item_stock) as stock_rows,
  (select coalesce(sum(quantity),0) from public.pos_item_stock) as total_stock,
  (select count(*) from public.pos_cash_sales) as receipts;
