# XAU execution logger design — 13 October 2026

Build authorized by the user's 'lets build the expert', following the demo logger design in chat.
This is a new standalone MQL5 EA, not an existing repository change. Delivery is source + preset + instructions; the environment has no MetaEditor or MT5 compiler. Do not claim an EX5/native compile or broker test.

## Purpose and scope
Measure actual demo pending-entry prices, request round-trip durations, deal times, tick paths, exits and costs. Default XAUUSD chart symbol (suffix allowed), 0.01 lots validated without rounding up, 500-tick RMS volatility projected over 50 ticks, 3-second repricing, 30-second holding target, momentum threshold 1.5, spread ceiling 0.20, volatility ratio ceiling 2.

One resting entry at a time, alternating eligible sides while flat; exit is a position TP, with inventory-skewed adaptive repricing. This supports both hedging and netting without opening an opposing hedge. This is not identical to the historical two-sided-quote simulator. Preserve fixed initial broker SL; dynamic TP never changes SL. No scaling into positions.

## Controls
Hard demo guard on init and every trade request; no real-account override. Tester allowed only as explicitly labeled simulation. Exact symbol/account ownership, one instance per terminal/account/symbol, one owned position and total volume <= configured lot. Refuse foreign existing symbol exposure. Runtime foreign activity halts new entries; never close foreign positions. Serialized cancel/replace with order-history reconciliation, fail closed for ambiguous submissions. Server SL and TP on entry. Version 1.01 prefers advertised GTC support after the observed rejection of a 15-second specified expiry; terminal timer cancellation is required. Removal attempts cleanup while trading is permitted, with explicit residual-exposure warning on failure.

Demo strategy timers use local monotonic time. Version 1.02 tester strategy deadlines use simulated server/tick time with a nondecreasing clamp; request duration and observation logs still use host monotonic time. Broker timestamps are retained without subtracting local clocks. Demo CopyTicks drains tick history, including repeated same-millisecond ticks; history-recovered records are labeled and do not claim first receipt times. Tester warmup consumes only delivered OnTick events and never prefetches quote history. Do not claim exact broker trigger time. Report visible quote touch only.

Session 07–17 UTC; end entries 30 seconds early; real demo uses TimeGMT, tester uses manual server UTC+3. Daily EA P&L includes own realized profit/commission/swap/fee and floating profit/swap. Session loss and drawdown 10 account-currency units, plus total run loss/drawdown 30; persist risk high-water marks and halts across EA restarts within day. Stop at 200 completed positions per run. Risk triggers may overshoot. Pause button cancels/tries flattening and remains stopped until reattachment; daily loss automatically resets only on a new UTC day, run-level stop persists until a deliberately selected new RunId while flat. No scheduled-news calendar.

CSV files: metadata, ticks, requests, transactions, deals, events. Requests include check result, request id, start/end monotonic time, order/deal tickets and reply; deals include position/order ids, broker execution time, reference order/SL/TP and realized costs. Do not mix pending wait duration with network latency. Logging failure blocks entries and attempts cleanup.

Version 1.03 completes a tester run early at the sample target using TesterStop only after exposure and fill reconciliation. It flushes logs and persists state first, then retains normal deinitialization. This changes tester completion at the target only; demo behavior and all default inputs remain unchanged. A sample that ends at the target covers only part of the selected historical interval.

Version 1.04 keeps position/deal ticket tables sorted for binary lookup and preallocates the recovery ticket list. Tester accounting rebuilds on history count/day changes or deal callback invalidation, with a full audit every 60 simulated seconds and forced recovery on shutdown. History selection failures still halt; failed deal recovery stays dirty. Demo retains full history refresh cadence. Floating P&L, risk thresholds, strategy timers, tick ingestion and logging schemas are unchanged.

## Verification
Portable tests compile the exact math/state header as C++ and cover warmup, rolling signals, outward rounding, side selection, lot validation, risk and state decisions. Static packaging checks cover EA hooks/guards/schema. A fresh independent reviewer checks MQL API usage and race conditions. Native MQL compile, terminal events and broker compatibility remain explicitly unverified here.
