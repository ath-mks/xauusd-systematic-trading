# v3.01 validation

Native MetaEditor compilation and MT5 tester/demo execution were unavailable in this Linux workspace. No EX5 or trading-performance result is supplied.

## Portable checks

```
python3 -m unittest discover -s tests -p '*.py'
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/core_test.cpp -o /tmp/xep_v3_core
/tmp/xep_v3_core
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/cost_tp_test.cpp -o /tmp/xep_v3_cost
/tmp/xep_v3_cost
```

The Python suite compiles selected real production functions against deterministic API fixtures. Fixtures do not emulate broker fills or timing. Cost checks cover buy/sell floors, rounding, invalid conversion, entry-cost allocation, exit estimates, negative swap and preservation of more profitable targets. Controller checks exercise cost-aware long/short TP, failed conversion and holding-exit priority. Inherited capacity/timer/history/reconciliation/tester checks remain included.

The inherited v3.00 validation did not cover the temporary market order created by a server TP/SL. The v3.01 regression adds that case and checks the original foreign-activity protections. The fill-to-first-update limitation remains: a preattached estimated TP may execute before correction to actual fill costs. This is not an assurance of native compilation or broker behaviour.

## MT5 acceptance

1. Compile with both headers; confirm zero errors.
2. Use GBP and real ticks; use hedging for two positions.
3. Run both one-position presets with identical tester settings; retain HTML and all CSVs.
4. Check paired entry/exit deal charges against £0.45 per 0.10 lot round trip. Default 4.50 is per full lot round trip; the exit estimate is half that rate.
5. Inspect long and short TP updates against actual allocated entry costs, estimated exit costs, negative swap and buffer; check request acceptance.
6. Confirm SL, timed and risk exits still close below the floor and holding time never extends to wait for break-even.
7. Repeat for two positions; check independent targets/timers, gross-volume/daily caps and STOP & FLATTEN.
8. Compare net profit, drawdown and exit-category results. A higher profitable-TP frequency alone does not establish an improvement.

## Completed portable run

83 Python unittest checks passed, plus the core and cost TP C++ test programs with warnings treated as errors. Six server-exit regression scenarios failed against the unmodified v3.00 production functions before the fix and passed after it. Cases cover TP, SL, stop-out, a simultaneous risk stop, an exit appearing during reconciliation, and waiting while the position/deal state catches up. Different-magic TP/entry orders and unexpected own market orders still halt. Conversion failure still prevents a same-pass new entry and flattens on the next eligible controller pass. Native MT5 checks remain outstanding.

## Observed failure behind this correction

The uploaded demo was GBP, hedging mode, magic 26101503, RunId 10, one 0.10-lot position, Original TP, 60-second holding limit and 00:00–24:00 UTC session. Server TP market BUY order 94949152 appeared for short position 94949141 at observed_mono_us 61237162. The reported RUN_HALT occurred at 61237609, followed by an EA market close rejected with retcode 10036 at 61244772. The eventual closing deal 63437923 had TP reason 5 and the same magic, closing at 4142.19. This matches the non-limit-order branch of the v3.00 Scan safeguard.

Both positions closed through TP, with no overlapping positions: 94949115 earned GBP 1.28 gross less GBP 0.46 commission = GBP 0.82; 94949141 earned GBP 1.59 gross less GBP 0.46 commission = GBP 1.13. Total net GBP 1.95. Their server holding times were 0.603 and 1.409 seconds. These two trades are diagnostic observations, not a performance assessment.

On the next demo run, verify server exits continue without false foreign-activity halts, attributed deal volume matches the closed position, and no extra EA close is sent while a known server exit is settling. Keep all CSVs. Confirm the START event says source logger v3.01.

## Review scope and residual timing limit

Source review found no blocking issue for the supplied one-position failure. The controller still uses one close barrier at a time. With several simultaneous server exits, it can retain only one currently observed exit order; another can disappear before its position/deal update and before it is adopted. Complete protection across every concurrent-exit snapshot ordering has not been established. The one-position regression and passing portable fixtures do not replace a native demo test or prove broker updates are atomic.
