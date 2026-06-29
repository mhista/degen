# DegenBot — Data Services Reference

Current services, costs, and free alternatives. Updated as integrations change.

---

## Layer 1 — Market Data

### ✅ DexScreener
- **What:** Price, volume, liquidity, MCap, buy/sell counts, token age, pair info
- **Cost:** Free, no key required
- **Rate limit:** ~300 req/min unauthenticated
- **Chains:** Solana, Ethereum, BNB, Base, and 60+ others
- **Status:** Wired in, primary market data source
- **URL:** https://dexscreener.com/

**Alternatives (free):**
| Service | Notes |
|---------|-------|
| GeckoTerminal | Free, similar coverage, REST API |
| Birdeye (Solana) | Solana-focused, free tier available |
| Jupiter Price API | Solana only, free, extremely fast |

---

## Layer 2 — Safety / Contract Analysis

### ✅ GoPlus Security
- **What:** Honeypot detection, mint/proxy flags, buy/sell tax, blacklist check
- **Cost:** Free tier (unauthenticated). Registered API key = higher rate limits + priority queue
- **Auth:** HMAC-SHA256 (app_key + time + sign). Keys wired in `.env`
- **Chains:** Ethereum (1), BNB (56), Solana (501)
- **Status:** Wired in with authenticated requests
- **URL:** https://gopluslabs.io/
- **Keys in .env:** `GOPLUS_API_KEY`, `GOPLUS_API_SECRET`

> **Note:** Empty results for Solana are normal for very new tokens — not an error.
> The service fails silently (no user-facing flag) when unavailable.

### ✅ RugCheck
- **What:** Solana token risk score, insider networks, holder concentration, LP lock status, mint/freeze authority, Jupiter verification
- **Cost:** Free tier (most endpoints). API key = higher limits
- **Status:** Wired in, most detailed Solana-specific check
- **URL:** https://rugcheck.xyz/
- **Key in .env:** `RUGCHECK_API_KEY`

### ⚪ TokenSniffer (optional)
- **What:** Contract similarity matching against known scam templates, overall risk score
- **Cost:** Paid ($99/mo). Leave key empty to skip this layer
- **Status:** Optional — gated behind feature flag
- **Key in .env:** `TOKENSNIFFER_API_KEY`

**Alternatives (free):**
| Service | Notes |
|---------|-------|
| Honeypot.is | Free honeypot check, EVM + Solana, very fast |
| De.Fi Shield | Free contract scanner, decent Solana coverage |
| Quick Intel | Free multi-chain scanner, API available |

> **Current gap:** Honeypot.is is the single best free honeypot check for EVM.
> Consider adding it as a dedicated layer alongside GoPlus.

---

## Layer 3 — Liquidity Lock & Ownership

### ✅ RugCheck (bundled)
- LP lock status and platform returned as part of the RugCheck response
- Creator address, deployer holding % (fixed — was using raw balance, now uses topHolders pct)
- Mint/freeze authority status

**Alternatives (free):**
| Service | Notes |
|---------|-------|
| Unicrypt API | Verify LP locks directly (free, no key needed) |
| Team Finance API | Another major locker — cross-check |
| Solscan API | Solana LP lock data, free tier |

---

## Layer 4 — Sentiment & Social Intelligence

### ⚪ ChainGPT (optional)
- **What:** Bullishness score, KOL mentions, mindshare, organic vs paid narrative detection
- **Cost:** Paid credits. Key in `.env` → feature auto-enabled
- **Status:** Optional, gated behind feature flag
- **Key in .env:** `CHAINGPT_API_KEY`

**Alternatives (free):**
| Service | Notes |
|---------|-------|
| LunarCrush | Social sentiment API, free tier (3k calls/day) |
| Santiment | On-chain + social data, free tier limited |
| CoinMarketCap Fear & Greed | Free macro sentiment only |
| Twitter/X API | Mention tracking (free tier = 500k reads/month) |

