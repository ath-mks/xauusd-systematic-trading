# XAU ExecutionProbe 1.04

Demo-only MT5 Expert Advisor for measuring XAUUSD pending-order execution. It places one entry order at a time, manages at most one position, and records quotes, requests, transactions, fills and costs. It refuses real accounts. Strategy Tester runs are explicitly labeled simulations.


## Version 1.04: reduce history work in longer backtests

Raising `InpTargetPositions` allows a longer run and a larger trade history. Earlier versions rebuilt that history every simulated second and repeatedly searched every stored position and deal. These nested linear searches caused sharply increasing work as the sample grew.

Version 1.04 uses sorted ticket tables with binary searches. In tester mode it reuses unchanged history totals, invalidating them on a deal-count change, a deal add/update/delete callback, a day change or a backward clock change. It also performs a full audit at least once per simulated minute and forces final recovery during shutdown. A failed history selection still halts the run. Demo history refresh cadence remains unchanged. Inputs, quote timing, tick ingestion, CSV schemas and risk thresholds are unchanged.

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
