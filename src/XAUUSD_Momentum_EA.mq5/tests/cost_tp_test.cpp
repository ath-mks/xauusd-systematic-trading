#include <cassert>
#include <cmath>
#include <iostream>
double MathMax(double a,double b){return std::fmax(a,b);} double MathMin(double a,double b){return std::fmin(a,b);}
double MathSqrt(double a){return std::sqrt(a);} double MathFloor(double a){return std::floor(a);} double MathCeil(double a){return std::ceil(a);} double MathAbs(double a){return std::fabs(a);}
#include "../MMCore.mqh"
int main(){
 // At GBP 8 per dollar move: 45p costs + 10p buffer require 0.06875, rounded outward.
 assert(std::abs(MMCostFloor(1,2000,.45,.10,8,.01)-2000.07)<1e-8);
 assert(std::abs(MMCostFloor(-1,2000,.45,.10,8,.01)-1999.93)<1e-8);
 assert(MMCostFloor(1,2000,0,0,8,.01)==2000);
 // Invalid conversion never silently returns a usable target.
 assert(MMCostFloor(1,2000,.45,.10,0,.01)==0);
 assert(MMCostFloor(-1,2000,.45,.10,-8,.01)==0);
 // Dynamic candidate may improve desired profit; floor only prevents unprofitable TP.
 assert(MMConstrainTP(1,1999,2000.07,.01)==2000.07);
 assert(MMConstrainTP(-1,2001,1999.93,.01)==1999.93);
 assert(MMConstrainTP(1,2001,2000.07,.01)==2001);
 assert(MMConstrainTP(-1,1999,1999.93,.01)==1999);
 // Actual entry charges and estimated exit charges are separate, so no doubling upfront round-trip charges.
 assert(std::abs(MMTargetCosts(.45,.1,0,.1,4.5)-.675)<1e-8);
 assert(std::abs(MMTargetCosts(.225,.1,0,.1,4.5)-.45)<1e-8);
 assert(std::abs(MMTargetCosts(0,0,0,.1,4.5)-.45)<1e-8);
 assert(std::abs(MMTargetCosts(.225,.1,-.1,.05,4.5)-.325)<1e-8);
 assert(std::abs(MMTargetCosts(.225,.1,.1,.1,4.5)-.45)<1e-8);
 std::cout<<"Cost TP tests passed\n";
}
