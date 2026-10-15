"""Execute the EA's actual expiration-assignment block with broker-log inputs.

This is a portable request-construction test, not an MT5/broker simulator.
Changing production selection to prefer SPECIFIED when GTC is available must
fail the Pepperstone regression. Only environment reads are supplied by stubs.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ExpirationSelection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / 'XAU_ExecutionProbe.mq5').read_text()
        start = source.index(' r.type_filling=ORDER_FILLING_RETURN;', source.index('void PlaceEntry('))
        end = source.index(' r.comment=', start)
        actual_block = source[start:end]
        program = r'''
#include <algorithm>
#include <cstdlib>
#include <iostream>
constexpr int ORDER_FILLING_RETURN=2, ORDER_TIME_GTC=0, ORDER_TIME_SPECIFIED=2;
constexpr int SYMBOL_EXPIRATION_GTC=1, SYMBOL_EXPIRATION_SPECIFIED=4;
constexpr int SYMBOL_EXPIRATION_MODE=0, InpMaxQuoteAgeMs=6000;
const char *g_symbol="XAUUSD";
long fixture_modes=0;
long SymbolInfoInteger(const char *, int){return fixture_modes;}
long TimeCurrent(){return 1791920501;}
int MathMax(int a,int b){return std::max(a,b);}
struct Request {int type_filling=0;int type_time=0;long expiration=0;};
int main(int argc,char **argv){
 if(argc!=2)return 2;
 fixture_modes=std::strtol(argv[1],nullptr,10);
 Request r;
''' + actual_block + r'''
 std::cout<<r.type_time<<" "<<r.expiration<<" "<<r.type_filling<<"\n";
}
'''
        cls.temp = tempfile.TemporaryDirectory(prefix='xep_expiry_')
        cls.addClassCleanup(cls.temp.cleanup)
        cpp = Path(cls.temp.name) / 'expiration.cpp'
        cls.binary = Path(cls.temp.name) / 'expiration'
        cpp.write_text(program)
        subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-pedantic', str(cpp), '-o', str(cls.binary)], check=True)

    def request(self, modes):
        output = subprocess.check_output([str(self.binary), str(modes)], text=True)
        return tuple(map(int, output.split()))

    def test_pepperstone_mode_15_uses_gtc_with_no_expiration(self):
        # Observed metadata expiration_mode=15; old 15s expiry yielded 10022.
        self.assertEqual(self.request(15), (0, 0, 2))

    def test_gtc_is_preferred_when_both_flags_are_set(self):
        self.assertEqual(self.request(1 | 4), (0, 0, 2))

    def test_gtc_only_remains_valid(self):
        self.assertEqual(self.request(1), (0, 0, 2))

    def test_specified_only_fallback_is_preserved(self):
        self.assertEqual(self.request(4), (2, 1791920516, 2))


if __name__ == '__main__':
    unittest.main()
