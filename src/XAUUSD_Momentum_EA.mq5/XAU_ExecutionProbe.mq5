#property strict
#property version "1.04"
#property description "Demo-only XAU execution measurement. One entry order, one position."
#include "MMCore.mqh"

input group "Demo execution probe"
input bool   InpEnableDemoOrders=true;
input long   InpMagic=26101301;
input int    InpRunId=1;                 // Change only when flat to start a new measurement run
input double InpLots=0.01;
input int    InpTargetPositions=200;
input group "Quotes (prices in USD per ounce for standard XAUUSD)"
input int    InpVolTicks=500;
input double InpMinDistance=0.10;
input double InpVolMultiplier=1.0;
input double InpInventoryGamma=0.5706715943;
input bool   InpMomentumProtection=true;
input double InpMaxSpread=0.20;
input double InpVolSpikeRatio=2.0;
input int    InpRefreshMs=3000;
input int    InpMaxQuoteAgeMs=6000;
input int    InpMaxTickAgeMs=5000;
input group "Risk (money amounts in account currency)"
input double InpSessionLoss=10.0;
input double InpSessionDrawdown=10.0;
input double InpRunLoss=30.0;
input double InpRunDrawdown=30.0;
input double InpMinStopDistance=0.50;
input double InpStopDistanceMultiplier=4.0;
input int    InpMaxHoldingSeconds=30;
input bool   InpFlattenOnRemove=true;
input int    InpMaxConsecutiveErrors=5;
input group "Session and logging"
input int    InpStartHourUTC=7;
input int    InpEndHourUTC=17;
input int    InpServerUTCOffsetHours=3;  // Provisional; used for history day boundaries and tester
input int    InpTimerMs=100;

MMFeatures g_features;
MMSignal g_signal;
string g_symbol,g_folder,g_key,g_lock,g_status="INITIALIZING",g_server;
long g_login=0;
double g_ticksize=0,g_point=0,g_vstep=0,g_locktoken=0;
int g_digits=0,g_nextside=1,g_errors=0;
int g_meta=INVALID_HANDLE,g_ticks=INVALID_HANDLE,g_requests=INVALID_HANDLE;
int g_transactions=INVALID_HANDLE,g_deals=INVALID_HANDLE,g_events=INVALID_HANDLE;
bool g_ready=false,g_test=false,g_iofail=false,g_paused=false,g_runhalt=false,g_dayhalt=false;
bool g_testerstopping=false;
bool g_historydirty=true;
int g_historycount=-1,g_historyday=-1;
datetime g_historytime=0;
bool g_ambiguous=false,g_busy=false,g_caughtup=false,g_ownedlock=false;
bool g_contaminated=false,g_closepending=false;
ulong g_closedeal=0;
ulong g_strategyus=0;
ulong g_lasttick=0,g_lastnewus=0,g_quoteus=0,g_modifyus=0,g_posdeadlineus=0,g_nexttradeus=0;
ulong g_summaryus=0,g_flushus=0,g_displayus=0,g_entrybarrier=0,g_closebarrier=0,g_posid=0;
int g_same=0,g_day=0,g_completed=0;
datetime g_epoch=0;
double g_realized=0,g_dayrealized=0,g_runpeak=0,g_daypeak=0,g_float=0;
struct LoggedDeal {ulong ticket;double price;double volume;double profit;double commission;double swap;double fee;};
LoggedDeal g_loggedDeals[];
ulong g_dealQueue[];
string BUTTON="XEP_STOP_FLATTEN";

struct Exposure
{
 int positions; int orders; bool foreign;
 double volume; ulong position; ulong order;
};
struct PositionLedger {ulong id;double netvol;bool entry;bool exit;};
PositionLedger g_ledger[];

string Q(string s){StringReplace(s,"\"","\"\"");return "\""+s+"\"";}
string SafeName(string s){StringReplace(s,"/","_");StringReplace(s,"\\","_");StringReplace(s,":","_");StringReplace(s," ","_");return StringSubstr(s,0,24);}
string IdentityHash(){string s=IntegerToString(g_login)+"|"+g_server+"|"+g_symbol;uint h=2166136261;for(int i=0;i<StringLen(s);i++)h=(uint)((h^(uint)StringGetCharacter(s,i))*16777619);return StringFormat("%08X",h);}
void W(uint written){if(written==0){g_iofail=true;Print("XEP: CSV write failed; stopping new orders. Error ",GetLastError());}}
datetime UTCNow(){if(g_test)return TimeCurrent()-InpServerUTCOffsetHours*3600;return TimeGMT();}
int DayNumber(){return (int)((long)UTCNow()/86400);}
bool IsDemo(){return g_test||AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;}
bool AccountMatches(){return AccountInfoInteger(ACCOUNT_LOGIN)==g_login&&AccountInfoString(ACCOUNT_SERVER)==g_server;}
bool TradePermissions()
{
 if(!IsDemo()||!AccountMatches())return false;
 if(g_test)return true; // MT5's local simulator does not require live-server permissions.
 return TerminalInfoInteger(TERMINAL_CONNECTED)&&TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&MQLInfoInteger(MQL_TRADE_ALLOWED)&&AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)&&AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
