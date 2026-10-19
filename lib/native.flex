// Calls a trusted native System V x86-64 function pointer with one word
// argument. The function must preserve the ABI's nonvolatile registers and
// stack discipline. Only call code whose lifetime and signature you control.
// Other targets and reference mode return zero without executing the pointer.
lowering native_call1 "machine.call1" "native-x86_64";
fn native_call1(pointer,argument) {return 0;}
