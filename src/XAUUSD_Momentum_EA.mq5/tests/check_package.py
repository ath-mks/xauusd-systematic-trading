from pathlib import Path
import re, unittest
P=Path(__file__).resolve().parents[1]
S=(P/'XAU_ExecutionProbe_v3.mq5').read_text()

def arguments_at(text,pos):
    start=text.index('(',pos)+1;depth=1;quoted=False;escaped=False;args=[];last=start
    for i in range(start,len(text)):
        ch=text[i]
        if quoted:
            if escaped:escaped=False
            elif ch=='\\':escaped=True
            elif ch=='"':quoted=False
        elif ch=='"':quoted=True
        elif ch=='(':depth+=1
        elif ch==')':
            depth-=1
            if depth==0:args.append(text[last:i].strip());return args
        elif ch==',' and depth==1:args.append(text[last:i].strip());last=i+1
    raise AssertionError('Unbalanced call')

class Packaging(unittest.TestCase):
    def test_preset_matches_inputs(self):
        expected=dict(re.findall(r'^input\s+(?:bool|int|long|double)\s+(Inp\w+)\s*=\s*([^;]+);',S,re.M))
        actual=dict(x.split('=',1) for x in (P/'XAU_v3_GBP_1Position_CostAware.set').read_text().splitlines() if x and not x.startswith(';'))
        expected['InpRunId']='11'
        self.assertEqual(expected,actual)
        for name in expected:self.assertTrue('"input.'+name+'"' in S,name)
    def test_csv_headers_match_writes(self):
        widths={}
        for m in re.finditer(r'\bFileWrite\(',S):
            args=arguments_at(S,m.start());handle=args[0]
            if handle.startswith('g_'):
                widths.setdefault(handle,set()).add(len(args)-1)
        self.assertEqual(set(widths),{'g_meta','g_ticks','g_requests','g_transactions','g_deals','g_events'})
        self.assertTrue(all(len(w)==1 for w in widths.values()),str(widths))
        self.assertTrue(all(next(iter(w))<=63 for w in widths.values()),str(widths))
    def test_trade_api_centralized(self):
        self.assertEqual(len(re.findall(r'\bOrderSend\(',S)),1)
        body=S[S.index('bool Send('):S.index('bool Cancel(')]
        self.assertTrue('if(!IsDemo()||!TradePermissions())return false;' in body)
        self.assertTrue('g_contaminated' in body)
        self.assertNotIn('OrderSendAsync(',S)
    def test_callbacks_and_source_header(self):
        for name in ['OnInit','OnDeinit','OnTick','OnTimer','OnTradeTransaction','OnChartEvent']:
            self.assertEqual(len(re.findall(r'\b(?:int|void)\s+'+name+r'\(',S)),1,name)
        self.assertTrue((P/'MMCore.mqh').exists())
        self.assertFalse(any(P.glob('*.ex5')),'Do not imply a native compile occurred')
    def test_recovery_safety_state(self):
        self.assertTrue('GlobalVariableSet(g_key+".flight",1)' in S)
        self.assertTrue('g_closepending=GlobalVariableCheck' in S)
        self.assertTrue('LoadTicket(".en")' in S)
        self.assertTrue('SaveTicket(".en",g_entrybarrier)' in S)

if __name__=='__main__':unittest.main()
