#include <climits>
template<class Key> static bool prepare_bucket_sort(uint32_t*order,unsigned n,Key key){
 if(n>8192)return false;if(n<2)return true;
 uint8_t keys[8192];uint32_t output[8192];unsigned positions[3*65]={},maximum=0;
 for(unsigned i=0;i<n;i++){
  if(i&&order[i]<=order[i-1])return false;
  uint64_t value=key(order[i]);unsigned count=value&8191;
  if(value>=3u*8192||count>64)return false;
  unsigned packed=(unsigned)(value>>13)*65+count;keys[i]=packed;positions[packed]++;if(count>maximum)maximum=count;
 }
 unsigned cursor=0;
 for(unsigned type=0;type<3;type++)for(unsigned count=0;count<=maximum;count++){
  unsigned at=type*65+count,nitems=positions[at];positions[at]=cursor;cursor+=nitems;
 }
 for(unsigned i=0;i<n;i++)output[positions[keys[i]]++]=order[i];
 memcpy(order,output,n*sizeof(uint32_t));return true;
}
struct PrepareChoice {unsigned lane,finish,remote;};
static PrepareChoice prepare_original_choice(unsigned index,unsigned cost,const unsigned*lane_finish,const unsigned*finish,const int*pred,unsigned npred,const DagNode*graph){
 PrepareChoice answer{index%6,~0u,~0u};
 for(unsigned choice=0;choice<6;choice++){
  unsigned lane=(index+choice)%6,ready=lane_finish[lane],remote=0;int seen[16];unsigned nseen=0;
  for(unsigned j=0;j<npred;j++){
   int p=pred[j];if(p<0)continue;bool duplicate=false;for(unsigned k=0;k<nseen;k++)if(seen[k]==p)duplicate=true;
   if(duplicate)continue;seen[nseen++]=p;bool cross=graph[p].lane!=lane;remote+=cross;
   unsigned dependency=finish[p]+(cross?4u:0u);if(dependency>ready)ready=dependency;
  }
  unsigned predicted=ready+cost;
  if(predicted<answer.finish||(predicted==answer.finish&&remote<answer.remote))answer={lane,predicted,remote};
 }
 return answer;
}
static PrepareChoice prepare_aggregated_choice(unsigned index,unsigned cost,const unsigned*lane_finish,const unsigned*finish,const int*pred,unsigned npred,const DagNode*graph){
 unsigned maxima[6]={},counts[6]={},total=0;int seen[16];unsigned nseen=0;
 for(unsigned j=0;j<npred;j++){
  int p=pred[j];if(p<0)continue;bool duplicate=false;for(unsigned k=0;k<nseen;k++)if(seen[k]==p)duplicate=true;
  if(duplicate)continue;seen[nseen++]=p;
  unsigned owner=graph[p].lane;
  // Preserve the old modular-unsigned behavior even outside the prepared
  // graph's small finish-time domain. Max and +4 cannot commute on overflow.
  if(owner>=6||finish[p]>UINT_MAX-4)return prepare_original_choice(index,cost,lane_finish,finish,pred,npred,graph);
  counts[owner]++;total++;if(finish[p]>maxima[owner])maxima[owner]=finish[p];
 }
 PrepareChoice answer{index%6,~0u,~0u};
 for(unsigned choice=0;choice<6;choice++){
  unsigned lane=(index+choice)%6,ready=lane_finish[lane],remote=total-counts[lane];
  for(unsigned owner=0;owner<6;owner++)if(counts[owner]){
   unsigned dependency=maxima[owner]+(owner!=lane?4u:0u);if(dependency>ready)ready=dependency;
  }
  unsigned predicted=ready+cost;
  if(predicted<answer.finish||(predicted==answer.finish&&remote<answer.remote))answer={lane,predicted,remote};
 }
 return answer;
}
