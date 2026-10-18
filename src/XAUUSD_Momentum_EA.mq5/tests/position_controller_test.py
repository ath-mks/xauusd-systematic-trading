"""Run actual EA scan/management/controller functions with deterministic MT5 API fixtures.
Transport fixtures record requests; they do not model broker fills or latency.
"""
from pathlib import Path
import re, subprocess, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'XAU_ExecutionProbe_v3.mq5').read_text()
def function(name):
    m=re.search(r'\b(?:bool|void|Exposure)\s+'+name+r'\s*\(',SOURCE)
    if not m:return ''
    start=SOURCE.index('{',m.end());end=start+1;depth=1
    while depth:
        depth+=(SOURCE[end]=='{')-(SOURCE[end]=='}');end+=1
    return SOURCE[m.start():end]

STUBS=r'''
#include <algorithm>
#include <cassert>
#include <cmath>
#include <string>
#include <vector>
using ulong=unsigned long;using string=std::string;
double MathMax(double a,double b){return std::fmax(a,b);} double MathMin(double a,double b){return std::fmin(a,b);}
double MathSqrt(double a){return std::sqrt(a);} double MathFloor(double a){return std::floor(a);}
double MathCeil(double a){return std::ceil(a);} double MathAbs(double a){return std::fabs(a);}
'''
STUBS+='#include "'+str(ROOT/'MMCore.mqh')+'"\n#include "'+str(ROOT/'MMPositionBook.mqh')+'"\n'
STUBS+=r'''
using ENUM_ORDER_TYPE=int;
bool MathIsValidNumber(double x){return std::isfinite(x);}
template<class... T> string StringFormat(string,T...){return "target log";}
bool InpCostAwareTP=false;double InpCommissionRoundTripPerLot=9,InpTPProfitBuffer=.10;
struct Ledger{ulong id;double entrycost=0.225,entryvolume=.05;};
std::vector<Ledger> g_ledger;
int LedgerLowerBound(ulong id){for(int i=0;i<(int)g_ledger.size();i++)if(g_ledger[i].id==id)return i;return (int)g_ledger.size();}
template<class T> int ArraySize(const std::vector<T>& x){return (int)x.size();}

enum {POSITION_SYMBOL,POSITION_MAGIC,POSITION_IDENTIFIER,POSITION_TYPE,POSITION_VOLUME,
 POSITION_PRICE_OPEN,POSITION_PROFIT,POSITION_SWAP,POSITION_SL,POSITION_TP,POSITION_TIME_MSC,
 ORDER_SYMBOL,ORDER_MAGIC,ORDER_TYPE,ORDER_VOLUME_CURRENT,ORDER_VOLUME_INITIAL,ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT,ORDER_TYPE_BUY,
 ORDER_TYPE_SELL,TRADE_ACTION_SLTP,POSITION_TYPE_BUY,POSITION_TYPE_SELL,
 ORDER_REASON,ORDER_REASON_EXPERT,ORDER_REASON_CLIENT,ORDER_REASON_TP,ORDER_REASON_SL,ORDER_REASON_SO};
struct Pos{ulong ticket,id;double volume=.05,sl=99,tp=100.23;long opened=100000,type=POSITION_TYPE_BUY;};
std::vector<Pos> positions;int selected=-1;
int PositionsTotal(){return (int)positions.size();}
ulong PositionGetTicket(int i){selected=i;return positions.at(i).ticket;}
bool PositionSelectByTicket(ulong ticket){for(int i=0;i<PositionsTotal();i++)if(positions[i].ticket==ticket){selected=i;return true;}return false;}
string PositionGetString(int){return "XAUUSD";}
long PositionGetInteger(int p){auto &x=positions.at(selected);switch(p){case POSITION_MAGIC:return 7;case POSITION_IDENTIFIER:return x.id;case POSITION_TYPE:return x.type;case POSITION_TIME_MSC:return x.opened;default:return 0;}}
double PositionGetDouble(int p){auto &x=positions.at(selected);switch(p){case POSITION_PRICE_OPEN:return 100;case POSITION_VOLUME:return x.volume;case POSITION_SL:return x.sl;case POSITION_TP:return x.tp;default:return 0;}}
bool order=false;double order_volume=.05,order_initial=.05;long fixture_order_type=ORDER_TYPE_BUY_LIMIT;
long fixture_order_magic=7,fixture_order_reason=ORDER_REASON_EXPERT;
int OrdersTotal(){return order?1:0;}ulong OrderGetTicket(int){return 88;}
string OrderGetString(int){return "XAUUSD";}long OrderGetInteger(int p){return p==ORDER_TYPE?fixture_order_type:(p==ORDER_REASON?fixture_order_reason:fixture_order_magic);}
double OrderGetDouble(int p){return p==ORDER_VOLUME_CURRENT?order_volume:order_initial;}
struct Exposure{int positions=0,orders=0;bool foreign=false,partial=false;double volume=0,pendingvolume=0;ulong position=0,order=0,exitorder=0;};
struct MqlTick{long time_msc=100000;double bid=100,ask=100.1;};
struct MqlTradeRequest{int action=0;ulong position=0;double sl=0,tp=0;};struct MqlTradeResult{};
template<class T>void ZeroMemory(T &v){v=T();}
struct MqlDateTime{int hour=7,min=0,sec=0,day_of_week=4;};
void TimeToStruct(long,MqlDateTime &dt){dt=MqlDateTime();}
ulong clock_us=100000000,g_nexttradeus=0,g_quoteus=100000000,g_lastnewus=100000000;
ulong g_summaryus=0,g_flushus=100000000,g_displayus=100000000,g_entrybarrier=0,g_closebarrier=0;
ulong g_posid=0,g_posdeadlineus=0,g_modifyus=0,g_closedeal=0;
bool g_ready=true,g_busy=false,g_test=true,g_testerstopping=false,g_caughtup=true,g_historydirty=true,g_canceldeferred=false;
bool g_runhalt=false,g_dayhalt=false,g_paused=false,g_iofail=false,g_ambiguous=false,g_contaminated=false,g_closepending=false;
bool fixture_cancel_ok=true,fixture_reconcile=true,fixture_ledger=true,fixture_fill_on_resolve=false,fixture_exit_on_resolve=false;int g_day=1,g_completed=0,g_dayentries=0,g_errors=0;
double g_dayrealized=0,g_realized=0,g_daypeak=0,g_runpeak=0,g_float=0,g_vstep=.01,g_ticksize=.01;
long InpMagic=7;int InpMaxPositions=2,InpMaxPositionsPerDay=2000,InpTargetPositions=2000,InpRefreshMs=3000,InpMaxQuoteAgeMs=6000;
int InpMaxHoldingSeconds=30,InpMaxTickAgeMs=5000,InpMaxConsecutiveErrors=5,InpStartHourUTC=7,InpEndHourUTC=17;
double InpLots=.05,InpSessionLoss=100,InpSessionDrawdown=100,InpRunLoss=300,InpRunDrawdown=300;
double InpMinDistance=.1,InpVolMultiplier=1,InpInventoryGamma=.5706715943,InpMaxSpread=.2,InpVolSpikeRatio=2;
bool InpEnableDemoOrders=true;string g_symbol="XAUUSD",g_status;
double fixture_bid=100;MMSignal g_signal{.2,.2,0,true};MMPositionBook g_positions;
int entries=0,cancels=0;std::vector<ulong> modified,closed;
ulong StrategyNowUS(){return clock_us;}long TimeCurrent(){return (long)(clock_us/1000000);}
long TimeTradeServer(){return TimeCurrent();}long UTCNow(){return TimeCurrent();}int DayNumber(){return 1;}
bool IsDemo(){return true;}bool AccountMatches(){return true;}bool TradePermissions(){return true;}
void PumpTicks(){g_lastnewus=clock_us;}void DrainDeals(){}void RefreshPnL(){}
void SaveRisk(){}void SaveOrders(){}void GlobalVariablesFlush(){}void FlushLogs(){}void Display(){}
void Event(string,string){}void StopRun(string){g_runhalt=true;}
bool LiveLedgerMatches(){return fixture_ledger;}
bool SymbolInfoTick(string,MqlTick &t){t=MqlTick();t.bid=fixture_bid;t.ask=fixture_bid+.1;t.time_msc=(long)(clock_us/1000);return true;}
bool ResolveClose(){if(fixture_reconcile)g_closepending=false;return !g_closepending;}
bool ResolveBarrier(ulong &t){if(fixture_exit_on_resolve){order=true;fixture_order_type=ORDER_TYPE_BUY;fixture_order_reason=ORDER_REASON_TP;fixture_exit_on_resolve=false;}if(fixture_fill_on_resolve){positions.push_back({3,1003,.05,99,100.23,100000,POSITION_TYPE_BUY});order=false;fixture_fill_on_resolve=false;}if(!order&&fixture_reconcile)t=0;return t==0;}
bool FinishTesterAtTarget(const Exposure &){return false;}
bool Cancel(ulong,string){cancels++;g_nexttradeus=clock_us+150000;if(!fixture_cancel_ok)return false;order=false;return true;}
void PlaceEntry(const MqlTick &){entries++;order=true;order_volume=InpLots;order_initial=InpLots;g_quoteus=clock_us;}
bool ClosePosition(ulong ticket,string){
 if(g_closepending||!fixture_ledger)return false;
 closed.push_back(ticket);positions.erase(std::remove_if(positions.begin(),positions.end(),[&](const Pos &p){return p.ticket==ticket;}),positions.end());
 g_closepending=true;g_nexttradeus=clock_us+150000;return true;
}
double MinimumDistance(){return .01;}double P(double x){return x;}
bool Send(MqlTradeRequest &r,string,MqlTradeResult &){
 assert(r.action==TRADE_ACTION_SLTP);assert(PositionSelectByTicket(r.position));
 positions[selected].tp=r.tp;modified.push_back(r.position);g_nexttradeus=clock_us+150000;return true;
}
void add(ulong ticket,long opened=100000,double tp=100.23){g_ledger.push_back({ticket+1000,.225,.05});positions.push_back({ticket,ticket+1000,.05,99,tp,opened,POSITION_TYPE_BUY});}
void advance(){clock_us+=200000;}
'''

