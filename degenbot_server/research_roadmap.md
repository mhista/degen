# Research roadmap — areas for deeper investigation

This document tracks the gaps, assumptions, and open questions in the
intelligence pipeline. Treat this as a living document — update it as
you learn more or as APIs change. Items are grouped by urgency.

---

## Critical — resolve before risking real money

### 1. RugCheck API authentication model
The current `rugcheck_service.dart` implementation calls the public
`/v1/tokens/{mint}/report` endpoint without authentication, which works
for basic lookups. Generating an API key requires creating an account at Rugcheck.xyz, and every API request must include the key in the X-API-KEY header — Solana-specific applications also need a Solana private key to generate JWT tokens for authentication. Before production use:
research whether the JWT-based auth is required for the endpoints you
need (insider graphs, wallet risk) versus the basic token report, since
the JWT flow needs a Solana keypair just for authentication purposes —
distinct from your trading wallet.

### 2. TokenSniffer cost-justification
The Sniffer Pack Pro API costs $99/month for 500 scans per day and is aimed at wallet integrations and trading bots. At Degen-bot scan
volumes (potentially hundreds of candidates per day across 3 chains),
500 scans/day may not be enough. Research: does TokenSniffer offer
higher tiers, and is the marginal value over GoPlus + RugCheck alone
worth the cost? Consider running TokenSniffer only on tokens that
already passed GoPlus + RugCheck (i.e., as a final confirmation layer
rather than a first-pass filter) to conserve your daily quota.

### 3. GoPlus rate limits at scale
The default GoPlus throughput is up to 100 data requests in a single batch query, and batch query support for a list of tokens is only available on paid tiers — the free version does not support consuming all token data at one time. Research the
exact free-tier rate limit (requests/minute) and whether batching
multiple contract addresses into one call (which GoPlus supports) is
implemented in our service — currently we call one address at a time.
This is a near-term optimization, not just a research item.

### 4. Solana wallet clustering — the BubbleMaps gap
Our `onchain_forensics_service.dart` explicitly documents that true
wallet-cluster graph analysis for Solana is not implemented — we only
get a raw signature count from the RPC. This is the single biggest gap
in Layer 5 for Solana. Research paths:
  - **Helius API** (Solana-specific indexer) — has enriched transaction
    parsing that can identify token transfers and funding sources
    without you writing a full Solana transaction parser.
  - **Moralis Solana API** — similar indexing service, multi-chain so
    one integration could potentially serve Solana + EVM forensics.
  - **BubbleMaps API directly** — if they offer programmatic access
    (not just the visual web tool), this would be the most direct path
    since it's purpose-built for cluster detection.

### 5. AI hallucination risk in scoring
The `_runAiScoring` method trusts the LLM to return valid JSON with a
score 0-100. LLMs occasionally fail to follow format instructions
exactly, especially under load. Research: should this call use
structured output / JSON mode (most providers support a strict schema
mode that guarantees valid JSON) rather than relying on prompt
instructions alone? Check whether `dartantic_ai` exposes a structured
output mode through the underlying model provider — this would
eliminate the `_parseAiResponse` try/catch fallback entirely.

---

## High priority — needed before scaling beyond prototype

### 6. Deployer wallet funding-source tracing
Currently marked as `null` / unimplemented in `OnChainData`. A common
rug pattern: the deployer wallet receives funding from a fresh,
just-created wallet (often itself funded from a mixer or a centralized
exchange withdrawal seconds before token launch). Tracing this requires
walking backward through the deployer's transaction history to find
its first inbound transaction. Research how Etherscan/BscScan's API
exposes "first transaction" data efficiently (avoid pulling the full
history for old wallets).

### 7. Honeypot.is as a dedicated third safety check
The recommended workflow layers Rugcheck for the broadest default risk screen, GoPlus Security for contract-focused signals, Honeypot.is for direct honeypot checks, TokenSniffer for a familiar second view, and Quick Intel as an extra verification layer. We currently rely on GoPlus's `is_honeypot` flag as
the primary honeypot signal. Research whether adding Honeypot.is as an
independent, dedicated check (it specializes specifically in
transaction simulation — actually simulating a buy-then-sell to see if
the sell reverts) catches cases GoPlus's static analysis misses. This
would be a meaningful Layer 2 addition given honeypots are the single
most catastrophic failure mode.

### 8. ChainGPT coverage gaps for ultra-fresh tokens
As flagged honestly in `chaingpt_service.dart`, brand-new degen tokens
likely won't have ChainGPT sentiment coverage yet. Research: does
ChainGPT have a faster-indexing tier, or should Layer 4 fall back to a
simpler heuristic (e.g., raw Twitter/X search volume via a different
API) specifically for tokens under 24 hours old? This matters because
fresh launches are exactly where degen bots operate most.