// Strategy deadlines use simulated market time in the tester. Log observations
// and request-call durations continue to use the separate host monotonic clock.
ulong StrategyNowUS()
{
 if(!g_test)return GetMicrosecondCount();
 long server=TimeTradeServer();ulong now=server>0?(ulong)server*1000000:0;
 MqlTick tick;
 if(SymbolInfoTick(g_symbol,tick)&&tick.time_msc>0)
 {
  ulong quoted=(ulong)tick.time_msc*1000;if(quoted>now)now=quoted;
 }
 if(now>g_strategyus)g_strategyus=now;
 return g_strategyus;
}
void Event(string kind,string message)
{
 Print("XEP ",kind,": ",message);
 if(g_events!=INVALID_HANDLE)W(FileWrite(g_events,GetMicrosecondCount(),(long)UTCNow(),kind,Q(message)));
}
void SaveRisk()
{
 GlobalVariableSet(g_key+".day",g_day);GlobalVariableSet(g_key+".dp",g_daypeak);
 GlobalVariableSet(g_key+".rp",g_runpeak);GlobalVariableSet(g_key+".dh",g_dayhalt?1:0);
 GlobalVariableSet(g_key+".rh",g_runhalt?1:0);GlobalVariableSet(g_key+".amb",g_ambiguous?1:0);
 GlobalVariableSet(g_key+".mix",g_contaminated?1:0);
}
void SaveTicket(string name,ulong ticket){GlobalVariableSet(g_key+name+"H",(double)(ticket>>32));GlobalVariableSet(g_key+name+"L",(double)(ticket&(ulong)4294967295));}
ulong LoadTicket(string name){if(!GlobalVariableCheck(g_key+name+"H"))return 0;return ((ulong)GlobalVariableGet(g_key+name+"H")<<32)|(ulong)GlobalVariableGet(g_key+name+"L");}
void SaveOrders(){SaveTicket(".en",g_entrybarrier);SaveTicket(".cl",g_closebarrier);SaveTicket(".de",g_closedeal);GlobalVariableSet(g_key+".cp",g_closepending?1:0);}
void StopRun(string why){if(!g_runhalt)Event("RUN_HALT",why);g_runhalt=true;g_status=why;SaveRisk();}
void SetAmbiguous(string why){g_ambiguous=true;StopRun(why);Alert("XAU ExecutionProbe: ambiguous order result. Inspect orders/positions manually. ",why);}
// Keep ticket tables sorted so recurring history lookups are logarithmic.
int LedgerLowerBound(ulong id)
{
 int lo=0,hi=ArraySize(g_ledger);
 while(lo<hi){int mid=lo+(hi-lo)/2;if(g_ledger[mid].id<id)lo=mid+1;else hi=mid;}
 return lo;
}
bool KnownPosition(ulong id){int k=LedgerLowerBound(id);return k<ArraySize(g_ledger)&&g_ledger[k].id==id;}
int LedgerIndex(ulong id)
{
 int k=LedgerLowerBound(id),n=ArraySize(g_ledger);
 if(k<n&&g_ledger[k].id==id)return k;
 ArrayResize(g_ledger,n+1,256);
 for(int i=n;i>k;i--)g_ledger[i]=g_ledger[i-1];
 g_ledger[k].id=id;g_ledger[k].netvol=0;g_ledger[k].entry=false;g_ledger[k].exit=false;return k;
}
Exposure Scan()
{
 Exposure e;e.positions=0;e.orders=0;e.foreign=false;e.volume=0;e.position=0;e.order=0;
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong t=PositionGetTicket(i);if(t==0||PositionGetString(POSITION_SYMBOL)!=g_symbol)continue;
  if(PositionGetInteger(POSITION_MAGIC)!=InpMagic){e.foreign=true;continue;}
  e.positions++;e.position=t;e.volume+=PositionGetDouble(POSITION_VOLUME);
 }
 for(int i=OrdersTotal()-1;i>=0;i--)
 {
  ulong t=OrderGetTicket(i);if(t==0||OrderGetString(ORDER_SYMBOL)!=g_symbol)continue;
  if(OrderGetInteger(ORDER_MAGIC)!=InpMagic){e.foreign=true;continue;}
  e.orders++;e.order=t;
 }
 return e;
}
double MinimumDistance(){return MathMax(g_ticksize,(MathMax((double)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL),(double)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_FREEZE_LEVEL))+1)*g_point);}
double P(double x){return NormalizeDouble(x,g_digits);}
ENUM_ORDER_TYPE_FILLING MarketFilling()
{
 long flags=SymbolInfoInteger(g_symbol,SYMBOL_FILLING_MODE);
 if((flags&SYMBOL_FILLING_FOK)!=0)return ORDER_FILLING_FOK;
 if((flags&SYMBOL_FILLING_IOC)!=0)return ORDER_FILLING_IOC;
 return ORDER_FILLING_RETURN;
}
void RequestRow(string stage,string why,const MqlTradeRequest &r,const MqlTradeResult &res,ulong start,ulong end,bool ok,int err)
{
 MqlTick tick;ZeroMemory(tick);SymbolInfoTick(g_symbol,tick);
 W(FileWrite(g_requests,stage,Q(why),start,end,(double)(end-start)/1000.0,(long)UTCNow(),res.request_id,(int)r.action,(int)r.type,r.order,r.position,r.volume,r.price,r.sl,r.tp,(int)r.type_time,(long)r.expiration,(int)r.type_filling,res.retcode,res.retcode_external,ok?1:0,err,res.order,res.deal,res.price,res.bid,res.ask,tick.time_msc,tick.bid,tick.ask,Q(res.comment)));
}
// Every actual trade request goes through this guard. No real-account override.
bool Send(MqlTradeRequest &r,string why,MqlTradeResult &res)
{
 ZeroMemory(res);
 if(!IsDemo()||!TradePermissions())return false;
 if(r.action==TRADE_ACTION_PENDING&&(g_iofail||g_runhalt||g_dayhalt||g_paused||g_ambiguous||!InpEnableDemoOrders))return false;
 if(r.action==TRADE_ACTION_DEAL&&g_ambiguous)return false; // do not duplicate an uncertain close
 if((r.action==TRADE_ACTION_DEAL||r.action==TRADE_ACTION_SLTP)&&g_contaminated)return false;
 r.magic=(ulong)InpMagic;r.symbol=g_symbol;
 if(r.action==TRADE_ACTION_PENDING)
 {
  Exposure e=Scan();if(e.foreign||e.positions>0||e.orders>0||g_entrybarrier!=0||g_closepending)return false;
  if(!LiveLedgerMatches())return false;
  if(MMRiskHit(g_dayrealized,g_daypeak,InpSessionLoss,InpSessionDrawdown)){g_dayhalt=true;SaveRisk();return false;}
  if(MMRiskHit(g_realized,g_runpeak,InpRunLoss,InpRunDrawdown)||g_completed>=InpTargetPositions){StopRun("Run limit reached before new entry");return false;}
  MqlTradeCheckResult check;ZeroMemory(check);ResetLastError();
  bool checked=OrderCheck(r,check);
  if(!checked){res.retcode=check.retcode;res.comment=check.comment;ulong now=GetMicrosecondCount();RequestRow("CHECK_REJECT",why,r,res,now,now,false,GetLastError());g_errors++;g_nexttradeus=StrategyNowUS()+1000000;return false;}
 }
 bool changesvolume=(r.action==TRADE_ACTION_PENDING||r.action==TRADE_ACTION_DEAL);
 if(changesvolume){GlobalVariableSet(g_key+".flight",1);GlobalVariablesFlush();}
 ulong start=GetMicrosecondCount();ResetLastError();bool sent=OrderSend(r,res);int err=GetLastError();ulong end=GetMicrosecondCount();
 RequestRow("SEND_REPLY",why,r,res,start,end,sent,err);
 bool accepted=sent&&(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED||res.retcode==TRADE_RETCODE_DONE_PARTIAL||res.retcode==TRADE_RETCODE_NO_CHANGES);
 ulong strategynow=StrategyNowUS();g_nexttradeus=strategynow+(accepted?150000:1000000);
 if(accepted)g_errors=0;else {g_errors++;Event("REQUEST_REJECT",why+": "+res.comment);}
 if(res.retcode==TRADE_RETCODE_TIMEOUT||res.retcode==TRADE_RETCODE_CONNECTION||(!sent&&res.retcode==0))SetAmbiguous("Request status uncertain; manual inspection required");
 if(accepted&&r.action==TRADE_ACTION_PENDING)
 {
  if(res.order==0)SetAmbiguous("Entry accepted without order ticket");
  else {g_entrybarrier=res.order;g_quoteus=strategynow;}
 }
 if(accepted&&r.action==TRADE_ACTION_DEAL)
 {
  g_closepending=true;g_closedeal=res.deal;
  if(res.order!=0)g_closebarrier=res.order;
  else if(res.deal==0)SetAmbiguous("Close accepted without order or deal ticket");
 }
 SaveOrders();if(changesvolume&&!g_ambiguous)GlobalVariableSet(g_key+".flight",0);GlobalVariablesFlush();
 return accepted;
}
bool Cancel(ulong ticket,string why)
{
 if(ticket==0||!OrderSelect(ticket))return true;
 if(OrderGetString(ORDER_SYMBOL)!=g_symbol||OrderGetInteger(ORDER_MAGIC)!=InpMagic)return false;
 MqlTradeRequest r;MqlTradeResult res;ZeroMemory(r);r.action=TRADE_ACTION_REMOVE;r.order=ticket;
 return Send(r,why,res);
}
bool LiveLedgerMatches()
{
 for(int k=0;k<ArraySize(g_ledger);k++)
 {
  double live=0;
  for(int i=PositionsTotal()-1;i>=0;i--){ulong p=PositionGetTicket(i);if(p!=0&&(ulong)PositionGetInteger(POSITION_IDENTIFIER)==g_ledger[k].id&&PositionGetString(POSITION_SYMBOL)==g_symbol)live+=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1)*PositionGetDouble(POSITION_VOLUME);}
  if(!MMVolumesMatch(g_ledger[k].netvol,live,g_vstep))return false;
 }
 for(int i=PositionsTotal()-1;i>=0;i--){ulong p=PositionGetTicket(i);if(p!=0&&PositionGetString(POSITION_SYMBOL)==g_symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic&&!KnownPosition((ulong)PositionGetInteger(POSITION_IDENTIFIER)))return false;}
 return true;
}
bool ResolveBarrier(ulong &ticket)
{
 if(ticket==0)return true;
 if(OrderSelect(ticket))return false;
 if(!HistoryOrderSelect(ticket))return false;
 long state=HistoryOrderGetInteger(ticket,ORDER_STATE);
 if(state!=ORDER_STATE_CANCELED&&state!=ORDER_STATE_EXPIRED&&state!=ORDER_STATE_REJECTED&&state!=ORDER_STATE_FILLED)return false;
 double initial=HistoryOrderGetDouble(ticket,ORDER_VOLUME_INITIAL),remaining=HistoryOrderGetDouble(ticket,ORDER_VOLUME_CURRENT);
 double expected=state==ORDER_STATE_FILLED?initial:MathMax(0,initial-remaining);
 RefreshPnL();if(!HistorySelect(g_epoch,TimeCurrent()+60))return false;
 double executed=0;
 for(int i=0;i<HistoryDealsTotal();i++){ulong d=HistoryDealGetTicket(i);long type=HistoryDealGetInteger(d,DEAL_TYPE);if((ulong)HistoryDealGetInteger(d,DEAL_ORDER)==ticket&&(type==DEAL_TYPE_BUY||type==DEAL_TYPE_SELL))executed+=HistoryDealGetDouble(d,DEAL_VOLUME);}
 if(!MMVolumesMatch(expected,executed,g_vstep)||!LiveLedgerMatches())return false;
 ticket=0;return true;
}
bool ResolveClose()
{
 if(!g_closepending)return true;
 if(g_closebarrier==0&&g_closedeal!=0&&HistoryDealSelect(g_closedeal))g_closebarrier=(ulong)HistoryDealGetInteger(g_closedeal,DEAL_ORDER);
 if(g_closebarrier==0||!ResolveBarrier(g_closebarrier))return false;
 g_closepending=false;g_closedeal=0;return true;
}
bool ClosePosition(ulong ticket,string why)
{
 if(g_closepending||g_ambiguous||g_contaminated||!LiveLedgerMatches()||!PositionSelectByTicket(ticket))return false;
 if(PositionGetInteger(POSITION_MAGIC)!=InpMagic||PositionGetString(POSITION_SYMBOL)!=g_symbol)return false;
 MqlTick tick;if(!SymbolInfoTick(g_symbol,tick)||tick.bid<=0||tick.ask<=0)return false;
 MqlTradeRequest r;MqlTradeResult res;ZeroMemory(r);
 r.action=TRADE_ACTION_DEAL;r.position=ticket;r.volume=PositionGetDouble(POSITION_VOLUME);
 bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
 r.type=buy?ORDER_TYPE_SELL:ORDER_TYPE_BUY;r.price=buy?tick.bid:tick.ask;
 r.deviation=20;r.type_filling=MarketFilling();r.comment="XEP risk exit";
 return Send(r,why,res);
}
void PlaceEntry(const MqlTick &tick)
{
 int side=MMEntrySide(g_signal.z,InpMomentumProtection,g_nextside);
 double delta=MathMax(InpMinDistance,InpVolMultiplier*g_signal.sigma),minimum=MinimumDistance();
 double price=MMEntryPrice(side,tick.bid,tick.ask,delta,minimum,g_ticksize);
 double stop=MathMax(InpMinStopDistance,MathMax(InpStopDistanceMultiplier*delta,minimum));
 MqlTradeRequest r;MqlTradeResult res;ZeroMemory(r);r.action=TRADE_ACTION_PENDING;r.type=side>0?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT;
 r.volume=InpLots;r.price=P(price);r.sl=P(MMRound(price-side*stop,g_ticksize,-side));
 r.tp=P(MMRound(price+side*MathMax(2*delta,minimum),g_ticksize,side));
 r.type_filling=ORDER_FILLING_RETURN;r.type_time=ORDER_TIME_GTC;r.expiration=0;
 long modes=SymbolInfoInteger(g_symbol,SYMBOL_EXPIRATION_MODE);
 // Prefer advertised GTC: Pepperstone rejected the short specified expiry (10022).
 // Normal quote lifetime is enforced by the connected EA's cancel/requote timer.
 if((modes&SYMBOL_EXPIRATION_GTC)==0&&(modes&SYMBOL_EXPIRATION_SPECIFIED)!=0){r.type_time=ORDER_TIME_SPECIFIED;r.expiration=TimeCurrent()+(int)MathMax(15,InpMaxQuoteAgeMs/1000+5);}
 r.comment="XEP demo probe";
 if(Send(r,"ENTRY",res)){g_nextside=-side;g_status="PENDING "+(side>0?"BUY":"SELL");}
}
void ManagePosition(ulong ticket,const MqlTick &tick,bool flatten,string reason)
{
 if(!PositionSelectByTicket(ticket))return;
 ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
 if(g_posid!=id)
 {
  g_posid=id;long elapsed=(long)TimeCurrent()*1000-PositionGetInteger(POSITION_TIME_MSC);
  g_posdeadlineus=StrategyNowUS()+(ulong)(MMRemainingHoldMs((double)elapsed,InpMaxHoldingSeconds*1000.0)*1000);g_modifyus=0;
 }
 bool holding=(StrategyNowUS()>=g_posdeadlineus);
 if(g_contaminated||g_closepending)return;
 if(flatten||holding){ClosePosition(ticket,holding?"HOLDING_LIMIT":reason);return;}
 if(!g_signal.ready||StrategyNowUS()-g_modifyus<(ulong)InpRefreshMs*1000)return;
 int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
 double sl=PositionGetDouble(POSITION_SL),oldtp=PositionGetDouble(POSITION_TP);
 if(sl<=0){StopRun("Position has no server stop loss");ClosePosition(ticket,"MISSING_SL");return;}
 double minimum=MinimumDistance();
 // Preserve SL; avoid modification if an existing stop is inside freeze range.
 if((side>0&&tick.bid-sl<minimum)||(side<0&&sl-tick.ask<minimum))return;
 if(oldtp>0&&((side>0&&oldtp-tick.bid<minimum)||(side<0&&tick.ask-oldtp<minimum)))return;
 double delta=MathMax(InpMinDistance,InpVolMultiplier*g_signal.sigma);
 double tp=P(MMExitTP(side,tick.bid,tick.ask,g_signal.sigma,delta,InpInventoryGamma,minimum,g_ticksize));
 g_modifyus=StrategyNowUS();if(MathAbs(tp-oldtp)<g_ticksize/2)return;
 MqlTradeRequest r;MqlTradeResult res;ZeroMemory(r);r.action=TRADE_ACTION_SLTP;r.position=ticket;r.sl=sl;r.tp=tp;
 Send(r,"ADAPTIVE_TP",res);
}
void TickRow(const MqlTick &t,string source,ulong observed)
{W(FileWrite(g_ticks,source,observed,(long)UTCNow(),t.time_msc,t.bid,t.ask,t.last,t.volume,t.volume_real,t.flags));}
void ConsumeTick(const MqlTick &t,string source)
{
 if(t.bid<=0||t.ask<t.bid)return;
 if(g_lasttick>0&&(ulong)t.time_msc>g_lasttick+30000){g_features.Reset();Event("TICK_GAP","Volatility warmup reset after quote gap >30 seconds");}
 g_features.Push((t.bid+t.ask)/2);TickRow(t,source,GetMicrosecondCount());
 if((ulong)t.time_msc==g_lasttick)g_same++;else {g_lasttick=(ulong)t.time_msc;g_same=1;}
 g_lastnewus=StrategyNowUS();
}
void PumpTicks()
{
 if(g_test)return; // Tester consumes only delivered OnTick events, with no history prefetch.
 MqlTick a[];ulong from=g_lasttick;int oldsame=g_same;int n=CopyTicks(g_symbol,a,COPY_TICKS_ALL,from,from==0?1100:8192);
 if(n<=0){g_caughtup=false;return;}int skipped=0,added=0;
 for(int i=0;i<n;i++)
 {
  if(from>0&&(ulong)a[i].time_msc==from&&skipped<oldsame){skipped++;continue;}
  if((ulong)a[i].time_msc<from)continue;
  ConsumeTick(a[i],from==0?"WARMUP_HISTORY":"HISTORY_READ");added++;
 }
 MqlTick latest;g_caughtup=SymbolInfoTick(g_symbol,latest)&&(ulong)latest.time_msc<=g_lasttick;
 if(n==8192&&added==0)StopRun("Tick-history cursor overflow; logging incomplete");
 g_signal=g_features.Signal(InpVolTicks);
}
bool HistoryRefreshNeeded(int count,datetime now)
{
 // Tester callbacks/count changes invalidate immediately; audit old revisions
 // at least once per simulated minute. Demo retains its full-refresh cadence.
 return !g_test||g_historydirty||count!=g_historycount||g_day!=g_historyday
        ||now<g_historytime||now-g_historytime>=60;
}
void RefreshPnL()
{
 datetime now=TimeCurrent();if(!HistorySelect(g_epoch,now+60)){StopRun("Trade history unavailable");return;}
 int n=HistoryDealsTotal();if(!HistoryRefreshNeeded(n,now))return;
 ArrayResize(g_ledger,0);
 for(int i=0;i<n;i++)
 {
  ulong d=HistoryDealGetTicket(i);if(HistoryDealGetString(d,DEAL_SYMBOL)!=g_symbol||HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic)continue;
  ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);if(id!=0)LedgerIndex(id);
 }
 g_realized=0;g_dayrealized=0;g_completed=0;
 long start=(long)g_day*86400+InpServerUTCOffsetHours*3600;
 for(int i=0;i<n;i++)
 {
  ulong d=HistoryDealGetTicket(i),id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
  long ty=HistoryDealGetInteger(d,DEAL_TYPE);
  if(HistoryDealGetString(d,DEAL_SYMBOL)==g_symbol&&HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic&&(ty==DEAL_TYPE_BUY||ty==DEAL_TYPE_SELL))
  {
   if(KnownPosition(id)&&AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)g_contaminated=true;
   StopRun("FOREIGN_DEAL: external XAU trade; manually inspect net position");
  }
  if(!KnownPosition(id))continue;
  double cash=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_FEE);
  g_realized+=cash;if(HistoryDealGetInteger(d,DEAL_TIME)>=start)g_dayrealized+=cash;
  int k=LedgerIndex(id);long type=HistoryDealGetInteger(d,DEAL_TYPE),entry=HistoryDealGetInteger(d,DEAL_ENTRY);double vol=HistoryDealGetDouble(d,DEAL_VOLUME);
  if(type==DEAL_TYPE_BUY)g_ledger[k].netvol+=vol;if(type==DEAL_TYPE_SELL)g_ledger[k].netvol-=vol;
  if(entry==DEAL_ENTRY_IN||entry==DEAL_ENTRY_INOUT)g_ledger[k].entry=true;
  if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_OUT_BY||entry==DEAL_ENTRY_INOUT)g_ledger[k].exit=true;
 }
 for(int i=0;i<ArraySize(g_ledger);i++)if(g_ledger[i].entry&&g_ledger[i].exit&&MathAbs(g_ledger[i].netvol)<g_vstep/2)g_completed++;
 // Select ticket list before LogDeal changes MT5's history selection.
 ulong recovery[];int count=0;
 ArrayResize(recovery,n);
 for(int i=0;i<n;i++){ulong d=HistoryDealGetTicket(i);if(KnownPosition((ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID)))recovery[count++]=d;}
 bool recovered=true;
 for(int i=0;i<count;i++)if(!LogDeal(recovery[i],true))recovered=false;
 g_historycount=n;g_historyday=g_day;g_historytime=now;g_historydirty=!recovered;
}
int LoggedIndex(ulong deal)
{
 int lo=0,hi=ArraySize(g_loggedDeals);
 while(lo<hi){int mid=lo+(hi-lo)/2;if(g_loggedDeals[mid].ticket<deal)lo=mid+1;else hi=mid;}
 if(lo<ArraySize(g_loggedDeals)&&g_loggedDeals[lo].ticket==deal)return lo;
 return -lo-1; // Encode the sorted insertion slot for a new deal.
}
bool LogDeal(ulong deal,bool recovered)
{
 if(!HistoryDealSelect(deal))return false;
 if(HistoryDealGetString(deal,DEAL_SYMBOL)!=g_symbol)return true;
 ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER),id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
 long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
 if(magic!=InpMagic&&!KnownPosition(id))return true;
 long time=HistoryDealGetInteger(deal,DEAL_TIME_MSC),type=HistoryDealGetInteger(deal,DEAL_TYPE),entry=HistoryDealGetInteger(deal,DEAL_ENTRY),reason=HistoryDealGetInteger(deal,DEAL_REASON);
 double price=HistoryDealGetDouble(deal,DEAL_PRICE),volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
 double profit=HistoryDealGetDouble(deal,DEAL_PROFIT),commission=HistoryDealGetDouble(deal,DEAL_COMMISSION),swap=HistoryDealGetDouble(deal,DEAL_SWAP),fee=HistoryDealGetDouble(deal,DEAL_FEE);
 int prior=LoggedIndex(deal);
 if(prior>=0&&g_loggedDeals[prior].price==price&&g_loggedDeals[prior].volume==volume&&g_loggedDeals[prior].profit==profit&&g_loggedDeals[prior].commission==commission&&g_loggedDeals[prior].swap==swap&&g_loggedDeals[prior].fee==fee)return true;
 double requested=0,sl=0,tp=0;long setup=0,done=0,otype=-1;
 if(HistoryOrderSelect(order)){requested=HistoryOrderGetDouble(order,ORDER_PRICE_OPEN);sl=HistoryOrderGetDouble(order,ORDER_SL);tp=HistoryOrderGetDouble(order,ORDER_TP);setup=HistoryOrderGetInteger(order,ORDER_TIME_SETUP_MSC);done=HistoryOrderGetInteger(order,ORDER_TIME_DONE_MSC);otype=HistoryOrderGetInteger(order,ORDER_TYPE);}
 MqlTick t;ZeroMemory(t);SymbolInfoTick(g_symbol,t);
 string source=prior>=0?"HISTORY_REVISION":(recovered?"HISTORY_RECOVERED":"TRANSACTION_CALLBACK");
 W(FileWrite(g_deals,source,GetMicrosecondCount(),(long)UTCNow(),deal,order,id,magic,time,type,entry,reason,volume,price,profit,commission,swap,fee,otype,requested,sl,tp,setup,done,t.time_msc,t.bid,t.ask));
 int k=prior;
 if(k<0){k=-k-1;int n=ArraySize(g_loggedDeals);ArrayResize(g_loggedDeals,n+1,256);for(int i=n;i>k;i--)g_loggedDeals[i]=g_loggedDeals[i-1];}
 g_loggedDeals[k].ticket=deal;g_loggedDeals[k].price=price;g_loggedDeals[k].volume=volume;g_loggedDeals[k].profit=profit;g_loggedDeals[k].commission=commission;g_loggedDeals[k].swap=swap;g_loggedDeals[k].fee=fee;return true;
}
void DrainDeals(){for(int i=ArraySize(g_dealQueue)-1;i>=0;i--)if(LogDeal(g_dealQueue[i],false)){g_dealQueue[i]=g_dealQueue[ArraySize(g_dealQueue)-1];ArrayResize(g_dealQueue,ArraySize(g_dealQueue)-1);}}
void Display()
{
 string mode=g_test?"TESTER SIMULATION":"DEMO EXECUTION";
 Comment("XAU ExecutionProbe 1.04 | ",mode,"\n",g_status,"\nSymbol: ",g_symbol,"  Lots: ",DoubleToString(InpLots,3),"  Completed: ",g_completed,"/",InpTargetPositions,
 "\nWarmup: ",g_features.Count(),"/1001  sigma: ",DoubleToString(g_signal.sigma,3),"  momentum Z: ",DoubleToString(g_signal.z,2),
 "\nDay P&L: ",DoubleToString(g_dayrealized+g_float,2),"  Run P&L: ",DoubleToString(g_realized+g_float,2)," ",AccountInfoString(ACCOUNT_CURRENCY),
 "\nUTC session ",InpStartHourUTC,":00–",InpEndHourUTC,":00  |  log folder MQL5\\Files\\",g_folder,
 "\nOne entry order at a time. Pending wait is NOT network latency.");
}
void FlushLogs(){FileFlush(g_ticks);FileFlush(g_requests);FileFlush(g_transactions);FileFlush(g_deals);FileFlush(g_events);}
bool FinishTesterAtTarget(const Exposure &e)
{
 // Finish only the tester sample target, after live exposure and fills agree.
 if(!g_test||g_testerstopping||!g_runhalt||g_completed<InpTargetPositions
    ||g_ambiguous||g_contaminated||g_closepending
    ||g_entrybarrier!=0||g_closebarrier!=0
    ||e.foreign||e.positions!=0||e.orders!=0||!LiveLedgerMatches())return false;
 g_testerstopping=true;
 Event("TESTER_COMPLETE","Target reached; completed partial-period test");
 SaveOrders();SaveRisk();GlobalVariablesFlush();FlushLogs();
 EventKillTimer();TesterStop();return true;
}
void Drive()
{
 if(!g_ready||g_busy||g_testerstopping)return;g_busy=true;ulong now=StrategyNowUS();
 if(!IsDemo()||!AccountMatches()){g_status="BLOCKED: account changed or real account";g_busy=false;return;}
 PumpTicks();DrainDeals();now=StrategyNowUS();
 int day=DayNumber();if(day!=g_day){g_day=day;g_dayhalt=false;g_daypeak=0;g_summaryus=0;Event("NEW_UTC_DAY","Daily risk state reset; run limits retained");}
 if(now-g_summaryus>=1000000||g_summaryus==0){RefreshPnL();g_summaryus=now;}
 Exposure e=Scan();g_float=0;
 for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t!=0&&PositionGetString(POSITION_SYMBOL)==g_symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic)g_float+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}
 double dayp=g_dayrealized+g_float,runp=g_realized+g_float;
 g_daypeak=MathMax(g_daypeak,dayp);g_runpeak=MathMax(g_runpeak,runp);
 if(!g_dayhalt&&MMRiskHit(dayp,g_daypeak,InpSessionLoss,InpSessionDrawdown)){g_dayhalt=true;Event("DAILY_HALT","Session loss or drawdown trigger");SaveRisk();GlobalVariablesFlush();}
 if(MMRiskHit(runp,g_runpeak,InpRunLoss,InpRunDrawdown))StopRun("Run loss or drawdown trigger");
 if(g_completed>=InpTargetPositions)StopRun("Target completed; collect CSV files");
 if(g_iofail)StopRun("CSV logging failed");
 if(e.foreign)StopRun("Foreign XAU activity: isolate this demo symbol");
 if(e.positions>1||e.volume>InpLots+g_vstep/2||e.orders>1)StopRun("Inventory or order-count limit violated");
 if(g_errors>=InpMaxConsecutiveErrors)StopRun("Repeated broker rejections; inspect requests.csv");
 bool session=false,entrysession=false;MqlDateTime dt;TimeToStruct(UTCNow(),dt);int second=dt.hour*3600+dt.min*60+dt.sec;
 session=dt.day_of_week>=1&&dt.day_of_week<=5&&second>=InpStartHourUTC*3600&&second<InpEndHourUTC*3600;
 entrysession=session&&second<InpEndHourUTC*3600-InpMaxHoldingSeconds;
 MqlTick tick;ZeroMemory(tick);bool hastick=SymbolInfoTick(g_symbol,tick)&&tick.bid>0&&tick.ask>=tick.bid;
 double brokerage=(double)((long)TimeTradeServer()*1000-tick.time_msc);
 bool fresh=g_caughtup&&MMFeedFresh((double)StrategyNowUS(),(double)g_lastnewus,brokerage,InpMaxTickAgeMs);
 bool healthy=hastick&&fresh&&g_signal.ready&&tick.ask-tick.bid<=InpMaxSpread+1e-9&&g_signal.sigma<=InpVolSpikeRatio*g_signal.slow+1e-12;
 bool stop=g_runhalt||g_dayhalt||g_paused||!InpEnableDemoOrders;
 if(now-g_flushus>=2000000){SaveRisk();GlobalVariablesFlush();FlushLogs();g_flushus=now;}
 if(now-g_displayus>=500000){Display();g_displayus=now;}
 if(!TradePermissions()){g_status="Waiting: connection / Algo Trading permission";g_busy=false;return;}
 if(now<g_nexttradeus){g_busy=false;return;}
 ResolveClose();ResolveBarrier(g_entrybarrier);SaveOrders();e=Scan();
 if(FinishTesterAtTarget(e)){g_busy=false;return;}
 stop=g_runhalt||g_dayhalt||g_paused||!InpEnableDemoOrders;
 if(g_closepending){g_status="WAITING: reconcile close order and live exposure";g_busy=false;return;}
 if(e.positions>0)
 {
  if(e.orders>0){Cancel(e.order,"CANCEL_REMAINDER_AFTER_FILL");g_busy=false;return;}
  g_status=stop?"STOPPING: flatten owned position":"MANAGING POSITION";
  if(hastick)ManagePosition(e.position,tick,stop||!session||!fresh,stop?"RISK_HALT":(!session?"SESSION_END":"STALE_FEED"));
  g_busy=false;return;
 }
 g_posid=0;
 bool resolved=g_entrybarrier==0&&!g_closepending;
 MM_ACTION action=MMAction(stop,entrysession,healthy,false,e.orders>0,!resolved||g_ambiguous);
 if(e.orders>0)
 {
  bool old=now-g_quoteus>=(ulong)InpRefreshMs*1000;
  if(action==MM_CANCEL||old||now-g_quoteus>=(ulong)InpMaxQuoteAgeMs*1000)Cancel(e.order,action==MM_CANCEL?"FILTER_OR_HALT":"REQUOTE");
  g_status=stop?"STOPPED: cancelling entry":"PENDING ENTRY";g_busy=false;return;
 }
 if(action==MM_QUOTE){PlaceEntry(tick);g_busy=false;return;}
 if(g_ambiguous)g_status="STOPPED: uncertain broker result; inspect manually";
 else if(g_runhalt)g_status="RUN STOPPED: see events.csv";
 else if(g_dayhalt)g_status="DAILY LIMIT: resumes next UTC day";
 else if(g_paused||!InpEnableDemoOrders)g_status="PAUSED: recording only";
 else if(!entrysession)g_status="WAITING: outside UTC entry session";
 else if(!g_signal.ready)g_status="WARMUP: waiting for 1001 valid quotes";
 else if(!resolved)g_status="WAITING: reconcile previous order";
 else g_status="FILTER: spread / volatility / stale quotes";
 g_busy=false;
}

