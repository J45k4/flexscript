import "lib/harness.flex";
import "../libs/ml/pup/gpu/tests/core.flex";
fn suite(compiler) {t_init(compiler);h_timeout=300000;cgt_suite(compiler);return t_done();}
fn main(argc,argv) {return t_entry(argc,argv);}
