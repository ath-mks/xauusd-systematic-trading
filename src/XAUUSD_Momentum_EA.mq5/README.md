# XAU Execution Probe v3.01 — GBP cost-aware TP comparison

## v3.01 server-exit correction

v3.00 could classify its own broker-generated TP/SL market exit as foreign activity while that order was briefly visible. It then halted and could submit a redundant close after the server had already closed the position. v3.01 recognises same-symbol, same-magic BUY/SELL orders with server TP, SL or stop-out reasons. It tracks them through the existing persistent close barrier and waits for terminal order status, attributed deals and live inventory to agree before resuming entries. These exits are not counted or cancelled as pending entries. Different-magic activity and unexpected own order types still trigger the original safeguards.

## New inputs

| Input | Default | Meaning |
|---|---:|---|
| InpCostAwareTP | true | false = original v2 target; true = cost floor |
| InpCommissionRoundTripPerLot | 4.50 | GBP commission/fees for 1.00 lot, BOTH sides combined |
| InpTPProfitBuffer | 0.10 | Extra GBP profit per position, independent of lots |

The confirmed £0.45 round trip per 0.10 lot corresponds to 4.50 per full lot. A 0.05-lot position has £0.225 estimated round-trip costs, before broker rounding. The exit estimate is half the configured round-trip rate. Adjust for asymmetric charging, changed rates or anticipated per-lot exit fees. Zero is a deliberate zero estimate, not automatic detection. This input changes targets only: reported P&L always uses actual deal charges.

Initial pending-order TP uses requested entry and estimates for both commission sides. Once open, the floor uses actual attributed entry commission/fees from history, half the configured round-trip rate times current lots for the future exit, current negative swap and the profit buffer. Actual entry costs replace the entry estimate and are not doubled. Remaining volume receives its proportion of original entry costs following a partial close. This floor does not recover losses already realised on partial exits. Positive swap/rebates do not lower the target.

OrderCalcProfit converts price profit into GBP using current account/symbol conditions. The EA verifies estimated gross profit at the floor and rounds away from entry to the symbol tick size. Conversion failure halts new trading and triggers the existing flattening flow. Spread is already embedded in entry and executable exit prices: long TP is an exit bid; short TP is an exit ask. No second spread charge is added.

## Target behaviour and limits

Original candidate: long mid + delta − gamma × sigma²; short mid − delta + gamma × sigma², subject to broker distances and rounding. Cost-aware mode takes the larger of the long candidate and its floor, or the smaller of the short candidate and its floor. Targets can move both ways. There is no forced convergence over time or new predictive momentum model. Each position has its own floor; opposite positions do not share a basket break-even point.

Actual fill price/charges are incorporated only at an eligible successful TP amendment. History reconciliation, refresh cooldown and broker freeze rules can defer correction. A rapid fill→TP may execute before correction; the existing server TP remains during deferral. FX rates, fee revisions and execution can also change realised net profit. The floor is an estimated target policy, not a profit guarantee.

Fixed SL, 30-second holding exits and risk/session/feed exits remain active and can close at a net loss. A target floor never extends holding time or waits indefinitely for break-even. Compare whether fewer losing TP exits are offset by larger timed/SL losses.

## Presets

| Preset | Positions | Lots each | Mode | RunId |
|---|---:|---:|---|---:|
| XAU_v3_GBP_1Position_Original.set | 1 | 0.10 | Original | 10 |
| XAU_v3_GBP_1Position_CostAware.set | 1 | 0.10 | Cost-aware | 11 |
| XAU_v3_GBP_2Position_Original.set | 2 | 0.05 | Original | 20 |
| XAU_v3_GBP_2Position_CostAware.set | 2 | 0.05 | Cost-aware | 21 |

All use gamma 0.5706715943, daily opening cap 2000, overall target 0 (full selected test period), 3000ms refresh and 30-second holding limit. Maximum gross open/pending volume is 0.10 lot. Daily cap counts distinct first-filled positions and resets at 00:00 UTC; exits continue at the cap. InpMaxPositions sets simultaneous positions; InpMaxPositionsPerDay sets daily openings.

Risk triggers remain £100 session loss/drawdown and £300 run loss/drawdown. These are exit triggers, not guaranteed loss limits. UTC session remains 07:00–17:00; broker offset +3 is provisional. Use a fresh RunId for an independent demo run, changing it only while flat.

Buffer is per position: two positions each target £0.10 extra by default, versus £0.10 for one position. Set £0.05 in the two-position cost-aware preset if comparing equal aggregate buffers. Original mode ignores the buffer/commission-target inputs.

## Logs and evaluation

Logs: MQL5/Files/XAU_ExecutionProbe_v3/... or the tester agent's equivalent folder. Keep all six CSVs. Metadata includes new inputs. TP_TARGET events record ticket, mode, old/new TP, floor, estimated GBP costs and buffer for attempted target changes. Check the corresponding request result for acceptance. Deal rows retain broker exit reasons, commission, swap and fees.

Compare net profit after costs, maximum equity drawdown, completed trades, holding time, TP/SL/timed exit counts and net P&L per exit category. Identical entry rules can produce different later fills/counts because holding times change. No historical backtest or profitability result is included.

Use STOP & FLATTEN with MT5 connected and Algo Trading enabled before removal. Confirm positions/orders are gone. Uncertain broker-result protection remains active. Server stops remain after removal, but EA holding timers stop.

See VALIDATION.md. Official account-currency conversion reference: https://www.mql5.com/en/docs/trading/ordercalcprofit
