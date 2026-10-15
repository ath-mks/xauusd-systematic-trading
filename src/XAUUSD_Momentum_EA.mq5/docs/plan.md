# XAU execution logger implementation plan

> For agentic workers: use executing-plans. The user has authorized the build; proceed inline and use a fresh reviewer at completion.

Goal: deliver a demo-only execution probe with interpretable logs and installation instructions.
Architecture: standalone MQL5 EA plus shared portable math/state header; sequential order controller, timer risk management, transaction logging and terminal-persistent risk state.
Tech stack: MQL5, Python test driver, C++17 shared-header tests.
Spec: docs/design.md

## Global constraints
Demo account only (tester distinctly labeled). No DLL/WebRequest dependencies. No assumed compiler availability. One entry/position, support hedging and netting, never manage foreign positions. No self-deployment/trading from this session.

## Review focus
Cancel/fill and timeout races; partial fills and netting interference; persistence/restarts; tick-history and broker/local clock separation; exact MQL5 API/compile compatibility.

## Task 1: portable strategy logic
- [x] Write tests/core_test.cpp for 1001-tick warmup, flat/known increments, rolling window wraparound, outward tick rounding, directional quote/TP bounds, momentum side choice, volume bounds and risk/state priorities.
- [x] Compile before MMCore.mqh exists; expected missing implementation failure.
- [x] Implement MMCore.mqh and compile/run test executable; expected all assertions pass.

## Task 2: EA and preset
- [x] Implement XAU_ExecutionProbe.mq5 with the controllers and six logs in the spec, plus XAU_Demo_Execution.set.
- [x] Add checks for input/preset alignment, request guard centralization, event hooks and CSV field consistency; expected pass.
- [x] Verify standalone packaging includes shared header beside MQ5. No EX5 claim.

## Task 3: verification and delivery
- [x] Write README for compile/load/run/status/stopping/log retrieval and limitations; include source/API references.
- [x] Request independent code review; fix important findings with targeted regression checks.
- [x] Run all checks and inspect final source/package. ZIP creation, persistent saving and install instructions are tracked by the delivery workflow.
