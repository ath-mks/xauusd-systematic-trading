#include <cassert>
#include <cmath>
#include <iostream>
double MathMax(double a,double b){return std::fmax(a,b);} double MathMin(double a,double b){return std::fmin(a,b);}
double MathSqrt(double a){return std::sqrt(a);} double MathFloor(double a){return std::floor(a);} double MathCeil(double a){return std::ceil(a);} double MathAbs(double a){return std::fabs(a);}
#include "../MMCore.mqh"
int main(){
 MMFeatures f;f.Reset();for(int i=0;i<1000;i++) f.Push(100+i*.1);
 assert(!f.Signal(500).ready);f.Push(200);auto s=f.Signal(500);assert(s.ready);assert(std::abs(s.sigma-std::sqrt(.5))<1e-9);assert(std::abs(s.z-std::sqrt(20.))<1e-8);
 for(int i=0;i<2000;i++){f.Push(200);}
 s=f.Signal(500);assert(s.ready&&s.sigma==0&&s.slow==0&&s.z==0);
 assert(MMEntrySide(2,true,-1)==1);assert(MMEntrySide(-2,true,1)==-1);assert(MMEntrySide(0,true,-1)==-1);
 assert(std::abs(MMRound(100.127,.01,1)-100.13)<1e-9);assert(std::abs(MMRound(100.127,.01,-1)-100.12)<1e-9);
 assert(MMVolumeValid(.01,.01,100,.01));assert(!MMVolumeValid(.005,.01,100,.01));assert(!MMVolumeValid(.015,.01,100,.01));
 double b=100,a=100.12;
 assert(MMEntryPrice(1,b,a,.10,.01,.01)<a);assert(MMEntryPrice(-1,b,a,.10,.01,.01)>b);
 assert(MMExitTP(1,b,a,1,.1,.5,.01,.01)>=b+.01-1e-9);
 assert(MMExitTP(-1,b,a,1,.1,.5,.01,.01)<=a-.01+1e-9);
 assert(MMRiskHit(-10,0,10,10));assert(MMRiskHit(2,13,10,10));assert(!MMRiskHit(2,11,10,10));
 assert(MMRemainingHoldMs(25000,30000)==5000);assert(MMRemainingHoldMs(45000,30000)==0);
 assert(MMRemainingHoldMs(-10,30000)==30000);
 assert(MMFeedFresh(1020000,1000000,200,5000));
 assert(!MMFeedFresh(1000000,1020000,200,5000)); // pre-pump clock cannot be used
 assert(!MMFeedFresh(1020000,1000000,60000,5000)); // cached history is stale
 assert(!MMVolumesMatch(.01,0,.01)); // filled history must precede resubmission
 assert(!MMVolumesMatch(.01,.005,.001));assert(MMVolumesMatch(.01,.01,.001));
 assert(MMAction(true,true,true,true,true,false)==MM_FLATTEN);
 assert(MMAction(false,false,false,true,false,false)==MM_MANAGE);
 assert(MMAction(false,false,true,false,true,false)==MM_CANCEL);
 assert(MMAction(false,true,true,false,false,false)==MM_QUOTE);
 assert(MMAction(false,true,true,false,false,true)==MM_WAIT);
 std::cout<<"Portable math/state tests passed\n";
}
