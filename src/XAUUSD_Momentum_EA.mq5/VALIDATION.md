# Validation record — 13 October 2026

Scope: XAU ExecutionProbe 1.04 source package. This environment has a C++ compiler and Python, but no MetaEditor, MT5 terminal or Wine. No `.ex5` is provided, no native MQL compilation was performed here, and no broker orders were submitted by this environment. User-supplied version 1.00 demo logs were used to diagnose the expiration rejection. Later reports identified a sample-target halt and slowing/freezing when increasing the target.

## Version 1.04 history performance correction

Source-level evidence: `RefreshPnL()` rebuilt all run history every simulated second, with repeated linear position and logged-deal searches. Its nested searches scale quadratically within a refresh. Recovery also resized an array once per eligible deal. The user's terminal was not accessible, so this diagnoses concrete code bottlenecks rather than proving these are the sole cause of the reported freeze.

`tests/history_performance_test.py` compiles actual extracted history, accounting and logging functions against deterministic C++ API stubs. Three of four tests failed before the change; accounting correctness already passed. The lookup fixture uses 20,000 stored positions and checks one present and one absent ID per position. It required 600,010,000 ID comparisons with v1.03 and 614,468 with v1.04. The corresponding new deal lookup case also uses 614,468 comparisons. These are operation counts, not a claim of a measured MT5 speedup.

Sorted tables with binary search replace linear searches; insertion handles out-of-order IDs and callback tickets. Recovery preallocates its ticket array. Tester history totals are reused after successful history selection if count/day are unchanged and no deal mutation invalidated them. A 60-second simulated-time audit catches old revisions or missed callbacks; callback invalidation, count/day changes and clock reversal force an earlier rebuild. Any deal add/update/delete callback invalidates before symbol filtering. Teardown forces a final refresh. Failed recovery remains dirty for retry. Demo full-refresh cadence and all inputs are unchanged; floating P&L and risk checks still run in the controller as before.

All four new tests passed. Cases cover ordered and unordered identifiers, unchanged-history reuse, new/deleted deals, revised profit, partial exits, daily boundaries, foreign netting contamination, demo refresh behavior and a failed history selection. The existing core assertions and 33 Python checks also passed. Native compilation, actual long-backtest runtime, event ordering and CSV persistence must still be verified in MT5. Full history audits, per-tick CSV output and the 100 ms timer remain costs in long tests.

A fresh independent reviewer examined the v1.03-to-v1.04 diff and reran the four new tests plus all 23 tests selected by `*test.py`. No critical or important findings were reported. Remaining limits: an unnotified same-count revision can wait until the 60-second simulated audit, full-history selection/reconciliation still scales with history size, and unusually reverse-ordered insertions still require linear shifts per insertion. The measured comparison reduction is limited to the lookup fixture, not a whole-run benchmark.

## Version 1.03 tester completion correction

Evidence: `2026.10.13 23:13:38.872 Core 1 2026.10.01 18:38:14 XEP RUN_HALT: Target completed; collect CSV files`. Source inspection confirms that reaching `InpTargetPositions` only latched the run halt; the timer and tick handlers kept running through the selected historical period. This message is a target-completion condition, not an order rejection.

Correction: after the existing close/order reconciliation, a tester-only guard requests `TesterStop()` when the target is reached and no positions, pending orders, foreign exposure, ambiguous requests, contamination or unresolved barriers remain. The live position ledger must also match the deal history. It writes `TESTER_COMPLETE`, saves order/risk state, flushes files and stops the timer before requesting normal tester completion. Further strategy/tick processing is suppressed while normal deinitialization and final history recovery remain enabled. Demo behavior and all input values are unchanged.

Both new tests in `tests/tester_completion_test.py` failed against v1.02 and passed after this change. The first compiles the actual completion function against deterministic C++ stubs and exercises target, tester/demo, exposure, reconciliation, ambiguity and repeated-call guards, plus save/flush/stop ordering. The second checks its placement after reconciliation and before new entry submission. All existing portable checks also passed. These checks do not execute MT5's `TesterStop` lifecycle; native completion and report generation remain to be verified in the terminal.

A fresh independent reviewer checked the v1.02-to-v1.03 source diff and completion lifecycle, and independently reran both completion checks. No critical or important findings were reported. In MT5, verify the final closed position, `TESTER_COMPLETE`, `DEINIT` and an early completed report.

## Version 1.02 tester corrections

Source inspection identified host-runtime strategy clocks and live permission dependencies inside tester execution. A deterministic portable harness reproduces how 30 simulated market seconds can pass while the old controller advances by only 1 ms of host time. It also reproduces the old permission rejection when testing offline. These are identified code defects, not proof that the user's unseen tester failure has no other cause.

The new `StrategyNowUS` separates strategy deadlines from CSV observation timing. In tester mode it uses simulated server/tick time with a nondecreasing clamp. In demo mode it preserves `GetMicrosecondCount`. Order throttles, quote age, holding/TP deadlines, freshness and controller refreshes now use this strategy clock. CSV observations and request duration continue to use the host monotonic clock and are explicitly identified in metadata.

Only actual MT5 tester mode bypasses live connection/permission flags, after the existing account-identity check. Real-account rejection and demo permission checks remain. Tester warmup consumes delivered quote events, including repeated millisecond timestamps, and skips `CopyTicks` history loading. The original demo history ingestion remains in place.