### 9. Liquidity lock verification beyond RugCheck's built-in data
RugCheck's `markets[].lp.lpLockedPct` field is the only lock-status
source currently wired up, and only for Solana. For Ethereum/BNB,
research direct API access to Unicrypt and Team.Finance — Team.Finance has locked over $6.5 billion across more than 21,000 DeFi projects, while Unicrypt has locked over $500 million from more than 14,000 projects — to verify lock status independently rather than relying solely on GoPlus's
proxy/ownership flags as an indirect signal.

### 10. Wash trading detection — refine the heuristic
Our current wash-trading flag (`onchain_forensics_service.dart`) uses a
simple circular-address heuristic (addresses appearing as both frequent
senders and receivers). This will produce false positives for
legitimate market makers and false negatives for more sophisticated
wash patterns (e.g., using many one-time-use wallets funded from a
single source rather than reusing the same addresses). Research more
robust wash-trading detection models — there is published research from
firms like Chainalysis and Solidus Labs on this exact problem worth
studying.

---

## Medium priority — quality-of-life and accuracy improvements

### 11. Multi-DEX price reconciliation
DexScreener aggregates across DEXes but our pipeline currently just
takes `pairs.first`. For tokens trading on multiple pools (e.g., both
Raydium and Orca on Solana), research whether picking the
highest-liquidity pair (rather than just the first returned) gives more
reliable pricing — a low-liquidity secondary pool can show wildly
different prices than the main pool.

### 12. Historical backtesting framework
Before risking capital, you should be able to run the intelligence
pipeline against historical token launches where the outcome is already
known (rugged vs. mooned vs. flat) to measure scoring accuracy. Research
how to source a labeled historical dataset — RugCheck and TokenSniffer's
public "flagged scam" databases could serve as negative examples; you'd
need to separately curate positive examples (tokens that performed well
and were NOT scams).

### 13. Holder count and distribution for EVM chains
Currently `MarketData.holderCount` is always null for EVM chains since
DexScreener doesn't provide it. Etherscan/BscScan APIs do expose holder
count and top-holder lists similar to what RugCheck gives for Solana.
Research wiring this into `onchain_forensics_service.dart` so EVM chains
get the same top-10-holder-concentration check Solana already has via
RugCheck.

### 14. Rate limit coordination across services
With 5+ external APIs each having different rate limits (GoPlus,
RugCheck, TokenSniffer, ChainGPT, Etherscan, BscScan, DexScreener), a
busy scanner loop checking many candidates per minute risks hitting
limits across multiple services simultaneously. Research a unified
rate-limiting/queueing layer (e.g., a token-bucket rate limiter per
service) rather than handling each service's limits ad-hoc.

### 15. Cost modeling at scale
Map out the actual monthly cost at your target scan volume:
GoPlus (free tier limits), RugCheck (free vs paid), TokenSniffer ($99/mo
if used), ChainGPT (pricing tiers), Etherscan/BscScan (free tier
limits), plus the AI scoring calls (Gemini/OpenAI cost per token
analyzed). At, say, 500 candidate scans/day, what's the realistic
monthly API bill? This should inform whether TokenSniffer and ChainGPT
are affordable from day one or phased in once the bot proves itself on
the free-tier sources alone.

---

## Future research — once trading is live

### 16. Feedback loop from actual trade outcomes
Once `trades` table has real closed positions with PnL, research how to
feed that outcome data back into the scoring weights. This is the path
toward the "mini trained model" you mentioned in our earlier
conversation — using realized trade outcomes as labels and the
intelligence report's full feature set (all the layer data) as inputs
to train a classifier in Python, then export to TensorFlow Lite for
Dart-native inference.

### 17. Cross-chain pattern recognition
Once you're operating across Ethereum, BNB, and Solana simultaneously,
research whether scam patterns correlate across chains (e.g., the same
group of bad actors launching similar contracts on multiple chains in
quick succession) — this could become a powerful additional signal not
available from any single-chain tool.

### 18. Real-time monitoring vs polling
The current scanner design (to be built in Step 5) will poll
DexScreener's boost/new-listing endpoints. Research whether DexScreener,
GoPlus, or another provider offers WebSocket or webhook-based real-time
feeds — for a degen bot, the few seconds saved by push-based updates
over polling can matter when competing against other bots for the same
early entry.

---

## How to use this document

Treat each numbered item as a ticket. As you research and resolve one,
move it to a "Resolved" section at the bottom with a short note on what
you decided and why, so future-you (or a teammate) doesn't re-research
the same question. Revisit this list every time you add a new chain or
a new data source — new integrations almost always surface new
questions that belong here.