STUBS+=r'''
bool conversion_ok=true;
bool OrderCalcProfit(int type,string,double volume,double open,double close,double &profit){if(!conversion_ok)return false;profit=(type==ORDER_TYPE_BUY?1:-1)*(close-open)*80*volume;return true;}
'''

CASES=r'''
int main(int argc,char** argv){
 assert(argc==2);string test=argv[1];g_positions.Reset();
 if(test=="server_tp"||test=="server_sl"||test=="server_so"||test=="server_tp_risk"){
  add(1);order=true;fixture_order_type=test=="server_sl"?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
  fixture_order_reason=test=="server_sl"?ORDER_REASON_SL:(test=="server_so"?ORDER_REASON_SO:ORDER_REASON_TP);
  if(test=="server_tp_risk")g_dayhalt=true;
  Exposure e=Scan();assert(!e.foreign&&e.orders==0&&e.exitorder==88&&!EntryCapacity(e));
  Drive();assert(!g_runhalt&&g_closepending&&g_closebarrier==88&&closed.empty()&&modified.empty()&&cancels==0&&entries==0);
 }else if(test=="server_flat"){
  order=true;fixture_order_type=ORDER_TYPE_BUY;fixture_order_reason=ORDER_REASON_TP;
  Drive();assert(!g_runhalt&&entries==0&&cancels==0&&g_closepending);
  order=false;fixture_reconcile=false;fixture_ledger=false;advance();Drive();assert(entries==0);
  fixture_reconcile=true;fixture_ledger=true;advance();Drive();assert(entries==1&&!g_runhalt);
 }else if(test=="late_server_exit"){
  add(1);fixture_exit_on_resolve=true;Drive();
  assert(!g_runhalt&&g_closepending&&g_closebarrier==88&&closed.empty()&&modified.empty()&&entries==0);
 }else if(test=="foreign_exit"){
  order=true;fixture_order_type=ORDER_TYPE_BUY;fixture_order_reason=ORDER_REASON_TP;fixture_order_magic=99;
  assert(Scan().foreign);Drive();assert(g_runhalt&&entries==0);
 }else if(test=="unexpected_own_market"){
  order=true;fixture_order_type=ORDER_TYPE_BUY;fixture_order_reason=ORDER_REASON_CLIENT;
  assert(Scan().foreign);Drive();assert(g_runhalt&&entries==0);
 }else if(test=="foreign_entry"){
  order=true;fixture_order_magic=99;assert(Scan().foreign);Drive();assert(g_runhalt&&entries==0);
 }else if(test=="cost_long"){
  InpCostAwareTP=true;g_signal.sigma=3;add(1,100000,100.5);Drive();
  assert(modified.size()==1&&std::abs(positions[0].tp-100.14)<1e-8);
 }else if(test=="cost_short"){
  InpCostAwareTP=true;g_signal.sigma=3;add(1,100000,99.5);positions[0].type=POSITION_TYPE_SELL;positions[0].sl=101;Drive();
  assert(modified.size()==1&&std::abs(positions[0].tp-99.86)<1e-8);
 }else if(test=="cost_due"){
  InpCostAwareTP=true;add(1,70000,100.5);Drive();assert(closed.size()==1&&modified.empty());
 }else if(test=="cost_conversion_failure"){
  InpCostAwareTP=true;conversion_ok=false;add(1,100000,100.5);Drive();assert(g_runhalt&&modified.empty()&&entries==0);advance();Drive();assert(closed.size()==1&&entries==0);
 }else if(test=="existing"){
  add(1);Drive();assert(entries==1&&closed.empty());
 }else if(test=="pending"){
  add(1,100000,100.5);order=true;g_entrybarrier=88;Drive();
  assert(cancels==0&&entries==0&&modified.size()==1&&modified[0]==1);
 }else if(test=="due"){
  add(1,100000,100.5);add(2,70000,100.5);Drive();
  assert(closed.size()==1&&closed[0]==2&&modified.empty()&&entries==0);
 }else if(test=="refresh"){
  add(1,100000,100.5);add(2,100000,100.5);Drive();advance();Drive();
  assert(modified.size()==2&&modified[0]!=modified[1]&&entries==0);
 }else if(test=="freeze"){
  add(1,100000,100.005);add(2,100000,100.5);Drive();
  assert(modified.size()==1&&modified[0]==2);
 }else if(test=="partial"){
  add(1);positions[0].volume=.02;order=true;order_volume=.03;Drive();
  assert(cancels==1&&!g_runhalt&&entries==0);
 }else if(test=="risk"){
  add(1);add(2);order=true;g_runhalt=true;Drive();advance();Drive();advance();Drive();
  assert(cancels==1&&closed.size()==2&&entries==0&&positions.empty());
 }else if(test=="filter"){
  add(1,100000,100.5);InpMaxSpread=.05;Drive();
  assert(entries==0&&modified.size()==1);
 }else if(test=="reconciliation"){
  add(1);g_entrybarrier=88;fixture_reconcile=false;Drive();assert(entries==0);
  g_entrybarrier=0;fixture_ledger=false;advance();Drive();assert(entries==0);
 }else if(test=="close_pending"){
  add(1,70000,100.5);g_closepending=true;fixture_reconcile=false;Drive();
  assert(entries==0&&closed.empty()&&modified.empty());
 }else if(test=="cap"){
  add(1);add(2);Drive();assert(entries==0&&!g_runhalt);
  InpMaxPositions=3;advance();Drive();assert(entries==1);
 }else if(test=="sample"){
  add(1);g_completed=1999;Drive();assert(entries==0);
 }else if(test=="cancel_failure"){
  add(1);add(2);order=true;fixture_cancel_ok=false;g_runhalt=true;
  for(int i=0;i<10;i++){Drive();advance();}
  assert(closed.size()==2&&entries==0&&cancels>0);
 }else if(test=="fair_refresh"){
  InpMaxPositions=30;InpMaxHoldingSeconds=60;for(int i=1;i<=30;i++)add(i,100000,100.5);
  for(int i=0;i<140;i++){fixture_bid=100+.04*std::sin(i*.23);Drive();advance();}
  for(ulong i=1;i<=30;i++)assert(std::find(modified.begin(),modified.end(),i)!=modified.end());
 }else if(test=="late_fill"){
  order=true;g_entrybarrier=88;fixture_fill_on_resolve=true;Drive();
  assert(!g_runhalt&&g_positions.Find(1003)>=0);
 }else if(test=="close_order"){
  add(1);add(2);order=true;fixture_order_type=ORDER_TYPE_BUY;g_closepending=true;g_closebarrier=88;fixture_reconcile=false;Drive();
  assert(!g_runhalt&&entries==0&&closed.empty());
 }else if(test=="full_book"){
  InpMaxPositions=100;for(int i=1;i<=100;i++)add(i);Drive();
  positions.erase(positions.begin()+40);add(500);advance();Drive();
  assert(!g_runhalt&&g_positions.Count()==100&&g_positions.Find(1500)>=0);
 }else if(test=="old_quote"){
  add(1,100000,100.5);order=true;g_quoteus=clock_us-6000000;Drive();
  assert(cancels==1&&modified.empty());
 }else if(test=="fractional"){
  add(1,70050);clock_us=100050000;Drive();assert(closed.size()==1&&closed[0]==1);
 }else if(test=="cleanup"){
  add(1);add(2);CleanupOwnedPositions();assert(closed.size()==2&&positions.empty());
 }else if(test=="cleanup_wait"){
  add(1);g_closepending=true;fixture_reconcile=false;CleanupOwnedPositions();assert(closed.empty());
 }else if(test=="daily"){
  add(1,100000,100.5);g_dayentries=InpMaxPositionsPerDay;Drive();
  assert(entries==0&&modified.size()==1&&!g_runhalt&&!g_dayhalt);
  g_dayentries=0;advance();Drive();assert(entries==1);
 }else if(test=="flat"){
  Drive();assert(entries==1);
 }else return 2;
}
'''

