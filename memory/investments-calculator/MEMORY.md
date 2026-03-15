# Project Memory — investments-calculator

<!-- L0 = this index (always loaded). L1 = summary field below each link (enough to decide relevance).
     L2 = full file (read only when needed). This reduces token consumption by ~90% vs loading all files. -->

## AI Self-Improvement Log
- [improvement-log.md](improvement-log.md)
  L1: 5 bugs fixed (2026-03-09): Bybit phantom SELL, Binance fee matching, concurrent asset IntegrityError, FX forward lookup, CoinGecko price=0 cache poisoning. Recurring: forgetting related files, not running full test suite. Techniques: audit system, parallel subagents, memory checklists.

## Checklists
- [new-parser-checklist.md](new-parser-checklist.md)
  L1: 10 steps across backend/frontend/tests. Key: content-based detection (not filename), PARSER_REGISTRY ordering, crypto stablecoin mapping + TRANSFER_IN/OUT, dedup keys use quantity when gross_amount=0, API vs CSV broker naming.
- [new-provider-checklist.md](new-provider-checklist.md)
  L1: 10 steps: create provider, register, add throttling/DB/migration, update frontend. CRITICAL: never swallow RateLimitError, never cache price=0 (poisons DB 24h), distinguish transient from permanent failures.

## Feedback
- [feedback_hooks_vscode.md](feedback_hooks_vscode.md)
  L1: exit 0+stdout = AI never sees it. exit 2+stderr = blocks and shows message. Marker file pattern for block-then-allow.

## Audit System
**Location:** `backend/tests/audit/` — 357 tests, 0 open findings (as of 2026-03-09).
**Run:** `cd backend && python -m pytest tests/audit/ -v -s` → review `findings.md`

### Not yet covered by audit
- CSV parser → DB round-trip (parse, store, retrieve, verify)
- Multi-year DD chain with credit carry-through
- Currency conversion edge cases (FX failure, weekend rates)

## Infrastructure
**Hooks:** pre-commit-review, block-dangerous-git, block-protected-files, auto-lint-python, auto-lint-typescript, check-css-variables
**Tests:** `bash .claude/hooks/test-hooks.sh` — 61 tests
**Agents:** security-reviewer, code-reviewer, ripple-checker
