-- ─────────────────────────────────────────────────────────────────────────────
-- DegenBot — Supabase schema (migration 001 — initial)
--
-- THIS IS ALREADY APPLIED TO THE DATABASE.
-- For reference / fresh installs only. Do not re-run on existing DB.
--
-- To apply changes, see 002_add_atl_fields.sql and later migrations.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── USERS ────────────────────────────────────────────────────────────────────
create table if not exists users (
  id                bigserial primary key,
  telegram_id       bigint not null unique,
  telegram_username text,
  active_chain      text not null default 'solana'
                      check (active_chain in ('solana', 'ethereum', 'bnb')),
  wallet_address    text,
  subscription_tier text not null default 'free'
                      check (subscription_tier in ('free', 'basic', 'pro')),
  is_bot_active     boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists users_telegram_id_idx on users (telegram_id);

-- ── COIN CANDIDATES ──────────────────────────────────────────────────────────
create table if not exists coin_candidates (
  id                bigserial primary key,
  chain             text not null check (chain in ('solana', 'ethereum', 'bnb')),
  contract_address  text not null,
  name              text not null,
  symbol            text not null,
  ai_score          int not null default 0 check (ai_score between 0 and 100),
  liquidity_usd     numeric not null default 0,
  volume_usd_24h    numeric not null default 0,
  price_usd         numeric not null default 0,
  market_cap_usd    numeric,
  holder_count      int,
  price_change_1h   numeric,
  price_change_6h   numeric,
  price_change_24h  numeric,
  ai_reasoning      text,
  status            text not null default 'pending'
                      check (status in ('pending', 'bought', 'closed', 'rejected')),
  scanned_at        timestamptz not null default now(),
  constraint coin_candidates_unique unique (contract_address, chain)
);

create index if not exists coin_candidates_status_idx on coin_candidates (status);
create index if not exists coin_candidates_score_idx  on coin_candidates (ai_score desc);
create index if not exists coin_candidates_chain_idx  on coin_candidates (chain);

-- ── TRADES ───────────────────────────────────────────────────────────────────
create table if not exists trades (
  id                    bigserial primary key,
  user_id               bigint not null references users(id) on delete cascade,
  coin_candidate_id     bigint not null references coin_candidates(id),
  chain                 text not null,
  contract_address      text not null,
  symbol                text not null,
  amount_spent_native   numeric not null,
  amount_spent_usd      numeric not null,
  buy_price_usd         numeric not null,
  buy_tx_hash           text,
  bought_at             timestamptz,
  sell_price_usd        numeric,
  sell_tx_hash          text,
  sold_at               timestamptz,
  take_profit_price_usd numeric,
  stop_loss_price_usd   numeric,
  realized_pnl_usd      numeric,
  roi_percent           numeric,
  close_reason          text
                          check (close_reason in ('take_profit', 'stop_loss', 'manual')),
  status                text not null default 'open'
                          check (status in ('open', 'closed', 'failed')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists trades_user_idx      on trades (user_id);
create index if not exists trades_status_idx    on trades (status);
create index if not exists trades_user_date_idx on trades (user_id, created_at desc);

-- ── RISK PROFILES ────────────────────────────────────────────────────────────
create table if not exists risk_profiles (
  id                          bigserial primary key,
  user_id                     bigint not null unique references users(id) on delete cascade,
  max_trade_percent           numeric not null default 5.0,
  daily_trade_limit           int not null default 10,
  trades_today                int not null default 0,
  default_take_profit_percent numeric not null default 50.0,
  default_stop_loss_percent   numeric not null default 20.0,
  last_reset_date             timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create index if not exists risk_profiles_user_idx on risk_profiles (user_id);

-- ── FEATURE FLAGS ────────────────────────────────────────────────────────────
create table if not exists feature_flags (
  id          bigserial primary key,
  flag_name   text not null unique,
  is_enabled  boolean not null default true,
  updated_at  timestamptz not null default now()
);

create index if not exists feature_flags_name_idx on feature_flags (flag_name);

-- ── AUTO-UPDATE updated_at ───────────────────────────────────────────────────
create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger users_updated_at
  before update on users for each row execute function update_updated_at();
create or replace trigger trades_updated_at
  before update on trades for each row execute function update_updated_at();
create or replace trigger risk_profiles_updated_at
  before update on risk_profiles for each row execute function update_updated_at();
create or replace trigger feature_flags_updated_at
  before update on feature_flags for each row execute function update_updated_at();
