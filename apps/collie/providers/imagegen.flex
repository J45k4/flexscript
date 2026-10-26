// Codex's image endpoint is separate from its conversation Responses endpoint.
import "codex.flex";
fn ig_transport(auth){let out=co_transport(auth);j_set(out,"url",j_string("https://chatgpt.com/backend-api/codex/images/generations"));let headers=j_need(out,"headers");j_set(headers,"Accept",j_string("application/json"));j_set(out,"read_timeout_ms",j_int(240000));return out;}
