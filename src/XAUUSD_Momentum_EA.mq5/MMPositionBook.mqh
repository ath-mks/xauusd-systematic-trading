#ifndef XEP_MM_POSITION_BOOK_MQH
#define XEP_MM_POSITION_BOOK_MQH
#define MM_MAX_POSITION_SLOTS 100
// Broker identifiers remain stable when a position ticket changes.
// The same code runs in MQL5 and in the portable C++ behaviour tests.
struct MMPositionSlot
{
 ulong id;
 ulong deadline_us;
 ulong modified_us;
 bool modified;
 bool seen;
};
class MMPositionBook
{
private:
 MMPositionSlot slots[MM_MAX_POSITION_SLOTS];
 void Clear(int i)
 {slots[i].id=0;slots[i].deadline_us=0;slots[i].modified_us=0;slots[i].modified=false;slots[i].seen=false;}
public:
 void Reset(){for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)Clear(i);}
 int Find(ulong id)
 {if(id==0)return -1;for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)if(slots[i].id==id)return i;return -1;}
 void BeginScan(){for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)slots[i].seen=false;}
 int Track(ulong id,double elapsed_ms,ulong now_us,double limit_ms)
 {
  if(id==0)return -1;
  int i=Find(id);
  if(i<0)
  {
   for(int k=0;k<MM_MAX_POSITION_SLOTS;k++)if(slots[k].id==0){i=k;break;}
   if(i<0)return -1;
   Clear(i);slots[i].id=id;
   slots[i].deadline_us=now_us+(ulong)(MMRemainingHoldMs(elapsed_ms,limit_ms)*1000);
  }
  slots[i].seen=true;return i;
 }
 void EndScan(){for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)if(slots[i].id!=0&&!slots[i].seen)Clear(i);}
 int Count(){int n=0;for(int i=0;i<MM_MAX_POSITION_SLOTS;i++)if(slots[i].id!=0)n++;return n;}
 ulong Deadline(int i){return slots[i].deadline_us;}
 ulong ModifiedAt(int i){return slots[i].modified_us;}
 bool Due(int i,ulong now_us){return i>=0&&slots[i].id!=0&&now_us>=slots[i].deadline_us;}
 bool CanModify(int i,ulong now_us,ulong refresh_us)
 {return i>=0&&slots[i].id!=0&&(!slots[i].modified||(now_us>=slots[i].modified_us&&now_us-slots[i].modified_us>=refresh_us));}
 void RecordModification(int i,ulong now_us)
 {slots[i].modified_us=now_us;slots[i].modified=true;}
};
#endif
