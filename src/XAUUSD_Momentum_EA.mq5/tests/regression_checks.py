"""Source integration checks, not a substitute for MetaEditor/broker tests."""
from pathlib import Path
import unittest
S=(Path(__file__).resolve().parents[1]/'XAU_ExecutionProbe.mq5').read_text()
class ControllerRegression(unittest.TestCase):
 def test_clock_read_after_history_pump(self):
  self.assertIn('PumpTicks();DrainDeals();now=StrategyNowUS();',S)
 def test_day_rollover_forces_history_refresh(self):
  self.assertIn('g_daypeak=0;g_summaryus=0;',S)
 def test_quote_age_checked_separately(self):
  self.assertIn('MMFeedFresh(',S)
 def test_restart_uses_remaining_holding_budget(self):
  self.assertIn('MMRemainingHoldMs(',S)
 def test_barrier_reconciles_fills_and_live_inventory(self):
  self.assertIn('HistoryOrderGetDouble(ticket,ORDER_VOLUME_INITIAL)',S)
  self.assertIn('LiveLedgerMatches()',S)
  self.assertNotIn('if(closing||e.positions>0||PositionNetFlat(ticket))',S)
 def test_close_tracks_deal_only_reply(self):
  self.assertIn('g_closepending=true;',S);self.assertIn('g_closedeal=res.deal;',S)
 def test_foreign_netting_guard(self):
  self.assertIn('g_contaminated',S);self.assertIn('FOREIGN_DEAL',S)
 def test_recover_deals_after_cleanup(self):
  deinit=S[S.index('void OnDeinit('):]
  self.assertIn('RefreshPnL();DrainDeals();',deinit)
  self.assertIn('HISTORY_RECOVERED',S)
 def test_account_is_bound(self):
  self.assertIn('AccountMatches()',S)
if __name__=='__main__': unittest.main()
