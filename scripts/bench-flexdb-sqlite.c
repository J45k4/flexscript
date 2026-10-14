// Native SQLite baseline: prepare once, bind/reset, consume matching results.
#include <sqlite3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/resource.h>
static sqlite3 *db;
static void check(int ok) { if(!ok) {fprintf(stderr,"SQLite benchmark: %s\n",db?sqlite3_errmsg(db):"closed database");exit(1);} }
static int64_t now(void) {struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (int64_t)t.tv_sec*1000000000+t.tv_nsec;}
static void sql(const char *s) {check(sqlite3_exec(db,s,0,0,0)==SQLITE_OK);}
static sqlite3_stmt *prepare(const char *s) {sqlite3_stmt *p=0;check(sqlite3_prepare_v2(db,s,-1,&p,0)==SQLITE_OK);return p;}
int main(int argc,char **argv) {
    if(argc!=4) return 1;
    const char *path=argv[1];int n=atoi(argv[2]);if(n<1000 || n>100000 || n%100) return 1;
    check(sqlite3_open_v2(path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_NOMUTEX,0)==SQLITE_OK);sql("PRAGMA synchronous=FULL; PRAGMA cache_size=-65536;");
    if(!strcmp(argv[3],"wal")) sql("PRAGMA journal_mode=WAL;");else sql("PRAGMA journal_mode=DELETE;");
    sql("CREATE TABLE people(id INTEGER PRIMARY KEY, age INTEGER NOT NULL, name TEXT NOT NULL);");
    sqlite3_stmt *p=prepare("INSERT INTO people VALUES(?1,?2,?3)");int64_t start=now();sql("BEGIN");
    for(int i=0;i<n;i++) {check(sqlite3_bind_int64(p,1,i+1)==SQLITE_OK);check(sqlite3_bind_int64(p,2,(i*17)%100)==SQLITE_OK);check(sqlite3_bind_text(p,3,"benchmark-name",14,SQLITE_STATIC)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_DONE);check(sqlite3_reset(p)==SQLITE_OK);}sql("COMMIT");int64_t insert=now()-start;sqlite3_finalize(p);
    sql("BEGIN");p=prepare("SELECT age FROM people WHERE id=?1");int64_t sum=0;start=now();for(int i=0;i<100000;i++){check(sqlite3_bind_int64(p,1,((int64_t)i*7919)%n+1)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_ROW);sum+=sqlite3_column_int64(p,0);check(sqlite3_step(p)==SQLITE_DONE);check(sqlite3_reset(p)==SQLITE_OK);}int64_t lookup=now()-start;check(sum==4950000);sqlite3_finalize(p);
    p=prepare("SELECT count(*) FROM people WHERE age>=?1");start=now();sum=0;for(int i=0;i<100;i++){check(sqlite3_bind_int(p,1,50)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_ROW);sum+=sqlite3_column_int64(p,0);check(sqlite3_step(p)==SQLITE_DONE);check(sqlite3_reset(p)==SQLITE_OK);}int64_t count=now()-start;check(sum==(int64_t)n*50);sqlite3_finalize(p);
    p=prepare("SELECT id,age,name FROM people WHERE age>=?1");int64_t *ids=malloc(n*sizeof(*ids));start=now();sum=0;for(int i=0;i<20;i++){check(sqlite3_bind_int(p,1,50)==SQLITE_OK);int rows=0,rc;while((rc=sqlite3_step(p))==SQLITE_ROW){ids[rows++]=sqlite3_column_int64(p,0);}check(rc==SQLITE_DONE);sum+=rows;check(ids[rows-1]>0);check(sqlite3_reset(p)==SQLITE_OK);}int64_t materialize=now()-start;check(sum==(int64_t)n*10);free(ids);sqlite3_finalize(p);sql("COMMIT");
    p=prepare("UPDATE people SET age=99,name='benchmark-name' WHERE id=?1");start=now();sql("BEGIN");for(int i=0;i<1000;i++){check(sqlite3_bind_int(p,1,i+1)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_DONE);check(sqlite3_reset(p)==SQLITE_OK);}sql("COMMIT");int64_t update=now()-start;
    // Force each update to change a value, just as FlexDB appends each update.
    sqlite3_finalize(p);p=prepare("UPDATE people SET age=98,name='benchmark-name' WHERE id=?1");start=now();for(int i=0;i<100;i++){sql("BEGIN");check(sqlite3_bind_int(p,1,i+1)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_DONE);check(sqlite3_reset(p)==SQLITE_OK);sql("COMMIT");}int64_t durable=now()-start;sqlite3_finalize(p);
    start=now();check(sqlite3_close(db)==SQLITE_OK);db=0;int64_t close_checkpoint=now()-start;start=now();check(sqlite3_open_v2(path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_NOMUTEX,0)==SQLITE_OK);p=prepare("SELECT age FROM people WHERE id=?1");check(sqlite3_bind_int(p,1,n)==SQLITE_OK);check(sqlite3_step(p)==SQLITE_ROW);check(sqlite3_column_int(p,0)==(n==1000?99:((n-1)*17)%100));int64_t reopen=now()-start;sqlite3_finalize(p);p=prepare("SELECT count(*) FROM people WHERE age>=50");start=now();check(sqlite3_step(p)==SQLITE_ROW);check(sqlite3_column_int64(p,0)==n/2+500);int64_t first_scan=now()-start;sqlite3_finalize(p);check(sqlite3_close(db)==SQLITE_OK);db=0;
    struct stat st;check(stat(path,&st)==0);struct rusage usage;check(getrusage(RUSAGE_SELF,&usage)==0);printf("{\"insert_ns\":%lld,\"lookup_ns\":%lld,\"count_ns\":%lld,\"materialize_ns\":%lld,\"update_ns\":%lld,\"durable_ns\":%lld,\"reopen_ns\":%lld,\"first_scan_ns\":%lld,\"close_checkpoint_ns\":%lld,\"bytes\":%lld,\"peak_kib\":%ld}\n",(long long)insert,(long long)lookup,(long long)count,(long long)materialize,(long long)update,(long long)durable,(long long)reopen,(long long)first_scan,(long long)close_checkpoint,(long long)st.st_size,usage.ru_maxrss);
}
