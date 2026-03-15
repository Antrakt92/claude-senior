---
name: improvement-log
description: Evolutionary record of AI self-improvement — mistakes, rules created, patterns detected. Read before complex work to avoid repeating past errors.
type: project
summary: "5 bugs fixed (2026-03-09): Bybit phantom SELL, Binance fee matching, concurrent asset IntegrityError, FX forward lookup, CoinGecko price=0 cache poisoning. Recurring: forgetting related files, not running full test suite. Techniques: audit system with soft-asserts, parallel subagents, memory checklists."
---

# AI Improvement Log

Track mistakes → analyze root cause → create rules → verify they work.

## Mistake Patterns & Rules Created

| Date | Mistake | Root Cause | Rule Created | Status |
|------|---------|------------|--------------|--------|
| 2026-03-09 | Bybit parser: phantom SELL for wrong currency | Didn't track payment_currency per spot group | Added to project CLAUDE.md: TRANSFER_IN/OUT must accompany BUY/SELL | FIXED |
| 2026-03-09 | Binance parser: fee matched to wrong coin | Positional matching instead of coin-affinity | Implemented 2-pass fee matching | FIXED |
| 2026-03-09 | import_service: IntegrityError on concurrent asset creation | Used db.rollback() instead of SAVEPOINT | Changed to begin_nested() | FIXED |
| 2026-03-09 | FX fill_date_gaps: forward lookup returned future rate | Algorithm looked forward instead of only backward | Removed forward lookup, extended prefetch range | FIXED |
| 2026-03-09 | CoinGecko: price=0 cached, poisoning all users | Didn't distinguish "price is zero" from "no data" | Added `if price == 0: return None` guard | FIXED |

## Recurring Patterns (need stronger rules)

- **Forgetting related files**: keeps happening despite Ripple Effect Rule. Most common with parser ↔ import_service ↔ router chain.
- **Not running full test suite**: sometimes only run the specific test, miss breakage elsewhere.

## Rules Removed (unnecessary noise)

_None yet. Will track as rules are evaluated._

## Techniques That Work Well

- **Audit system**: Writing soft-assert tests that LOG findings instead of failing → then reviewing findings.md → converting confirmed bugs to hard-assert regression tests. This catches edge cases AI wouldn't think to test.
- **Parallel subagents for research**: Launching 3 Explore agents simultaneously to investigate independent questions saves significant time.
- **Memory files for checklists**: `new-parser-checklist.md` and `new-provider-checklist.md` prevent forgetting registration steps across 14+ files.
