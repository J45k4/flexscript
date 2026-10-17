// Query the native compiler mode without guessing from a benchmark request.
lowering native_lowering_active "lowering.active" "native-x86_64";
fn native_lowering_active(){return 0;}
