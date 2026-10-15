# XAUUSD Systematic Trading & Execution Research

Research project investigating short-horizon systematic trading and
execution dynamics in XAUUSD using MQL5 and MetaTrader 5.

The project combines tick-level backtesting with live-demo forward
testing to study momentum signals, transaction costs, execution quality,
exit behaviour and downside risk.

## Current Research Questions

- Can short-horizon momentum signals remain viable after transaction costs?
- How closely do MT5 backtests reproduce live-demo execution?
- Why can a high trade win rate coexist with poor overall profitability?
- Can alternative exit and risk-control mechanisms reduce loss severity?

## Methodology

The strategy is implemented in MQL5 and tested using tick-level XAUUSD
market data. Backtests are compared with live-demo execution logs to
analyse spreads, fills, holding periods, transaction costs and P&L.

## Current Findings

Initial testing suggests that trade hit rate alone is not sufficient to
determine strategy viability. A key issue identified is payoff asymmetry:
losing trades can be substantially larger than winning trades.

Current research therefore focuses on exit behaviour, holding-period
constraints and risk controls designed to reduce large losses without
overfitting historical data.

## Status

This is an ongoing research project and should not be interpreted as a
production trading system or evidence of future profitability.
