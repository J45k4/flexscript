// Optional single-model schema parser and SQLite integration.
import "sqlite.flex";
import "internal/schema.flex";
fn mono_model(path,schema) {sc_parse(schema);db_connect(path);return db_schema(sc_model,sc_ddl);}
fn model_select_sql() {return sc_select;}
fn model_insert_sql() {return sc_insert;}
fn model_update_sql() {return sc_update;}
fn model_delete_sql() {return sc_delete;}
fn model_find_sql() {return sc_find;}
