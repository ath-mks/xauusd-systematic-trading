"""Exercise the actual tester completion guard; no MT5 execution is simulated."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'XAU_ExecutionProbe.mq5').read_text()

def extract(name):
    m=re.search(r'bool\s+'+name+r'\s*\(',SOURCE)
    if not m:return ''
    start=SOURCE.index('{',m.end());end=start+1;depth=1
    while depth:
        if SOURCE[end]=='{':depth+=1
        elif SOURCE[end]=='}':depth-=1
        end+=1
    return SOURCE[m.start():end]

class TesterCompletion(unittest.TestCase):
    def test_normal_completion_and_exposure_guards(self):
        actual=extract('FinishTesterAtTarget')
        self.assertTrue(actual,'Missing clean tester-completion path after the target halt')
        program=r'''
#include <cassert>
#include <string>
using ulong=unsigned long;
using string=std::string;
struct Exposure {int positions;int orders;bool foreign;};
bool g_test=true,g_runhalt=true,g_ambiguous=false,g_contaminated=false;
bool g_closepending=false,g_testerstopping=false,ledger=true;
ulong g_entrybarrier=0,g_closebarrier=0;
int g_completed=200,InpTargetPositions=200,calls=0;
std::string sequence;
bool LiveLedgerMatches(){return ledger;}
void Event(string,string){sequence+='E';}
void SaveOrders(){sequence+='O';}
void SaveRisk(){sequence+='R';}
void GlobalVariablesFlush(){sequence+='G';}
void FlushLogs(){sequence+='F';}
void EventKillTimer(){sequence+='K';}
void TesterStop(){assert(!sequence.empty()&&sequence.back()=='K');sequence+='T';calls++;}
''' + actual + r'''
int main(){
 Exposure e{0,0,false};
 g_test=false;assert(!FinishTesterAtTarget(e));g_test=true;
 g_completed=199;assert(!FinishTesterAtTarget(e));g_completed=200;
 g_runhalt=false;assert(!FinishTesterAtTarget(e));g_runhalt=true;
 e.positions=1;assert(!FinishTesterAtTarget(e));e.positions=0;
 e.orders=1;assert(!FinishTesterAtTarget(e));e.orders=0;
 e.foreign=true;assert(!FinishTesterAtTarget(e));e.foreign=false;
 g_entrybarrier=99;assert(!FinishTesterAtTarget(e));g_entrybarrier=0;
 g_closebarrier=99;assert(!FinishTesterAtTarget(e));g_closebarrier=0;
 g_closepending=true;assert(!FinishTesterAtTarget(e));g_closepending=false;
 g_ambiguous=true;assert(!FinishTesterAtTarget(e));g_ambiguous=false;
 g_contaminated=true;assert(!FinishTesterAtTarget(e));g_contaminated=false;
 ledger=false;assert(!FinishTesterAtTarget(e));ledger=true;
 assert(calls==0&&sequence.empty());
 assert(FinishTesterAtTarget(e));assert(g_testerstopping);
 assert(calls==1&&sequence=="EORGFKT");
 assert(!FinishTesterAtTarget(e));assert(calls==1);
}
'''
        with tempfile.TemporaryDirectory(prefix='xep_finish_') as tmp:
            cpp=Path(tmp)/'finish.cpp';binary=Path(tmp)/'finish';cpp.write_text(program)
            subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror','-pedantic',str(cpp),'-o',str(binary)],check=True)
            subprocess.run([str(binary)],check=True)

    def test_finish_hook_is_after_reconciliation_and_before_new_trades(self):
        start=SOURCE.index('void Drive(');end=SOURCE.index('int OpenCSV(',start)
        drive=SOURCE[start:end]
        self.assertTrue('FinishTesterAtTarget(e)' in drive,'Controller must invoke completion')
        self.assertLess(drive.index('ResolveClose();ResolveBarrier(g_entrybarrier);'),drive.index('FinishTesterAtTarget(e)'))
        self.assertLess(drive.index('FinishTesterAtTarget(e)'),drive.index('PlaceEntry(tick)'))

if __name__=='__main__':unittest.main()
