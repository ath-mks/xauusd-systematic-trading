"""Execute the production capacity and timer helpers, not a broker emulator."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class MultiplePositions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        core = (ROOT / 'MMCore.mqh').read_text()
        if 'MMEntryAllowed(' not in core:
            raise AssertionError('Missing configurable multi-position admission')
        if not (ROOT / 'MMPositionBook.mqh').exists():
            raise AssertionError('Missing independent position holding/TP timers')
        cls.tmp = tempfile.TemporaryDirectory(prefix='xep_v2_capacity_')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.binary = Path(cls.tmp.name) / 'capacity'
        code = r'''
#include <cassert>
#include <cmath>
#include <string>
#include <climits>
using ulong=unsigned long;
double MathMax(double a,double b){return std::fmax(a,b);}
double MathMin(double a,double b){return std::fmin(a,b);}
double MathSqrt(double a){return std::sqrt(a);}
double MathFloor(double a){return std::floor(a);}
double MathCeil(double a){return std::ceil(a);}
double MathAbs(double a){return std::fabs(a);}
''' + '#include "' + str(ROOT/'MMCore.mqh') + '"\n' + '#include "' + str(ROOT/'MMPositionBook.mqh') + '"\n' + r'''
int main(int argc,char** argv){
 assert(argc==2);std::string test=argv[1];
 if(test=="capacity"){
  assert(MMEntryAllowed(0,0,0,0,.05,2,.01,0,2000));
  assert(MMEntryAllowed(1,0,.05,0,.05,2,.01,0,2000));
  assert(!MMEntryAllowed(2,0,.10,0,.05,2,.01,0,2000));
  assert(MMEntryAllowed(2,0,.10,0,.05,3,.01,0,2000));
  assert(!MMEntryAllowed(1,0,.05,0,.05,1,.01,0,2000));
 }else if(test=="reservations"){
  assert(!MMEntryAllowed(1,1,.05,.05,.05,2,.01,0,2000));
  assert(!MMEntryAllowed(1,0,.09,0,.05,2,.01,0,2000));
  assert(MMExposureValid(1,1,.02,.03,.05,1,.01));
  assert(MMExposureValid(1,1,.05,.05,.05,2,.01));
  assert(!MMExposureValid(2,1,.10,.05,.05,2,.01));
  assert(!MMExposureValid(3,0,.09,0,.05,2,.01));
  assert(!MMExposureValid(0,2,0,.05,.05,2,.01));
 }else if(test=="sample"){
  assert(MMEntryAllowed(1,0,.05,0,.05,2,.01,1998,2000));
  assert(!MMEntryAllowed(1,0,.05,0,.05,2,.01,1999,2000));
  assert(!MMEntryAllowed(0,0,0,0,.05,2,.01,2000,2000));
  assert(MMEntryAllowed(1,0,.05,0,.05,2,.01,2000,0));
  assert(!MMEntryAllowed(1,0,.05,0,.05,2,.01,INT_MAX-1,INT_MAX));
 }else if(test=="invalid"){
  assert(!MMEntryAllowed(-1,0,0,0,.05,2,.01,0,2000));
  assert(!MMEntryAllowed(0,0,0,0,.05,0,.01,0,2000));
  assert(!MMEntryAllowed(0,0,0,0,0,2,.01,0,2000));
  assert(!MMExposureValid(0,0,-.01,0,.05,2,.01));
 }else if(test=="timers"){
  MMPositionBook b;b.Reset();b.BeginScan();
  int x=b.Track(100,10000,100000000,30000);
  int y=b.Track(200,0,100000000,30000);b.EndScan();
  assert(x>=0&&y>=0&&x!=y&&b.Count()==2);
  assert(b.Deadline(x)==120000000&&b.Deadline(y)==130000000);
  assert(b.Due(x,120000000)&&!b.Due(y,120000000));
  b.BeginScan();assert(b.Track(100,0,110000000,30000)==x);
  assert(b.Track(200,10000,110000000,30000)==y);b.EndScan();
  assert(b.Deadline(x)==120000000&&b.Deadline(y)==130000000);
 }else if(test=="refresh"){
  MMPositionBook b;b.Reset();b.BeginScan();
  int x=b.Track(100,0,100000000,30000);
  int y=b.Track(200,0,100000000,30000);b.EndScan();
  assert(b.CanModify(x,100000000,3000000)&&b.CanModify(y,100000000,3000000));
  b.RecordModification(x,100000000);
  assert(!b.CanModify(x,101000000,3000000)&&b.CanModify(y,101000000,3000000));
  assert(b.CanModify(x,103000000,3000000));
 }else if(test=="restart"){
  MMPositionBook b;b.Reset();b.BeginScan();
  int x=b.Track(100,25000,100000000,30000);
  int y=b.Track(200,45000,100000000,30000);b.EndScan();
  assert(b.Deadline(x)==105000000&&!b.Due(x,104999999));
  assert(b.Due(y,100000000));
 }else if(test=="pruning"){
  MMPositionBook b;b.Reset();b.BeginScan();
  b.Track(100,0,100000000,30000);int y=b.Track(200,0,100000000,30000);b.EndScan();
  b.BeginScan();b.Track(200,0,110000000,30000);b.EndScan();
  assert(b.Count()==1&&b.Find(100)<0&&b.Deadline(y)==130000000);
  b.BeginScan();b.Track(200,0,111000000,30000);b.Track(300,0,111000000,30000);b.EndScan();
  assert(b.Count()==2&&b.Find(300)>=0&&b.Deadline(y)==130000000);
 }else if(test=="book_limit"){
  MMPositionBook b;b.Reset();b.BeginScan();
  for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)assert(b.Track(i+1,0,100000000,30000)>=0);
  assert(b.Track(MM_MAX_POSITION_SLOTS+1,0,100000000,30000)<0);b.EndScan();
  assert(b.Count()==MM_MAX_POSITION_SLOTS);
 }else return 2;
}
'''
        cpp=Path(cls.tmp.name)/'capacity.cpp';cpp.write_text(code)
        subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror','-pedantic',str(cpp),'-o',str(cls.binary)],check=True)

    def run_case(self,name):
        subprocess.run([str(self.binary),name],check=True)
    def test_configurable_position_count(self):self.run_case('capacity')
    def test_pending_volume_is_reserved_and_partial_remainder_is_valid(self):self.run_case('reservations')
    def test_unfinished_positions_reserve_sample_target(self):self.run_case('sample')
    def test_invalid_capacity_inputs_are_blocked(self):self.run_case('invalid')
    def test_each_position_retains_its_own_deadline(self):self.run_case('timers')
    def test_tp_cooldown_is_independent(self):self.run_case('refresh')
    def test_restart_restores_remaining_holding_time(self):self.run_case('restart')
    def test_closing_one_position_does_not_reset_another(self):self.run_case('pruning')
    def test_timing_book_has_a_defined_capacity(self):self.run_case('book_limit')

if __name__=='__main__':unittest.main()
