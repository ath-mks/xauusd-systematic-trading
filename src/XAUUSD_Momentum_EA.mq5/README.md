# XAU ExecutionProbe 1.04

Demo-only MT5 Expert Advisor for measuring XAUUSD pending-order execution. It places one entry order at a time, manages at most one position, and records quotes, requests, transactions, fills and costs. It refuses real accounts. Strategy Tester runs are explicitly labeled simulations.

This package contains source code, presets and verification materials. **It has not been compiled in MetaEditor or run against a broker in this environment.** Compile and inspect a short demo run before collecting the longer sample.

## Version 1.04: reduce history work in longer backtests

Raising `InpTargetPositions` allows a longer run and a larger trade history. Earlier versions rebuilt that history every simulated second and repeatedly searched every stored position and deal. These nested linear searches caused sharply increasing work as the sample grew.

Version 1.04 uses sorted ticket tables with binary searches. In tester mode it reuses unchanged history totals, invalidating them on a deal-count change, a deal add/update/delete callback, a day change or a backward clock change. It also performs a full audit at least once per simulated minute and forces final recovery during shutdown. A failed history selection still halts the run. Demo history refresh cadence remains unchanged. Inputs, quote timing, tick ingestion, CSV schemas and risk thresholds are unchanged.

Install by stopping any attached demo instance and confirming flat/no pending orders, replacing both source files, and compiling `XAU_ExecutionProbe.mq5` with F7. Confirm version **1.04**. Rerun the same tester dates and inputs to compare; retain real-tick testing. This removes identified source-level history bottlenecks, but no MT5 elapsed-time benchmark is available from this environment. Full tick CSV logging and the 100 ms timer still make long tests expensive; increasing the target does not guarantee a practical runtime for an arbitrarily large sample.

## Version 1.03: finish the tester at the sample target

The Journal message `XEP RUN_HALT: Target completed; collect CSV files` means the completed-position target was reached (200 by default). Earlier versions stopped placing orders but continued processing and logging the remaining historical dates. This could make a backtest appear stuck.

Version 1.03 finishes a tester run normally with `TesterStop()` once the target is reached, positions and orders are absent, and fill/position reconciliation is complete. It saves state, flushes the logs and records `TESTER_COMPLETE` before requesting completion. MT5 retains the statistics accumulated so far. This is a **partial-period sample**, not a test of the entire selected date range. Ambiguous requests or inconsistent exposure prevent this early-completion path until resolved.

Replace both source files and compile with F7; confirm the current version **1.04**. First stop any attached demo instance and confirm it has no positions or pending orders, as recompilation can reinitialize it. Preserve customized inputs. To collect more than 200 completed positions, increase `InpTargetPositions` in the **Strategy Tester → Inputs** tab. Loss/drawdown limits still apply. Demo behavior, position size, SL/TP, risk thresholds and the default target are unchanged.

## Version 1.02: Strategy Tester compatibility

The user reported that version 1.01 works on a demo chart but not in a backtest. Source inspection found strategy deadlines driven by elapsed host time, which is inappropriate for accelerated historical playback, and a requirement for live terminal permissions during simulated trading. The tester Journal was not supplied, so a separate launch, history-download or configuration failure has not been ruled out.

Version 1.02 uses simulated server/tick time for tester quote age, repricing, holding deadlines and request pacing. The clock cannot move backward when a tick read is temporarily unavailable. Demo mode retains the local monotonic strategy clock and all demo permission checks. Tester mode obtains its features from delivered `OnTick` events and does not call `CopyTicks` to prefetch history. It requires 1,001 valid delivered ticks before quoting.

To install, first stop the existing demo EA and confirm flat/no pending orders before overwriting and recompiling its files; recompilation may reinitialize an attached EA. Retain your current demo input settings if you customized them. For a controlled tester check:

1. Compile the updated source with F7 and verify zero errors, then select **XAU_ExecutionProbe** in MT5 Strategy Tester (Ctrl+R).
2. Select the exact broker **XAUUSD** symbol and **M1**. The strategy uses ticks; M1 is a convenient display period.
3. Select **Every tick based on real ticks**. Do not use Open prices only or 1 minute OHLC for this tick-dependent logic.
4. Start with one complete weekday, for example **2026.09.15 to 2026.09.16**, if the broker supplies history for it. Set **Optimization: Disabled** and use a local testing agent. An initial visual run makes the chart status visible.
5. In the tester's **Inputs** tab, load `XAU_Backtest_Check.set`. This uses the original 0.01-lot baseline, original risk limits and test RunId 101. Inputs on an attached demo chart are not automatically the tester's inputs. The tester's global variables are separate from the demo terminal's state.
6. Leave `InpServerUTCOffsetHours=3` for the September interval being examined, subject to verification against that history. The entry window remains 07:00–17:00 UTC: with this offset, 10:00–20:00 in recorded broker time. Today's wall-clock time does not restrict historical entries.
7. Start the test and inspect the **Strategy Tester → Journal** tab if it cannot initialize, load history or place orders. For diagnosis, send the first error and surrounding messages, the tester Settings screenshot and any chart status.