`tests/tester_compatibility_test.py` compiles the actual controller clock expression, clock/permission functions and tick ingestion code, together with `MMCore.mqh`, against deterministic environment/I/O stubs. Eight of thirteen checks failed before implementation; all thirteen passed after correction. They cover accelerated playback, host pauses, absent ticks, nondecreasing time, timer gaps, demo clock/permissions, real/account-change guards and tester warmup. These are portable behavior tests; they do not emulate MT5's event engine or order fills.

A fresh independent reviewer examined the complete v1.01-to-v1.02 source diff, audited clock domains and permission guards, and independently reran the thirteen compatibility checks. No critical or important findings were reported. Native MQL compilation, tester launch, event timing and trade execution still require verification in MT5.

## Version 1.01 expiration correction

Evidence: all five supplied entry replies contain retcode 10022 and "Invalid expiration", no order/deal ticket, and ORDER_TIME_SPECIFIED (2). The requested expiry was approximately 15 seconds after the contemporaneous server quote. Symbol metadata reports expiration_mode=15, which includes GTC (flag 1), and a measured server offset of +10800 seconds. These logs establish an expiration-specific rejection but do not establish the server's exact minimum permitted duration.

Correction: when GTC is advertised, retain ORDER_TIME_GTC and expiration=0. Preserve the connected EA's existing local cancel/requote timer, SL/TP, risk limits and rejection halt. Keep the previous specified-only fallback for symbols without GTC. Restart instructions explicitly require a flat symbol and a new RunId; the source never clears the old run's halt automatically.

`tests/expiration_test.py` extracts and executes the actual expiration-assignment block from the EA as C++ with deterministic symbol/time inputs. Before the fix, two cases failed: the observed Pepperstone flags (15) and combined GTC/SPECIFIED flags (5). After the fix all four cases pass, including GTC-only and the unchanged specified-only fallback. These tests prove request construction, not server acceptance.

GTC removes the requested server expiry; orders may survive a terminal disconnect. This consequence is documented in the upgrade instructions. The user reported demo operation after version 1.01. Native compilation and runtime checks are still required for the current package.

## Checks performed

The exact `MMCore.mqh` header used by the EA is also compiled by the C++ test harness, with mappings for the MQL math functions. Tests cover warmup, rolling signals, known price paths, rounding, quote/exit bounds, side choice, lot validation, risk priorities, freshness, holding-time remainder and volume reconciliation.

```sh
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/core_test.cpp -o /tmp/xep_core_test
/tmp/xep_core_test
python3 tests/regression_checks.py
python3 tests/check_package.py
python3 tests/expiration_test.py
python3 tests/tester_compatibility_test.py
python3 tests/tester_completion_test.py
python3 tests/history_performance_test.py
```

Core assertions passed without compiler warnings. All 37 Python-driven checks passed: nine source integration regressions, five packaging checks, four expiration cases, thirteen tester compatibility cases, two tester completion checks and four history performance checks. The regression checks verify that the relevant guards and integration paths remain present; they are **not** a simulated MT5 event engine and do not prove live race handling. Packaging checks cover all 28 preset inputs and their metadata, the six CSV column layouts, event hooks, request centralization and recovery-state fields.

Test-first record: the core harness initially failed because the shared implementation was absent. The nine integration regression checks initially failed against the pre-review source. Both passed after implementation and fixes.

## Independent review and corrections

A fresh reviewer examined the source for API usage, order lifecycle, restart handling, exposure ownership, risk enforcement and timing/logging interpretation. One correction pass addressed the important findings; no second independent review is claimed.

| Finding | Correction |
|---|---|
| Tick freshness compared with a clock read before history pumping | Read a fresh monotonic clock after pumping history |
| Recovered old history could look newly received | Check broker quote age as well as local progress and catch-up state |
| Order barrier released before fills and positions reconciled | Require terminal order history, expected executed volume and matching deal/live-position ledgers |
| A close reply containing only a deal ID lacked reconciliation | Persist the deal ID, recover its order ID and reconcile before allowing another volume request |
| Restart granted a full new holding interval | Subtract existing server-reported position age and track the remaining local deadline |
| Midnight reset could reuse previous-day realized P&L | Force history refresh when the UTC day changes |
| Foreign netting fills could evade position-magic checks | Scan history for external symbol deals and latch mixed-position protection |
| Deal records could be omitted around unload/restart | Backfill known-position history, log revisions and recover again during teardown/attachment |

Additional hardening binds all requests to the captured account and server, persists ticket values in two 32-bit parts, records an in-flight marker before volume-changing requests, and avoids TP modification near existing stop/freeze boundaries. A terminal crash with an in-flight request leaves the run halted for manual inspection.

## Checks still requiring MT5

- Native MetaEditor compilation, including any compiler-specific syntax or warnings.
- Actual broker symbol constraints, pending-order acceptance, expiration and stop/TP behavior.
- Demo fills, partial fills, cancellation/fill races, delayed transactions and disconnect recovery.
- Terminal clock behavior, server UTC offset, commissions and differences between hedging/netting account implementations.
- UI attachment, stop button, terminal shutdown/restart and file output in the user's installation.

The source checks do not replace these terminal checks. Risk and holding thresholds trigger requests; they do not guarantee a fill price, maximum loss or deadline. The serial entry/position-TP architecture intentionally differs from simultaneous two-sided market-making quotes, and scheduled-news filtering is not implemented.
