# DegenBot Refactor Notes
## What changed and what to do next

---

## What was wrong (and is now fixed)

The original bot was a **coin-analyzer** — it ran 5 data layers, handed everything
to an LLM, and let the LLM score 0-100 and decide buy/watch/reject. That is what
every other generic bot does, and it is NOT what the trader wanted.

**The trader's actual system:**
1. Apply HIS hardcoded rules — no LLM involvement in the decision
2. Track ATL after buying — sell at +800% from ATL (not a fixed TP%)
3. After first sell — rebuy at -80% retrace from peak
4. Check BTC macro before EVERY buy
5. Never re-analyze an address already seen

---

## New files created

| File | Purpose |
|------|---------|
| `lib/src/services/trading/trader_rule_engine.dart` | THE BRAIN — trader's exact rules encoded as deterministic code |
| `lib/src/services/trading/token_cache_service.dart` | In-memory store of analyzed addresses — never re-analyzes |
| `lib/src/services/trading/macro_context_service.dart` | BTC price tracker + analyst override commands |
| `lib/src/services/trading/position_monitor.dart` | ATL tracking, 800% sell trigger, 80% retrace rebuy |

---

## Files significantly modified

| File | What changed |
|------|-------------|
| `token_intelligence_pipeline.dart` | Cache check added; `_runAiScoring` (LLM decides) replaced by `TraderRuleEngine.evaluate()` + `_explainRuleDecision` (LLM only explains) |
| `risk_manager_service.dart` | Added macro context check before trades; removed fixed TP price; stop-loss is now a backstop floor only |
| `trade.spy.yaml` | Added `allTimeLowPriceUsd`, `firstSellExecuted`, `firstSellPriceUsd` fields |
| `command_handlers.dart` | Added `/macro`, `/mcap`, `/reanalyze`, `/cache` commands |
| `message_formatter.dart` | Removed "AI Score: X/100"; positions now show ATL + first-sell target |
| `ai_handler.dart` | Updated system prompt to explain rule-based approach |

---

## What you MUST do before running

### 1. Run `serverpod generate`
The `trade.spy.yaml` model has 3 new fields:
- `allTimeLowPriceUsd: double?`
- `firstSellExecuted: bool?`
- `firstSellPriceUsd: double?`

Run `dart run build_runner build` (or `serverpod generate`) to regenerate
`lib/src/generated/trade.dart`. Then run the Supabase migration to add the
columns to the `trades` table.

### 2. Add http package (if not already present)
`MacroContextService` uses the `http` package for the Coingecko API call.
Check `pubspec.yaml` — if `http` isn't listed, add it:
```yaml
dependencies:
  http: ^1.0.0
```

### 3. Wire PositionMonitor into the scanner loop
When you build the scanner loop (next step), call `PositionMonitor.instance.checkAllPositions()`
every 5-15 minutes to check for sell/rebuy triggers on open positions.

### 4. Wire MacroContextService into the scanner loop
Call `MacroContextService.instance.refreshBtcPrice()` at the start of each
scanner cycle to keep the macro state current.

---

## The trader's rules — exactly as coded in TraderRuleEngine

**Gate 0 (instant abandon):** Honeypot confirmed → stop, zero further API calls.

**Gate 1 (safety):**
- TokenSniffer score ≥ 40 (if available)
- Buy tax < 8%
- Sell tax < 8%
- GoPlus flags: only `external_call`, `has_blacklist`, `has_whitelist`,
  `trading_cooldown` are tolerable. Any other flag = reject.

**Gate 2 (liquidity & ownership):**
- Liquidity must be locked ≥ 30 years (10,950 days)
- Deployer wallet must hold ≤ 10% of supply
- Top 10 wallets must hold ≤ 20% of supply (unless ownership renounced)

**Gate 3 (market fit):**
- Market cap must be $300–$3,000 (default, user-configurable with /mcap)

**Exit strategy (PositionMonitor):**
- Track ATL from moment of buy
- First sell at ATL × 9 (= +800% from ATL)
- After first sell: rebuy when price drops to 20% of first-sell price (−80%)
- Backstop stop-loss: −70% from entry (catastrophic floor, configurable via /risk)

---

## What's NOT built yet (next steps, in order)

1. **Scanner loop** — periodic DexScreener scan every few hours. Should:
   - Check `TokenCacheService` before analyzing any address
   - Call `MacroContextService.refreshBtcPrice()` each cycle
   - Call `PositionMonitor.checkAllPositions()` for sell/rebuy triggers
   - Notify users via Telegram when action is needed

2. **Actual trade execution** — wallet integration (Solana/EVM wallet SDKs)
   for actually submitting buy/sell transactions on-chain

3. **Supabase persistence for PositionMonitor** — currently in-memory.
   On server restart, open positions are lost. Seed from the `trades` table
   on startup.

4. **Historical backtest** — the context doc describes this as Step 2 in the
   overall plan. Before risking real money, run the rule engine against
   historical token launches to measure real edge.

5. **ML filter layer** — Step 3 in the plan: Python XGBoost model as a
   narrow filter ON TOP of the rule engine (not instead of it). Only build
   this after the backtest shows real edge and you have 500+ labeled trades.