int OpenCSV(string name){return FileOpen(g_folder+"\\"+name,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);}
void Meta(string key,string value){W(FileWrite(g_meta,key,Q(value)));}
int OnInit()
{
 g_test=(bool)MQLInfoInteger(MQL_TESTER);g_symbol=_Symbol;g_login=AccountInfoInteger(ACCOUNT_LOGIN);g_server=AccountInfoString(ACCOUNT_SERVER);g_features.Reset();g_signal=g_features.Signal(InpVolTicks);
 if(!IsDemo()){Print("XEP: refused. Demo account only; no real-account override.");return INIT_FAILED;}
 if(!g_test&&(!TerminalInfoInteger(TERMINAL_CONNECTED)||TimeCurrent()<=0)){Print("XEP: connect to your demo account before attaching.");return INIT_FAILED;}
 string upper=g_symbol;StringToUpper(upper);if(StringFind(upper,"XAUUSD")<0){Print("Attach to your XAUUSD chart (suffix allowed).");return INIT_PARAMETERS_INCORRECT;}
 if(InpMagic<=0||InpRunId<1||InpTargetPositions<1||InpVolTicks<50||InpVolTicks>500||InpLots<=0||InpMinDistance<=0||InpVolMultiplier<=0||InpInventoryGamma<0||InpMaxSpread<=0||InpVolSpikeRatio<=0||InpRefreshMs<250||InpMaxQuoteAgeMs<InpRefreshMs||InpMaxTickAgeMs<500||InpSessionLoss<=0||InpSessionDrawdown<=0||InpRunLoss<=0||InpRunDrawdown<=0||InpMinStopDistance<=0||InpStopDistanceMultiplier<=0||InpMaxHoldingSeconds<1||InpMaxConsecutiveErrors<1||InpStartHourUTC<0||InpEndHourUTC>24||InpStartHourUTC>=InpEndHourUTC||InpMaxHoldingSeconds>=(InpEndHourUTC-InpStartHourUTC)*3600||InpTimerMs<50||InpTimerMs>1000||InpServerUTCOffsetHours< -12||InpServerUTCOffsetHours>14)return INIT_PARAMETERS_INCORRECT;
 if(!SymbolSelect(g_symbol,true))return INIT_FAILED;
 g_ticksize=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_SIZE);g_point=SymbolInfoDouble(g_symbol,SYMBOL_POINT);g_digits=(int)SymbolInfoInteger(g_symbol,SYMBOL_DIGITS);g_vstep=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
 if(g_ticksize<=0||g_point<=0||!MMVolumeValid(InpLots,SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX),g_vstep)){Print("XEP: invalid lot size or symbol specifications; size is never rounded up.");return INIT_PARAMETERS_INCORRECT;}
 long allowed=SymbolInfoInteger(g_symbol,SYMBOL_ORDER_MODE);
 if((allowed&SYMBOL_ORDER_LIMIT)==0||(allowed&SYMBOL_ORDER_SL)==0||(allowed&SYMBOL_ORDER_TP)==0){Print("XEP requires limit orders, SL and TP support.");return INIT_FAILED;}
 g_lock="XEP_LOCK_"+IdentityHash()+(g_test?"_T":"_D");
 GlobalVariableTemp(g_lock);g_locktoken=(double)ChartID();if(g_locktoken==0)g_locktoken=1;
 if(!GlobalVariableSetOnCondition(g_lock,g_locktoken,0)){Print("XEP: another instance owns this account/symbol. Remove it first.");return INIT_FAILED;}g_ownedlock=true;
 g_key="XEP_"+IdentityHash()+"_"+IntegerToString(InpRunId)+"_"+IntegerToString(InpMagic)+(g_test?"_T":"_D");
 if(StringLen(g_key)>55){Print("XEP: state key too long for terminal global variables.");return INIT_PARAMETERS_INCORRECT;}
 Exposure e=Scan();if(e.foreign){Print("XEP: remove foreign XAUUSD trades/orders or use a separate demo account.");return INIT_FAILED;}
 if(!GlobalVariableCheck(g_key+".epoch"))
 {
  if(e.positions>0||e.orders>0){Print("New RunId requires a flat symbol with no pending orders.");return INIT_FAILED;}
  GlobalVariableSet(g_key+".epoch",(double)TimeCurrent());
 }
 g_epoch=(datetime)GlobalVariableGet(g_key+".epoch");g_day=DayNumber();
 g_runpeak=GlobalVariableCheck(g_key+".rp")?GlobalVariableGet(g_key+".rp"):0;
 g_runhalt=GlobalVariableCheck(g_key+".rh")&&GlobalVariableGet(g_key+".rh")>0;
 g_ambiguous=GlobalVariableCheck(g_key+".amb")&&GlobalVariableGet(g_key+".amb")>0;
 g_contaminated=GlobalVariableCheck(g_key+".mix")&&GlobalVariableGet(g_key+".mix")>0;
 if(GlobalVariableCheck(g_key+".flight")&&GlobalVariableGet(g_key+".flight")>0){g_ambiguous=true;g_runhalt=true;}
 g_entrybarrier=LoadTicket(".en");g_closebarrier=LoadTicket(".cl");g_closedeal=LoadTicket(".de");g_closepending=GlobalVariableCheck(g_key+".cp")&&GlobalVariableGet(g_key+".cp")>0;
 if(GlobalVariableCheck(g_key+".day")&&(int)GlobalVariableGet(g_key+".day")==g_day){g_daypeak=GlobalVariableGet(g_key+".dp");g_dayhalt=GlobalVariableGet(g_key+".dh")>0;}
 string stamp=SafeName(TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS));
 g_folder="XAU_ExecutionProbe\\"+SafeName(g_symbol)+"_"+stamp+"_"+IntegerToString((long)GetTickCount64());
 FolderCreate("XAU_ExecutionProbe");FolderCreate(g_folder);
 g_meta=OpenCSV("metadata.csv");g_ticks=OpenCSV("ticks.csv");g_requests=OpenCSV("requests.csv");g_transactions=OpenCSV("transactions.csv");g_deals=OpenCSV("deals.csv");g_events=OpenCSV("events.csv");
 if(g_meta==INVALID_HANDLE||g_ticks==INVALID_HANDLE||g_requests==INVALID_HANDLE||g_transactions==INVALID_HANDLE||g_deals==INVALID_HANDLE||g_events==INVALID_HANDLE){Print("XEP: could not create all CSV files.");return INIT_FAILED;}
 W(FileWrite(g_meta,"key","value"));
 W(FileWrite(g_ticks,"source","observed_mono_us","local_utc_seconds","quote_server_msc","bid","ask","last","volume","volume_real","flags"));
 W(FileWrite(g_requests,"stage","reason","send_mono_us","reply_mono_us","call_duration_ms","local_utc_seconds","request_id","action","order_type","request_order","position_ticket","volume","requested_price","sl","tp","time_type","expiration_server","filling_type","retcode","retcode_external","api_return","last_error","result_order","result_deal","result_price","result_bid","result_ask","snapshot_server_msc","snapshot_bid","snapshot_ask","comment"));
 W(FileWrite(g_transactions,"observed_mono_us","local_utc_seconds","transaction_type","order","deal","position","order_type","order_state","deal_type","price","volume","request_id","request_retcode","snapshot_server_msc","snapshot_bid","snapshot_ask"));
 W(FileWrite(g_deals,"source","observed_mono_us","local_utc_seconds","deal","order","position_id","magic","deal_server_msc","deal_type","deal_entry","deal_reason","volume","fill_price","profit","commission","swap","fee","history_order_type","history_order_price","history_order_sl","history_order_tp","order_setup_server_msc","order_done_server_msc","snapshot_server_msc","snapshot_bid","snapshot_ask"));
 W(FileWrite(g_events,"observed_mono_us","local_utc_seconds","event","message"));
 Meta("version","1.04");Meta("mode",g_test?"TESTER_SIMULATION":"DEMO_FORWARD");Meta("symbol",g_symbol);Meta("server",AccountInfoString(ACCOUNT_SERVER));Meta("account_identity_hash",IdentityHash());Meta("account_currency",AccountInfoString(ACCOUNT_CURRENCY));Meta("margin_mode",IntegerToString(AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
 Meta("strategy_clock",g_test?"SIMULATED_SERVER_AND_TICK_TIME":"HOST_MONOTONIC");Meta("observation_clock","HOST_MONOTONIC");Meta("tick_ingestion",g_test?"TESTER_ONTICK_ONLY":"COPYTICKS_HISTORY_AND_ONTICK_SNAPSHOTS");
 Meta("contract_size",DoubleToString(SymbolInfoDouble(g_symbol,SYMBOL_TRADE_CONTRACT_SIZE),8));Meta("tick_size",DoubleToString(g_ticksize,8));Meta("tick_value",DoubleToString(SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE),8));
 Meta("volume_min",DoubleToString(SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN),8));Meta("volume_step",DoubleToString(g_vstep,8));Meta("volume_max",DoubleToString(SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX),8));Meta("volume_limit",DoubleToString(SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_LIMIT),8));
 Meta("stops_level_points",IntegerToString(SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL)));Meta("freeze_level_points",IntegerToString(SymbolInfoInteger(g_symbol,SYMBOL_TRADE_FREEZE_LEVEL)));Meta("expiration_mode",IntegerToString(SymbolInfoInteger(g_symbol,SYMBOL_EXPIRATION_MODE)));Meta("filling_mode",IntegerToString(SymbolInfoInteger(g_symbol,SYMBOL_FILLING_MODE)));
 Meta("run_id",IntegerToString(InpRunId));Meta("magic",IntegerToString(InpMagic));Meta("lots",DoubleToString(InpLots,8));Meta("run_epoch_server",IntegerToString((long)g_epoch));Meta("server_utc_offset_assumed_hours",IntegerToString(InpServerUTCOffsetHours));Meta("observed_TimeTradeServer_minus_TimeGMT_seconds",IntegerToString((long)(TimeTradeServer()-TimeGMT())));
 Meta("terminal_ping_us",IntegerToString(TerminalInfoInteger(TERMINAL_PING_LAST)));Meta("terminal_build",IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));Meta("vol_ticks",IntegerToString(InpVolTicks));Meta("vol_multiplier",DoubleToString(InpVolMultiplier,8));Meta("minimum_quote_distance",DoubleToString(InpMinDistance,8));Meta("inventory_gamma",DoubleToString(InpInventoryGamma,10));Meta("momentum_protection",InpMomentumProtection?"true":"false");Meta("refresh_ms",IntegerToString(InpRefreshMs));Meta("max_spread",DoubleToString(InpMaxSpread,8));Meta("session_loss_account_currency",DoubleToString(InpSessionLoss,2));Meta("session_drawdown_account_currency",DoubleToString(InpSessionDrawdown,2));Meta("run_loss_account_currency",DoubleToString(InpRunLoss,2));Meta("run_drawdown_account_currency",DoubleToString(InpRunDrawdown,2));Meta("holding_limit_seconds",IntegerToString(InpMaxHoldingSeconds));Meta("scheduled_news_filter","not implemented");
 Meta("input.InpEnableDemoOrders",(InpEnableDemoOrders?"true":"false"));
 Meta("input.InpMagic",IntegerToString(InpMagic));
 Meta("input.InpRunId",IntegerToString(InpRunId));
 Meta("input.InpLots",DoubleToString(InpLots,10));
 Meta("input.InpTargetPositions",IntegerToString(InpTargetPositions));
 Meta("input.InpVolTicks",IntegerToString(InpVolTicks));
 Meta("input.InpMinDistance",DoubleToString(InpMinDistance,10));
 Meta("input.InpVolMultiplier",DoubleToString(InpVolMultiplier,10));
 Meta("input.InpInventoryGamma",DoubleToString(InpInventoryGamma,10));
 Meta("input.InpMomentumProtection",(InpMomentumProtection?"true":"false"));
 Meta("input.InpMaxSpread",DoubleToString(InpMaxSpread,10));
 Meta("input.InpVolSpikeRatio",DoubleToString(InpVolSpikeRatio,10));
 Meta("input.InpRefreshMs",IntegerToString(InpRefreshMs));
 Meta("input.InpMaxQuoteAgeMs",IntegerToString(InpMaxQuoteAgeMs));
 Meta("input.InpMaxTickAgeMs",IntegerToString(InpMaxTickAgeMs));
 Meta("input.InpSessionLoss",DoubleToString(InpSessionLoss,10));
 Meta("input.InpSessionDrawdown",DoubleToString(InpSessionDrawdown,10));
 Meta("input.InpRunLoss",DoubleToString(InpRunLoss,10));
 Meta("input.InpRunDrawdown",DoubleToString(InpRunDrawdown,10));
 Meta("input.InpMinStopDistance",DoubleToString(InpMinStopDistance,10));
 Meta("input.InpStopDistanceMultiplier",DoubleToString(InpStopDistanceMultiplier,10));
 Meta("input.InpMaxHoldingSeconds",IntegerToString(InpMaxHoldingSeconds));
 Meta("input.InpFlattenOnRemove",(InpFlattenOnRemove?"true":"false"));
 Meta("input.InpMaxConsecutiveErrors",IntegerToString(InpMaxConsecutiveErrors));
 Meta("input.InpStartHourUTC",IntegerToString(InpStartHourUTC));
 Meta("input.InpEndHourUTC",IntegerToString(InpEndHourUTC));
 Meta("input.InpServerUTCOffsetHours",IntegerToString(InpServerUTCOffsetHours));
 Meta("input.InpTimerMs",IntegerToString(InpTimerMs));
 FileFlush(g_meta);if(g_iofail)return INIT_FAILED;
 if(!EventSetMillisecondTimer(InpTimerMs))return INIT_FAILED;
 ObjectCreate(0,BUTTON,OBJ_BUTTON,0,0,0);ObjectSetInteger(0,BUTTON,OBJPROP_XDISTANCE,12);ObjectSetInteger(0,BUTTON,OBJPROP_YDISTANCE,170);ObjectSetInteger(0,BUTTON,OBJPROP_XSIZE,180);ObjectSetInteger(0,BUTTON,OBJPROP_YSIZE,28);ObjectSetString(0,BUTTON,OBJPROP_TEXT,"STOP & FLATTEN");
 if(g_entrybarrier==0&&!g_closepending)g_entrybarrier=e.order;g_quoteus=0;g_ready=true;
 Event("START",g_test?"Simulated tester execution only; source logger v1.04":"Demo forward execution; source logger v1.04");
 Print("XEP files: ",TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL5\\Files\\",g_folder);
 RefreshPnL();PumpTicks();Display();return INIT_SUCCEEDED;
}
void OnTick()
{
 if(!g_ready||g_testerstopping)return;
 MqlTick t;
 if(SymbolInfoTick(g_symbol,t))
 {
  if(g_test)
  {
   ConsumeTick(t,"TESTER_TICK");g_signal=g_features.Signal(InpVolTicks);
   g_caughtup=t.time_msc>0&&t.bid>0&&t.ask>=t.bid;
  }
  else TickRow(t,"ONTICK_SNAPSHOT",GetMicrosecondCount());
 }
 Drive();
}
void OnTimer(){Drive();}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &r,const MqlTradeResult &res)
{
 if(!g_ready)return;
 if(t.type==TRADE_TRANSACTION_DEAL_ADD||t.type==TRADE_TRANSACTION_DEAL_UPDATE||t.type==TRADE_TRANSACTION_DEAL_DELETE){g_historydirty=true;g_summaryus=0;}
 bool ours=(t.symbol==g_symbol)||(t.type==TRADE_TRANSACTION_REQUEST&&r.symbol==g_symbol&&r.magic==(ulong)InpMagic);if(!ours)return;
 MqlTick tick;ZeroMemory(tick);SymbolInfoTick(g_symbol,tick);
 uint rid=0,ret=0;if(t.type==TRADE_TRANSACTION_REQUEST){rid=res.request_id;ret=res.retcode;}
 W(FileWrite(g_transactions,GetMicrosecondCount(),(long)UTCNow(),(int)t.type,t.order,t.deal,t.position,(int)t.order_type,(int)t.order_state,(int)t.deal_type,t.price,t.volume,rid,ret,tick.time_msc,tick.bid,tick.ask));
 if((t.type==TRADE_TRANSACTION_DEAL_ADD||t.type==TRADE_TRANSACTION_DEAL_UPDATE)&&t.deal!=0){int n=ArraySize(g_dealQueue);ArrayResize(g_dealQueue,n+1);g_dealQueue[n]=t.deal;}
 g_summaryus=0;
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{if(id==CHARTEVENT_OBJECT_CLICK&&sparam==BUTTON){g_paused=true;Event("USER_STOP","Cancel entry and flatten owned position when broker permits");ObjectSetInteger(0,BUTTON,OBJPROP_STATE,false);}}
void OnDeinit(const int reason)
{
 EventKillTimer();
 if(g_ready)
 {
  Event("DEINIT","Reason "+IntegerToString(reason)+"; best-effort cleanup");
  if(IsDemo()&&TradePermissions())
  {
   Exposure e=Scan();if(e.order!=0&&e.order!=g_closebarrier)Cancel(e.order,"REMOVE_EA");
   e=Scan();if(InpFlattenOnRemove&&e.position!=0)ClosePosition(e.position,"REMOVE_EA");
  }
  if(AccountMatches()){g_historydirty=true;RefreshPnL();DrainDeals();ResolveClose();ResolveBarrier(g_entrybarrier);SaveOrders();SaveRisk();GlobalVariablesFlush();}
  Exposure e=Scan();if(e.positions>0||e.orders>0)Print("XEP WARNING: orders/positions remain. Inspect Trade tab and close/cancel manually. Server SL/TP remain; terminal timers stop now.");
 }
 if(g_meta!=INVALID_HANDLE)FileClose(g_meta);if(g_ticks!=INVALID_HANDLE)FileClose(g_ticks);if(g_requests!=INVALID_HANDLE)FileClose(g_requests);if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);if(g_deals!=INVALID_HANDLE)FileClose(g_deals);if(g_events!=INVALID_HANDLE)FileClose(g_events);
 ObjectDelete(0,BUTTON);Comment("");
 if(g_ownedlock&&GlobalVariableCheck(g_lock))GlobalVariableSetOnCondition(g_lock,0,g_locktoken);
}