The default 100 ms timer and CSV logging make this slower than a bar-based EA; do the one-day check before a month or an optimization. The sample target of 200 completed positions and daily/run risk stops remain active. From version 1.03, reaching the sample target completes the tester early after reconciliation. A daily risk stop still waits for the next UTC day; other run stops can produce a flat equity segment through the remaining test. A completed test with zero trades still needs its status/logs inspected; it is not automatically a timing bug.

Between quote events, the tester clock uses the simulated server's second-resolution time; on quote events it also uses the tick's millisecond timestamp. It does not promise exact subsecond exits between ticks. CSV `*_mono_us` observations and `call_duration_ms` remain host-runtime measurements; in the tester, these are processing measurements, **not simulated broker latency**. Metadata identifies both clock domains and tester tick ingestion. Test fills remain simulated even with real historical quotes.

## Upgrade after the invalid-expiration stop

Version 1.01 prefers GTC (good till cancelled) when the symbol advertises it. Version 1.00 selected a 15-second specified expiration on PepperstoneUK-Demo XAUUSD; the supplied logs show five rejections with code 10022, "Invalid expiration". They do not reveal the broker's minimum acceptable expiry. Normal cancellation/repricing remains controlled by the EA's 3-second timer.

1. Confirm in MT5's Trade tab that XAUUSD has no positions or pending orders, then remove the old EA from the chart.
2. Replace the two source files in the existing Experts folder and compile `XAU_ExecutionProbe.mq5` with F7.
3. Reattach the EA, load the preset, and change **InpRunId from 1 to 2** for this corrected demo run. The old run deliberately retains its rejection halt. Do not delete terminal global variables or disable the rejection limit.
4. Confirm the chart displays **1.04**. Keep Algo Trading enabled and the terminal connected. Observe a short run and retrieve fresh logs if another rejection occurs.

With GTC selected, pending orders have no specified expiry and can remain at the broker after a disconnection or shutdown. Use STOP & FLATTEN while connected, confirm flat/no pending orders, then stop the terminal. The new version does not silently reset risk stops.

## Install and compile

1. Extract this ZIP.
2. In MT5, choose **File → Open Data Folder**. Open `MQL5\Experts` and create a folder named `XAU_ExecutionProbe`.
3. Copy **both** `XAU_ExecutionProbe.mq5` and `MMCore.mqh` into that folder. Keep them together.
4. Press **F4** to open MetaEditor. Open `XAU_ExecutionProbe.mq5`, then press **F7** to compile. Proceed only after the compiler reports zero errors. If it reports errors, send the exact error text and line numbers for correction. A successful local compile creates the `.ex5` file.
5. Return to MT5. In **Navigator → Expert Advisors**, right-click and refresh if necessary.

No DLL, Python installation or WebRequest configuration is needed to run the EA. The included Python/C++ files are developer verification tools, not MT5 dependencies.

## Start the demo run

1. Connect to your **Pepperstone Razor demo account**. Use a dedicated XAUUSD symbol/account without manual trades or another EA trading that symbol. Open your broker's exact XAUUSD chart; suffixes are accepted. Any chart timeframe works because the EA uses ticks.
2. Drag `XAU_ExecutionProbe` onto the chart. In **Inputs**, choose **Load** and select the extracted `XAU_Demo_Execution.set` file.
3. Check that `InpLots=0.01` is appropriate for this demo and valid for the broker's symbol. The EA rejects an invalid size; it never rounds up to a larger lot.
4. Check `InpServerUTCOffsetHours`. The preset uses **+3 provisionally**. Compare current broker time with UTC while connected, and adjust if necessary. Live session scheduling uses UTC directly; this offset is used to assign history to UTC days and for tester timing. Update it when the broker changes its offset.
5. Allow algorithmic trading in the EA settings and enable the MT5 **Algo Trading** toolbar button. The preset enables demo orders, so eligible entries can begin after initialization.
6. Watch the first few fills. Confirm the symbol and lot size, no more than one position, and that filled positions have a server SL and TP. If compilation or terminal behavior differs from these expectations, stop the probe and send the logs.

The default entry session is **07:00–17:00 UTC, Monday–Friday**, with new entries ending 30 seconds early. Warmup requires 1,001 valid quotes; available recent tick history can satisfy it on a demo chart. In the tester, warmup uses ticks delivered after the test begins. The chart displays status, warmup, completed positions and P&L. Outside the session or when filters block entries, it can remain idle normally.