class PositionController(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(prefix='xep_v2_controller_');cls.addClassCleanup(cls.tmp.cleanup)
        cls.binary=Path(cls.tmp.name)/'controller'
        names=['CostFloor','Scan','EntryCapacity','SyncPositionStates','ManagePosition','ManagePositions','CleanupOwnedPositions','Drive']
        actual='\n'.join(function(n) for n in names)
        if not function('CleanupOwnedPositions'):actual+='\nvoid CleanupOwnedPositions(){}\n'
        cpp=Path(cls.tmp.name)/'controller.cpp';cpp.write_text(STUBS+actual+CASES)
        subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-pedantic',str(cpp),'-o',str(cls.binary)],check=True)
    def run_case(self,name):subprocess.run([str(self.binary),name],check=True)
    def test_own_tp_is_reconciled_without_foreign_halt_or_extra_close(self):self.run_case('server_tp')
    def test_own_sl_is_reconciled_without_foreign_halt(self):self.run_case('server_sl')
    def test_own_stopout_is_reconciled_without_foreign_halt(self):self.run_case('server_so')
    def test_risk_stop_does_not_duplicate_server_exit(self):self.run_case('server_tp_risk')
    def test_new_entry_waits_for_server_exit_and_ledger(self):self.run_case('server_flat')
    def test_server_exit_appearing_during_reconciliation_is_caught(self):self.run_case('late_server_exit')
    def test_different_magic_tp_still_halts(self):self.run_case('foreign_exit')
    def test_unexpected_own_market_order_still_halts(self):self.run_case('unexpected_own_market')
    def test_different_magic_entry_still_halts(self):self.run_case('foreign_entry')
    def test_cost_long_uses_entry_cost_and_exit_estimate(self):self.run_case('cost_long')
    def test_cost_short_rounds_outward(self):self.run_case('cost_short')
    def test_cost_floor_never_prevents_holding_exit(self):self.run_case('cost_due')
    def test_failed_conversion_halts_without_modifying_tp(self):self.run_case('cost_conversion_failure')
    def test_existing_position_allows_another_entry(self):self.run_case('existing')
    def test_pending_entry_does_not_block_tp_management(self):self.run_case('pending')
    def test_oldest_due_exit_precedes_tp_updates(self):self.run_case('due')
    def test_positions_refresh_independently(self):self.run_case('refresh')
    def test_frozen_first_tp_does_not_starve_another(self):self.run_case('freeze')
    def test_partial_entry_remainder_is_canceled_without_false_halt(self):self.run_case('partial')
    def test_risk_stop_cancels_entry_and_flattens_all_positions(self):self.run_case('risk')
    def test_entry_filter_preserves_existing_position_management(self):self.run_case('filter')
    def test_unreconciled_volume_prevents_new_entries(self):self.run_case('reconciliation')
    def test_unconfirmed_close_is_not_repeated(self):self.run_case('close_pending')
    def test_cap_can_be_raised_without_disabling_limits(self):self.run_case('cap')
    def test_outstanding_position_reserves_sample_target(self):self.run_case('sample')
    def test_daily_cap_pauses_entries_but_preserves_exits_and_can_reset(self):self.run_case('daily')
    def test_expired_entry_is_canceled_before_tp_updates(self):self.run_case('old_quote')
    def test_holding_deadline_uses_fractional_server_time(self):self.run_case('fractional')
    def test_removal_attempts_each_confirmed_position_close(self):self.run_case('cleanup')
    def test_removal_does_not_repeat_an_unconfirmed_close(self):self.run_case('cleanup_wait')
    def test_working_close_is_not_reserved_as_a_new_entry(self):self.run_case('close_order')
    def test_full_timer_book_reclaims_closed_identifiers_before_replacement(self):self.run_case('full_book')
    def test_fill_during_reconciliation_gets_a_timer_before_management(self):self.run_case('late_fill')
    def test_cancel_rejection_does_not_starve_risk_exits(self):self.run_case('cancel_failure')
    def test_large_caps_refresh_every_position_under_changing_quotes(self):self.run_case('fair_refresh')
    def test_flat_probe_can_place_first_entry(self):self.run_case('flat')

if __name__=='__main__':unittest.main()
