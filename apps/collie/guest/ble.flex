// SDK advertising value construction. Protocol selection and payload bytes are guest code.
fn ble_set_options(legacy,connectable,scannable,anonymous,include_tx,primary_phy,secondary_phy,interval,tx_power,discoverable){let r=db_list();db_add(r,db_int(legacy));db_add(r,db_int(connectable));db_add(r,db_int(scannable));db_add(r,db_int(anonymous));db_add(r,db_int(include_tx));db_add(r,db_int(primary_phy));db_add(r,db_int(secondary_phy));db_add(r,db_int(interval));db_add(r,db_int(tx_power));db_add(r,db_int(discoverable));return r;}
fn ble_set_data_value(uuids,service_data,manufacturers,solicitation,include_name,include_tx){let r=db_list();db_add(r,uuids);db_add(r,service_data);db_add(r,manufacturers);db_add(r,solicitation);db_add(r,db_int(include_name));db_add(r,db_int(include_tx));return r;}
fn ble_ad_service(uuid,bytes){let r=db_list();db_add(r,db_text(uuid));db_add(r,bytes);return r;}
fn ble_ad_manufacturer(id,bytes){let r=db_list();db_add(r,db_int(id));db_add(r,bytes);return r;}
fn ble_periodic_options(include_tx,interval){let r=db_list();db_add(r,db_int(include_tx));db_add(r,db_int(interval));return r;}
fn ble_ad_empty(){return ble_set_data_value(db_list(),db_list(),db_list(),db_list(),0,0);}