Start with a short observed demo run. If behavior matches the settings, continue toward the target of **200 completed positions**. A risk stop or a smaller sample is still useful; do not repeatedly reset a stopped run merely to reach 200.

## Default behavior

| Setting | Default and meaning |
|---|---|
| Exposure | One pending entry while flat; one position; 0.01 lot; no averaging |
| Fair price | Midpoint of current Bid and Ask |
| Volatility | RMS of midpoint changes over 500 ticks, scaled by the square root of 50; 1,000-tick slow baseline |
| Quote distance | Maximum of 0.10 and volatility × 1.0, then adjusted outward for broker minimum distances and tick size |
| Momentum | 20-tick displacement normalized by 200-tick RMS changes; threshold ±1.5 selects the eligible entry side |
| Repricing | Cancel and replace about every 3 seconds, only after previous order/fills reconcile |
| Inventory skew | Adaptive position TP uses midpoint − 0.5706715943 × direction × volatility²; direction is normalized to +1/−1 |
| Spread filter | No new entry above 0.20 price units |
| Volatility filter | No new entry when short volatility exceeds 2 × slow volatility |
| Stale quotes | Cancel entries and attempt to flatten if quotes are stale; default age limit 5 seconds |
| Server stop | Initial distance is max(0.50, 4 × quote distance, broker minimum); not moved by adaptive TP |
| Initial TP | Entry price plus/minus max(2 × quote distance, broker minimum); subsequently adaptive |
| Holding target | Attempt exit after 30 seconds, retaining remaining time after a restart |
| Daily risk | Halt at loss of 10 or drawdown of 10 account-currency units |
| Run risk | Halt at loss of 30 or drawdown of 30 account-currency units |
| Sample target | Halt after 200 completed positions in the run |

Price distances use the symbol's quoted price units, typically USD per ounce for standard XAUUSD. **Money risk limits use the account currency**, and cover this EA's tracked activity, not total account equity. They include attributed deal profit, commission, swap and fee, plus current floating P&L. Separate broker balance charges without a position identifier cannot reliably be attributed here.

Risk values are **exit triggers, not guaranteed maximum losses**. Broker delays, spread changes, gaps, rejection, disconnection and terminal shutdown can prevent the requested exit time or price. The fixed server SL remains independent of terminal timers, subject to broker execution.

## What this probe tests

This first version measures whether demo entry fills, exits and costs justify further work. It alternates eligible entry sides while flat. Strong positive momentum permits buy entries; strong negative momentum permits sell entries. Existing pending entries are reconsidered at the next refresh, rather than on every momentum change. After a fill it cancels any unfilled entry remainder, preserves the initial SL and adjusts that position's TP.

This differs from simultaneously resting both buy and sell quotes. It is a serial execution probe suitable for hedging and netting accounts, not a reproduction of a two-sided backtest and not evidence of profitability. A TP can move below the original entry for a long position, or above it for a short position; its name does not imply that each exit makes money. No scheduled-news calendar is implemented. Spread and volatility filters do not substitute for one.

## Stop, restart and persistent state

- To stop, leave the terminal connected with Algo Trading enabled, click **STOP & FLATTEN**, then confirm in the **Trade** tab that the symbol is flat with no pending orders. The button pauses entries until the EA is reattached.
- Removing the EA attempts to cancel its entry and, by default, close its position. This is best effort only. Switching off Algo Trading or closing the terminal first prevents normal timer-based cleanup. Check the Trade tab manually.
- Entry orders prefer advertised GTC support; specified expiration remains a fallback when GTC is unavailable and specified expiry is supported. The normal 3-second cancellation and 30-second exit require the EA to keep running. A GTC order has no specified expiry and can remain at the broker after disconnection. The specified fallback has not been broker-validated.
- Reattaching with the same account, symbol, magic and `InpRunId` resumes the recorded run. Run P&L, completed positions, high-water marks, risk stops and unresolved-order state persist. Daily stops reset on the next UTC day; run stops do not.
- To intentionally begin a new measurement run, first confirm flat/no pending orders, then change `InpRunId`. Changing Magic or RunId does not close existing exposure. Keep all old log folders.
- An uncertain request result or an interrupted submission blocks new orders instead of retrying volume blindly. Inspect the Trade and History tabs and `events.csv` before starting a new run. If necessary, close/cancel the demo exposure manually.
- Foreign activity on XAUUSD halts the probe. If a foreign deal may have changed a shared netting position, the EA stops modifying or closing that position to avoid acting on mixed ownership; inspect it manually. Existing server SL/TP may still execute.
- Use only one EA instance for this account/symbol. The instance lock covers one terminal, not other terminal installations. Do not run the same experiment from two terminals.

## Retrieve the logs

In MT5, choose **File → Open Data Folder**, then open:

```text
MQL5\Files\XAU_ExecutionProbe\<symbol_date_time_uptime>\
```

