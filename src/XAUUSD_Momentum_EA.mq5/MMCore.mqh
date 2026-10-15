#ifndef XEP_MMCORE_MQH
#define XEP_MMCORE_MQH
// Shared unchanged by MQL5 and the portable C++ tests. Prices are symbol units.
struct MMSignal { double sigma; double slow; double z; bool ready; };
class MMFeatures
{
private:
 double mids[1001];
 int cursor;
 int count;
 double Ago(int n) { return mids[(cursor-1-n+3003)%1001]; }
 double MeanSquares(int n)
 {
  double total=0;
  for(int j=0;j<n;j++){double dx=Ago(j)-Ago(j+1);total+=dx*dx;}
  return total/n;
 }
public:
 void Reset(){cursor=0;count=0;}
 void Push(double mid){mids[cursor]=mid;cursor=(cursor+1)%1001;if(count<1001)count++;}
 int Count(){return count;}
 MMSignal Signal(int n)
 {
  MMSignal s;s.sigma=0;s.slow=0;s.z=0;s.ready=(count>=1001&&n>=50&&n<=500);
  if(!s.ready)return s;
  s.sigma=MathSqrt(50*MeanSquares(n));s.slow=MathSqrt(50*MeanSquares(1000));
  s.z=(Ago(0)-Ago(20))/MathMax(.01,MathSqrt(20*MeanSquares(200)));
  return s;
 }
};
double MMRound(double value,double tick,int direction)
{if(direction>0)return MathCeil(value/tick-1e-9)*tick;return MathFloor(value/tick+1e-9)*tick;}
bool MMVolumeValid(double v,double minv,double maxv,double step)
{return step>0&&v>=minv-1e-10&&v<=maxv+1e-10&&MathAbs(v/step-MathFloor(v/step+.5))<1e-7;}
int MMEntrySide(double z,bool protect,int nextside)
{if(protect&&z>1.5)return 1;if(protect&&z< -1.5)return -1;return nextside;}
double MMEntryPrice(int side,double bid,double ask,double distance,double minimum,double tick)
{double mid=(bid+ask)/2;if(side>0)return MMRound(MathMin(mid-distance,ask-minimum),tick,-1);return MMRound(MathMax(mid+distance,bid+minimum),tick,1);}
double MMExitTP(int side,double bid,double ask,double sigma,double distance,double gamma,double minimum,double tick)
{double r=(bid+ask)/2-gamma*side*sigma*sigma;if(side>0)return MMRound(MathMax(r+distance,bid+minimum),tick,1);return MMRound(MathMin(r-distance,ask-minimum),tick,-1);}
bool MMRiskHit(double pnl,double peak,double loss,double drawdown)
{return pnl<=-loss||peak-pnl>=drawdown;}
double MMRemainingHoldMs(double age,double limit){return MathMax(0,limit-MathMax(0,age));}
bool MMFeedFresh(double now,double last,double brokerage,double maxage)
{return last>0&&now>=last&&(now-last)<=maxage*1000&&brokerage>=-2000&&brokerage<=maxage;}
bool MMVolumesMatch(double expected,double observed,double step)
{return MathAbs(expected-observed)<step/2;}
enum MM_ACTION {MM_WAIT,MM_QUOTE,MM_CANCEL,MM_MANAGE,MM_FLATTEN};
MM_ACTION MMAction(bool halted,bool entryok,bool healthy,bool position,bool order,bool unresolved)
{
 if(position)return halted?MM_FLATTEN:MM_MANAGE;
 if(order&&(halted||!entryok||!healthy))return MM_CANCEL;
 if(halted||!entryok||!healthy||unresolved||order)return MM_WAIT;
 return MM_QUOTE;
}
#endif
