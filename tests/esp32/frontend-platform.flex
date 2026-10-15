// Explicit trusted adapter. It can configure hardware and call typed app code.
global adapter_guard=1234567890123;
fn esp_platform_init() {if adapter_guard!=1234567890123 || startup(37)!=42 {return -1;}adapter_guard=42;return 0;}