> **Current gap:** No free sentiment layer active by default.
> LunarCrush free tier is the easiest drop-in replacement for ChainGPT sentiment.

---

## Layer 5 — On-Chain Forensics

### ✅ Bitquery V2 (ALL chains — primary)
- **What:** Unique buyer count, wash-trading detection (same wallet on both sides), recent DEX trades
- **Chains:** Solana, Ethereum, BNB/BSC, Base
- **Cost:** Point-based. Free tier = limited points/day. Queries only run after Gate 0–1 passes, so points aren't wasted on honeypots.
- **Auth:** OAuth2 client credentials (24h tokens, auto-refreshed)
- **Status:** Primary forensics source for all four chains
- **Keys in .env:** `BITQUERY_CLIENT_ID`, `BITQUERY_CLIENT_SECRET`
- **Note:** Use the **Automatic** (server) credentials, not the Manual 10-year ones. Server tokens expire in 24h and are refreshed automatically.
- **Point cost:** ~5–10 points per full token analysis
- **URL:** https://bitquery.io/
- **Namespaces used:** `EVM(network: eth/bsc/base)` for EVM chains; `Solana` for Solana

### ✅ Etherscan / BscScan (ETH + BNB fallback)
- **What:** Transfer history, wallet clustering — fallback when Bitquery is unavailable
- **Cost:** Free tier (5 calls/sec per key)
- **Status:** Fallback only — Bitquery runs first
- **Keys in .env:** `ETHERSCAN_API_KEY`, `BSCSCAN_API_KEY`

### ✅ Solana RPC (Solana fallback)
- **What:** Transaction signature count for Solana (coarse signal only)
- **Cost:** Free (public RPC)
- **Status:** Fallback when Bitquery unavailable — returns no flags (not user-visible)

**Alternatives:**
| Service | Notes |
|---------|-------|
| Helius (Solana) | Best Solana indexer, free tier (100k credits/mo), parsed transactions |
| Moralis | Multi-chain wallet history, free tier (40k calls/mo) |
| BubbleMaps API | Visual wallet cluster graph (paid, ~$50/mo) |
| Solscan API | Solana explorer API, free tier |

> **Next upgrade:** Helius free tier gives us parsed Solana transactions — this would let us
> do true deployer funding-source tracing (who funded the deployer wallet?), which is currently
> the `null` field in `OnChainData.deployerFundingSource`.

---

## Macro Context

### ✅ CoinGecko (BTC price)
- **What:** BTC 24h price change for macro buy-pause logic
- **Cost:** Free, no key required
- **Status:** Wired in `MacroContextService`

**Alternatives (free):**
| Service | Notes |
|---------|-------|
| Binance Public API | Free, higher rate limits |
| CryptoCompare | Free tier, no key needed for basic price |

---

## Summary: What's Free Right Now

| Layer | Service | Cost |
|-------|---------|------|
| Market data | DexScreener | Free |
| Safety | GoPlus (authenticated) | Free |
| Safety | RugCheck | Free |
| LP Lock | RugCheck (bundled) | Free |
| Sentiment | None (ChainGPT optional) | — |
| On-chain (Solana) | Bitquery V2 | Free tier (points) |
| On-chain (Ethereum) | Bitquery V2 → Etherscan fallback | Free |
| On-chain (BNB/BSC) | Bitquery V2 → BscScan fallback | Free |
| On-chain (Base) | Bitquery V2 | Free tier (points) |
| Macro | CoinGecko | Free |

**Total cost to run (default config): $0/month**

ChainGPT and TokenSniffer are the only paid services and both are off by default.

---

## Error Handling Policy

Internal service failures are **never shown to users as flag noise**.

- GoPlus unavailable → returns empty SafetyData, zero flags
- Bitquery unavailable → falls back to Solana RPC, then returns partial data with no user-facing message
- CoinGecko unavailable → macro state stays at last known value
- Any other service timeout → silent fallback, logged server-side only

Users see clean analysis results. Admins see the real picture in server logs.
