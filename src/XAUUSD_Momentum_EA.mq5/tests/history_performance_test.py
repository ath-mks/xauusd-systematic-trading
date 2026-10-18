"""Run actual EA history code with deterministic API stubs; not an MT5 emulator."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'XAU_ExecutionProbe_v3.mq5').read_text()

def function(name):
    match = re.search(r'(?:int|bool|void)\s+' + name + r'\s*\(', SOURCE)
    if not match:
        return ''
    start = SOURCE.index('{', match.end())
    end, depth = start + 1, 1
    while depth:
        depth += (SOURCE[end] == '{') - (SOURCE[end] == '}')
        end += 1
    return SOURCE[match.start():end]

STUBS = r'''
#include <algorithm>
#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>
using ulong=unsigned long;
using datetime=long;
using string=std::string;
long comparisons=0, reads=0, rows=0;
struct Id {
 ulong value=0;
 Id()=default; Id(ulong x):value(x){}
 operator ulong()const {comparisons++;return value;}
};
struct PositionLedger {Id id;double netvol=0;bool entry=false;bool exit=false;long firstentry=0;double entrycost=0,entryvolume=0;};
struct LoggedDeal {Id ticket;double price=0,volume=0,profit=0,commission=0,swap=0,fee=0;};
std::vector<PositionLedger> g_ledger;
std::vector<LoggedDeal> g_loggedDeals;
template<class T> int ArraySize(const std::vector<T>& a){return (int)a.size();}
template<class T> int ArrayResize(std::vector<T>& a,int n,int reserve=0){
 if(n>(int)a.capacity())a.reserve(n+reserve);a.resize(n);return n;
}
bool g_test=true,g_historydirty=true,g_runhalt=false,g_contaminated=false;
int g_historycount=-1,g_historyday=-1,g_day=1,g_completed=0,g_dayentries=0;
datetime g_historytime=0,g_epoch=0,clock_now=90000;
long InpMagic=7;
int InpServerUTCOffsetHours=0;
string g_symbol="XAUUSD";
double g_realized=0,g_dayrealized=0,g_vstep=0.01;
bool history_ok=true;
int margin_mode=0;
enum {DEAL_SYMBOL,DEAL_MAGIC,DEAL_POSITION_ID,DEAL_TYPE,DEAL_TIME,DEAL_ENTRY,
 DEAL_VOLUME,DEAL_PROFIT,DEAL_COMMISSION,DEAL_SWAP,DEAL_FEE,DEAL_ORDER,
 DEAL_TIME_MSC,DEAL_REASON,DEAL_PRICE,ACCOUNT_MARGIN_MODE,
 ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,ORDER_PRICE_OPEN,ORDER_SL,ORDER_TP,
 ORDER_TIME_SETUP_MSC,ORDER_TIME_DONE_MSC,ORDER_TYPE};
enum {DEAL_TYPE_BUY=101,DEAL_TYPE_SELL,DEAL_TYPE_OTHER};
enum {DEAL_ENTRY_IN=201,DEAL_ENTRY_OUT,DEAL_ENTRY_INOUT,DEAL_ENTRY_OUT_BY};
struct Deal {
 ulong ticket,id;long magic,time,type,entry;double vol,profit,commission,swap,fee,price;
 string symbol="XAUUSD";
};
std::vector<Deal> deals;
std::vector<ulong> selected;
Deal& D(ulong t){for(auto& d:deals)if(d.ticket==t)return d;std::abort();}
datetime TimeCurrent(){return clock_now;}
bool HistorySelect(datetime,datetime){
 if(!history_ok)return false;selected.clear();for(auto& d:deals)selected.push_back(d.ticket);return true;
}
int HistoryDealsTotal(){return (int)selected.size();}
ulong HistoryDealGetTicket(int i){reads++;return selected.at(i);}
bool HistoryDealSelect(ulong t){
 for(auto& d:deals)if(d.ticket==t){selected.assign(1,t);return true;}return false;
}
string HistoryDealGetString(ulong t,int){return D(t).symbol;}
long HistoryDealGetInteger(ulong t,int p){
 auto& d=D(t);
 switch(p){case DEAL_MAGIC:return d.magic;case DEAL_POSITION_ID:return d.id;
 case DEAL_TYPE:return d.type;case DEAL_TIME:return d.time;case DEAL_ENTRY:return d.entry;
 case DEAL_TIME_MSC:return d.time*1000;case DEAL_ORDER:return d.ticket+10000;
 default:return 0;}
}
double HistoryDealGetDouble(ulong t,int p){
 auto& d=D(t);
 switch(p){case DEAL_VOLUME:return d.vol;case DEAL_PROFIT:return d.profit;
 case DEAL_COMMISSION:return d.commission;case DEAL_SWAP:return d.swap;
 case DEAL_FEE:return d.fee;case DEAL_PRICE:return d.price;default:return 0;}
}
bool HistoryOrderSelect(ulong){return true;}
double HistoryOrderGetDouble(ulong,int){return 0;}
long HistoryOrderGetInteger(ulong,int){return 0;}
int AccountInfoInteger(int){return margin_mode;}
void StopRun(string){g_runhalt=true;}
double MathMax(double a,double b){return std::fmax(a,b);}
double MathAbs(double x){return std::abs(x);}
struct MqlTick {long time_msc=0;double bid=0,ask=0;};
void ZeroMemory(MqlTick& t){t=MqlTick();}
bool SymbolInfoTick(string,MqlTick&){return true;}
ulong GetMicrosecondCount(){return 1;}
datetime UTCNow(){return clock_now;}
int g_deals=1;
template<class... T> unsigned FileWrite(int,T...){rows++;return 1;}
void W(unsigned){}
bool LogDeal(ulong,bool);
'''

CASES = r'''
void add(ulong ticket,ulong id,long type,long entry,double volume,double profit=0,
         long when=90000,long magic=7){
 deals.push_back({ticket,id,magic,when,type,entry,volume,profit,-0.1,0,0,2000,"XAUUSD"});
}
void baseline(){
 add(30,900,DEAL_TYPE_BUY,DEAL_ENTRY_IN,0.01,0,80000);
 add(10,900,DEAL_TYPE_SELL,DEAL_ENTRY_OUT,0.01,2);
 add(20,100,DEAL_TYPE_SELL,DEAL_ENTRY_IN,0.02);
 add(40,100,DEAL_TYPE_BUY,DEAL_ENTRY_OUT,0.01,1);
}
void close(double actual,double expected){assert(std::abs(actual-expected)<1e-8);}
int main(int argc,char** argv){
 assert(argc==2);string test=argv[1];
 if(test=="lookups"){
  for(int i=0;i<20000;i++)LedgerIndex(2*i+2);
  comparisons=0;
  for(int i=0;i<20000;i++){assert(KnownPosition(2*i+2));assert(!KnownPosition(2*i+1));}
  std::cout<<"Position lookup comparisons: "<<comparisons<<std::endl;
  assert(comparisons<700000);
  for(int i=0;i<20000;i++){LoggedDeal d;d.ticket=2*i+2;g_loggedDeals.push_back(d);}
  comparisons=0;
  for(int i=0;i<20000;i++){assert(LoggedIndex(2*i+2)==i);assert(LoggedIndex(2*i+1)<0);}
  std::cout<<"Deal lookup comparisons: "<<comparisons<<std::endl;
  assert(comparisons<700000);
  g_ledger.clear();
  LedgerIndex(900);LedgerIndex(100);LedgerIndex(500);LedgerIndex(100);
  assert(ArraySize(g_ledger)==3);
  assert(KnownPosition(900)&&KnownPosition(100)&&KnownPosition(500)&&!KnownPosition(200));
 }else if(test=="accounting"){
  baseline();RefreshPnL();
  assert(g_completed==1);assert(g_dayentries==1);close(g_realized,2.6);close(g_dayrealized,2.7);
  close(g_ledger[LedgerIndex(100)].netvol,-0.01);
  assert(rows==4);
  for(auto& d:deals)assert(LoggedIndex(d.ticket)>=0);
  RefreshPnL();assert(rows==4);
  add(5,100,DEAL_TYPE_BUY,DEAL_ENTRY_OUT,0.01,-1);
  RefreshPnL();assert(g_completed==2);assert(g_dayentries==1);close(g_realized,1.5);assert(rows==5);
  D(10).profit=4;g_historydirty=true;RefreshPnL();close(g_realized,3.5);assert(rows==6);
  g_day=2;clock_now=172810;RefreshPnL();close(g_dayrealized,0);assert(g_dayentries==0);assert(g_completed==2);
  add(80,100,DEAL_TYPE_BUY,DEAL_ENTRY_IN,0.01,0,172810,99);
  RefreshPnL();assert(g_runhalt&&g_contaminated);assert(g_completed==1);
 }else if(test=="cache"){
  baseline();RefreshPnL();reads=0;
  for(int i=0;i<1000;i++)RefreshPnL();
  assert(reads==0); // unchanged tester history must not be rebuilt
  D(10).profit=4;g_historydirty=true;RefreshPnL();assert(reads>0);close(g_realized,4.6);
  reads=0;clock_now+=59;RefreshPnL();assert(reads==0);
  clock_now++;RefreshPnL();assert(reads>0); // periodic correction/recovery audit
  reads=0;clock_now-=5;RefreshPnL();assert(reads>0); // clock reversal
  reads=0;g_day++;RefreshPnL();assert(reads>0);close(g_dayrealized,0);
  deals.erase(deals.begin());RefreshPnL();close(g_realized,4.7);
  g_test=false;reads=0;RefreshPnL();RefreshPnL();assert(reads>0); // demo full refresh retained
  history_ok=false;RefreshPnL();assert(g_runhalt); // cache cannot mask a failed select
 }else if(test=="daily"){
  add(1,11,DEAL_TYPE_BUY,DEAL_ENTRY_IN,.02,0,90000);
  add(2,11,DEAL_TYPE_BUY,DEAL_ENTRY_IN,.03,0,172810);
  add(3,22,DEAL_TYPE_SELL,DEAL_ENTRY_IN,.05,0,172811);
  g_day=2;clock_now=172820;RefreshPnL();assert(g_dayentries==1&&g_completed==0);
  add(4,11,DEAL_TYPE_SELL,DEAL_ENTRY_OUT,.05,1,172830);
  clock_now=172840;RefreshPnL();assert(g_dayentries==1&&g_completed==1);
  g_historydirty=true;g_ledger.clear();RefreshPnL();assert(g_dayentries==1);
  g_day=3;clock_now=259210;RefreshPnL();assert(g_dayentries==0);
 }else return 2;
}
'''

class HistoryPerformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='xep_history_')
        cls.binary = Path(cls.tmp.name) / 'history'
        names = ['LedgerLowerBound', 'KnownPosition', 'LedgerIndex', 'HistoryRefreshNeeded',
                 'RefreshPnL', 'LoggedIndex', 'LogDeal']
        actual = '\n'.join(function(name) for name in names)
        actual = actual.replace('ulong recovery[];', 'std::vector<ulong> recovery;')
        cpp = Path(cls.tmp.name) / 'history.cpp'
        cpp.write_text(STUBS + actual + CASES)
        subprocess.run(['g++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror',
                        '-Wno-misleading-indentation', '-pedantic', str(cpp), '-o', str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_case(self, name):
        subprocess.run([str(self.binary), name], check=True)

    def test_lookup_work_grows_logarithmically(self): self.run_case('lookups')
    def test_totals_partial_fills_revisions_and_foreign_deals(self): self.run_case('accounting')
    def test_unchanged_tester_history_is_reused_and_invalidated(self): self.run_case('cache')

    def test_daily_limit_counts_first_entry_once_across_partial_fills_and_restart(self): self.run_case('daily')

    def test_deal_updates_and_teardown_invalidate_cache(self):
        callback = SOURCE[SOURCE.index('void OnTradeTransaction('):SOURCE.index('void OnChartEvent(')]
        self.assertRegex(callback, r'DEAL_DELETE[^;]*\).*?g_historydirty=true', msg='Deal changes must invalidate cached totals')
        self.assertLess(callback.index('g_historydirty=true'), callback.index('if(!ours)return'))
        teardown = SOURCE[SOURCE.index('void OnDeinit('):]
        self.assertIn('g_historydirty=true;RefreshPnL();', teardown)

if __name__ == '__main__':
    unittest.main()
