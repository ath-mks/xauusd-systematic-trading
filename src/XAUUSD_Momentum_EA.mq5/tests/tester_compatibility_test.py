"""Portable tests of actual EA clock, permission and tick-ingestion code.

MT5 environment reads and I/O are supplied by deterministic stubs. These tests
do not emulate order execution or replace a native Strategy Tester run.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'XAU_ExecutionProbe.mq5').read_text()


def function(name):
    match = re.search(r'\b(?:void|bool|ulong)\s+' + name + r'\s*\(', SOURCE)
    if match is None:
        return ''
    start = SOURCE.index('{', match.end())
    depth = 1
    end = start + 1
    while depth:
        if SOURCE[end] == '{':
            depth += 1
        elif SOURCE[end] == '}':
            depth -= 1
        end += 1
    return SOURCE[match.start():end]


class TesterCompatibility(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        expression = re.search(r'ulong now=([^;]+);', function('Drive')).group(1)
        program = r'''
#include <cmath>
#include <iostream>
#include <string>
using ulong=unsigned long;
using string=std::string;
double MathMax(double a,double b){return std::fmax(a,b);}
double MathMin(double a,double b){return std::fmin(a,b);}
double MathSqrt(double x){return std::sqrt(x);}
double MathFloor(double x){return std::floor(x);}
double MathCeil(double x){return std::ceil(x);}
double MathAbs(double x){return std::fabs(x);}
''' + '#include "' + str(ROOT / 'MMCore.mqh') + '"\n' + r'''
struct MqlTick {long time_msc=0;double bid=100;double ask=100.1;};
enum {TERMINAL_CONNECTED,TERMINAL_TRADE_ALLOWED,MQL_TRADE_ALLOWED,
      ACCOUNT_TRADE_ALLOWED,ACCOUNT_TRADE_EXPERT};
bool g_test=true,g_ready=true,g_caughtup=false,g_testerstopping=false;
bool fixture_demo=true,fixture_account=true,fixture_flags=true,fixture_tick_ok=true;
ulong fixture_wall=1000000,g_lasttick=0,g_lastnewus=0,g_strategyus=0;
long fixture_server=1700000000;
MqlTick fixture_tick;
int g_same=0,InpVolTicks=500;
string g_symbol="XAUUSD";
MMFeatures g_features;
MMSignal g_signal;
ulong GetMicrosecondCount(){return fixture_wall;}
long TimeTradeServer(){return fixture_server;}
bool SymbolInfoTick(const string &,MqlTick &t){t=fixture_tick;return fixture_tick_ok;}
bool IsDemo(){return g_test||fixture_demo;}
bool AccountMatches(){return fixture_account;}
bool TerminalInfoInteger(int){return fixture_flags;}
bool MQLInfoInteger(int){return fixture_flags;}
bool AccountInfoInteger(int){return fixture_flags;}
void Event(string,string){}
void TickRow(const MqlTick &,string,ulong){}
void Drive(){}
''' + function('StrategyNowUS') + '\n' + function('TradePermissions') + '\n' + function('ConsumeTick') + '\n' + function('OnTick') + '\n' + r'''
ulong ReadControllerClock(){return ''' + expression + r''';}
int main(){
 g_features.Reset();fixture_tick_ok=false;
 std::cout<<"initial_no_tick "<<ReadControllerClock()<<"\n";
 fixture_tick_ok=true;fixture_tick.time_msc=fixture_server*1000+250;
 ulong begin=ReadControllerClock();
 fixture_wall+=1000;fixture_server+=30;fixture_tick.time_msc+=30000;
 std::cout<<"historical_elapsed "<<ReadControllerClock()-begin<<"\n";
 ulong same=ReadControllerClock();fixture_wall+=90000000;
 std::cout<<"host_pause_elapsed "<<ReadControllerClock()-same<<"\n";
 fixture_tick_ok=false;
 std::cout<<"no_tick_clock "<<ReadControllerClock()<<"\n";
 fixture_tick_ok=true;fixture_tick.time_msc=fixture_server*1000+250;
 begin=ReadControllerClock();fixture_server+=2;
 std::cout<<"timer_gap_elapsed "<<ReadControllerClock()-begin<<"\n";
 g_test=false;
 std::cout<<"demo_clock "<<ReadControllerClock()<<"\n";
 g_test=true;fixture_flags=false;
 std::cout<<"offline_tester "<<TradePermissions()<<"\n";
 fixture_account=false;
 std::cout<<"changed_account "<<TradePermissions()<<"\n";
 fixture_account=true;g_test=false;fixture_demo=false;fixture_flags=true;
 std::cout<<"real_account "<<TradePermissions()<<"\n";
 fixture_demo=true;fixture_flags=false;
 std::cout<<"disabled_demo "<<TradePermissions()<<"\n";
 fixture_flags=true;
 std::cout<<"enabled_demo "<<TradePermissions()<<"\n";
 g_test=true;
 for(int i=0;i<1001;i++)OnTick();
 std::cout<<"tester_warmup "<<g_features.Count()<<"\n";
 std::cout<<"tester_ready "<<g_signal.ready<<"\n";
 g_test=false;g_features.Reset();OnTick();
 std::cout<<"demo_ontick_pushes "<<g_features.Count()<<"\n";
}
'''
        cls.temp = tempfile.TemporaryDirectory(prefix='xep_tester_')
        cls.addClassCleanup(cls.temp.cleanup)
        cpp = Path(cls.temp.name) / 'tester.cpp'
        binary = Path(cls.temp.name) / 'tester'
        cpp.write_text(program)
        subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-pedantic', str(cpp), '-o', str(binary)], check=True)
        output = subprocess.check_output([str(binary)], text=True)
        cls.values = {key: int(value) for key, value in
                      (row.split() for row in output.splitlines())}

    def test_30_market_seconds_advance_despite_1ms_host_runtime(self):
        self.assertEqual(self.values['historical_elapsed'], 30_000_000)

    def test_host_pause_does_not_age_simulated_orders(self):
        self.assertEqual(self.values['host_pause_elapsed'], 0)

    def test_no_tick_uses_simulated_server_time(self):
        self.assertEqual(self.values['initial_no_tick'], 1_700_000_000_000_000)

    def test_missing_tick_does_not_move_clock_backwards(self):
        self.assertEqual(self.values['no_tick_clock'], 1_700_000_030_250_000)

    def test_timer_advances_beyond_last_fractional_tick(self):
        self.assertEqual(self.values['timer_gap_elapsed'], 1_750_000)

    def test_demo_keeps_local_monotonic_clock(self):
        self.assertEqual(self.values['demo_clock'], 91_001_000)

    def test_tester_does_not_require_live_permissions(self):
        self.assertEqual(self.values['offline_tester'], 1)

    def test_account_change_is_still_blocked(self):
        self.assertEqual(self.values['changed_account'], 0)

    def test_real_account_is_still_blocked(self):
        self.assertEqual(self.values['real_account'], 0)

    def test_demo_requires_permissions(self):
        self.assertEqual(self.values['disabled_demo'], 0)
        self.assertEqual(self.values['enabled_demo'], 1)

    def test_tester_warms_up_from_delivered_ticks_including_same_ms(self):
        self.assertEqual(self.values['tester_warmup'], 1001)
        self.assertEqual(self.values['tester_ready'], 1)

    def test_demo_tick_ingestion_remains_in_history_pump(self):
        self.assertEqual(self.values['demo_ontick_pushes'], 0)

    def test_tester_skips_history_download(self):
        body = function('PumpTicks')
        self.assertTrue('if(g_test)return;' in body[:body.index('CopyTicks(')])


if __name__ == '__main__':
    unittest.main()