The exact folder is also printed in the Experts log and displayed on the chart. After stopping and checking flat/no pending orders, ZIP the **whole run folder** and send it back. Include every folder if you restarted the EA. No account password is needed. Tester output is in the tester agent's separate file sandbox.

| File | Contents |
|---|---|
| `metadata.csv` | All actual inputs, symbol contract and lot rules, account currency, server, terminal build and initial reported ping |
| `ticks.csv` | Broker quote timestamps, Bid/Ask and whether the record came from a callback snapshot or history recovery |
| `requests.csv` | Submitted prices, SL/TP, lot size, order type, request duration, broker return codes and order/deal identifiers |
| `transactions.csv` | Observed trade transaction callbacks and contemporaneous quote snapshots |
| `deals.csv` | Deal prices, volumes, execution timestamps, order/position IDs, profit, commission, swap and fees |
| `events.csv` | Start/stop, filtering-related events, errors, risk stops and recovery messages |

The EA backfills deal records from MT5 history on attachment and during operation. Deals occurring after unload may appear only after a later reattachment to the same run. Keep MT5 account history available as a cross-check. Across restarted folders, deduplicate deals by account/server plus deal ticket, retaining the latest revision.

### Interpreting timing and fills

`call_duration_ms` measures elapsed local time around `OrderSend`: it is request/reply duration, not a measured server trigger-to-fill delay. Pending-order waiting time is not network latency. A terminal ping near 5 ms does not guarantee fills within 5 ms.

`*_server_msc` fields retain broker timestamps. `*_mono_us` fields use a local monotonic clock relative to this EA instance. Do not subtract these different clock domains, or compare monotonic values across restarts. A quote snapshot recorded when a callback runs is not proof of the quote at the exact server fill instant.

`WARMUP_HISTORY` and `HISTORY_READ` rows record historical quotes at the time they were read, not the time they first arrived. `ONTICK_SNAPSHOT` rows intentionally overlap with recovered quotes. Do not concatenate all three sources as a unique tick stream. History can contain multiple records sharing the same millisecond, so timestamp alone is not a safe tick deduplication key.

In version 1.02 tester runs, `TESTER_TICK` marks each delivered quote event used by the strategy. These runs do not emit history-prefetched quote rows. Multiple tester ticks with the same millisecond are retained as separate events.

For analysis, join order/deal identifiers to compare limit requests with actual entry prices, then examine subsequent prices and exit costs. `HISTORY_REVISION` records replace earlier values for the same deal. Demo results measure this demo server's behavior; they do not establish live execution quality.

## Troubleshooting

| Status or symptom | Check |
|---|---|
| No EA in Navigator | Both source files are together, MQ5 compiled successfully, Navigator refreshed |
| Init refused | Demo account connected; XAUUSD symbol; no foreign exposure; valid lot size and symbol support |
| Waiting for permissions | Connection, global Algo Trading, EA permission and account trading permission |
| Outside entry session | Current UTC time and weekday; final 30 seconds have no new entries |
| Warmup / spread / volatility / stale quotes | Wait for healthy current data; inspect Bid/Ask and chart status |
| Repeated rejection | Inspect `requests.csv` return codes/comments and `events.csv`; do not increase lot size to bypass errors |
| Waiting for reconciliation | MT5 order, deal and position state has not reconciled; preserve logs and inspect Trade/History tabs |
| Run stopped after restart | Same RunId retains target/risk/uncertainty stops; inspect the recorded reason |
| Tester says Target completed | In v1.03 expect `TESTER_COMPLETE` and normal completion after exposure reconciles; increase tester `InpTargetPositions` for a larger sample |
| Tester slows as the completed count grows | Upgrade to v1.04; preserve dates/inputs for comparison. If it still stalls, send the target value and the last tester Journal messages |

## Verification and references

See `VALIDATION.md` for the checks actually run and their limits. Strategy Tester can help check terminal integration, but generated or historical tester fills cannot answer the demo execution question.

Official MQL5 references used for this implementation:

- [OrderSend](https://www.mql5.com/en/docs/trading/ordersend): request acceptance is not proof that a deal has executed.
- [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction): transaction ordering and queue behavior.
- [CopyTicks](https://www.mql5.com/en/docs/series/copyticks): tick-history retrieval.
- [Symbol properties](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants): tick size, volume limits, stop/freeze levels, fill and expiration modes.
- [Edit, compile and run](https://www.mql5.com/en/book/intro/edit_compile_run).
- [Strategy Tester behavior](https://www.mql5.com/en/docs/runtime/testing): simulated time, timers, tick modes and isolated global variables.
- [GetMicrosecondCount](https://www.mql5.com/en/docs/common/getmicrosecondcount): elapsed program-runtime measurements.
- [TesterStop](https://www.mql5.com/en/docs/common/testerstop): normal early completion with accumulated test statistics.
