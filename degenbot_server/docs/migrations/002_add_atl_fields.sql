-- ============================================================
-- Migration 002 — ATL-based sell strategy columns
--
-- Adds three columns to the trades table to support the
-- All-Time Low tracking and first-sell execution logic:
--
--   all_time_low_price_usd  — lowest price seen since entry.
--                             Starts at buy_price_usd, only moves down.
--                             First sell triggers at ATL × 9 (+800%).
--
--   first_sell_executed     — true once the +800% sell fires.
--                             After this, we watch for −80% rebuy.
--
--   first_sell_price_usd    — price at which the first sell executed.
--                             Rebuy target = first_sell_price_usd × 0.20.
--
-- Run in Supabase SQL Editor (one-time).
-- Safe to run on a live table — all columns are nullable with no default.
-- ============================================================

alter table trades
  add column if not exists all_time_low_price_usd numeric,
  add column if not exists first_sell_executed     boolean,
  add column if not exists first_sell_price_usd    numeric;

-- Backfill: set ATL = buy_price_usd for any open trades that don't have it yet.
-- (New trades will get ATL set immediately when PositionMonitor tracks them.)
update trades
set all_time_low_price_usd = buy_price_usd
where status = 'open'
  and all_time_low_price_usd is null;

-- ── Add Base to chain check constraints ───────────────────────────────────────
-- The original schema only allowed 'solana', 'ethereum', 'bnb'.
-- Base is now a supported chain — drop and recreate the constraints.

alter table users
  drop constraint if exists users_active_chain_check;
alter table users
  add constraint users_active_chain_check
  check (active_chain in ('solana', 'ethereum', 'bnb', 'base'));

alter table coin_candidates
  drop constraint if exists coin_candidates_chain_check;
alter table coin_candidates
  add constraint coin_candidates_chain_check
  check (chain in ('solana', 'ethereum', 'bnb', 'base'));
