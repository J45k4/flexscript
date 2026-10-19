import "../flexdb.flex";
import "../../../compiler/transform-sdk.flex";
extend "../schema.flex";
// Hundreds of helpers must fit the ordinary bounded transformation VM.
database LargeCatalog {
    table Meta00 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta01 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta02 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta03 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta04 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta05 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta06 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta07 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta08 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta09 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta10 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
    table Meta11 { id: rowid;
        column00: i64;
        column01: i64;
        column02: i64;
        column03: i64;
        column04: i64;
        column05: i64;
        column06: i64;
        column07: i64;
        column08: i64;
        column09: i64;
        column10: i64;
        column11: i64;
    }
}
fn ordinary_body(){let s="} database Fake { \" still string"; // } database Ignored {
 return load8(s);}
fn main(argc,argv){let db=LargeCatalog_open(load64(argv+8));if !db{return 1;}let ok=Meta00_column00_column()==0 && Meta11_column11_column()==11;let a=alloc(64);let b=alloc(64);let n=0;while n<=32 {let src=0;while src<5 {let dst=0;while dst<5 {let i=0;while i<64 {store8(a+i,i+1);store8(b+i,i+1);i=i+1;}i=0;while i<n {store8(b+dst+i,load8(b+src+i));i=i+1;}ext_copy(a+dst,a+src,n);i=0;while i<64 {if load8(a+i)!=load8(b+i){return 2;}i=i+1;}dst=dst+1;}src=src+1;}n=n+1;}ext_copy(a,b,-1);ext_copy(a,b,(-9223372036854775807-1));if !close_flexdb(db){return 3;}if !ok{return 4;}return 0;}
