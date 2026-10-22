// Portable views with Monolith's existing loopback HTTP/SSE transport.
import "runtime.flex";
import "web-assets.flex";
import "../../scripts/lib/host.flex";
import "../monolith/support.flex";
import "../monolith/internal/launch.flex";
import "../monolith/internal/server.flex";
// Initial native records arrive through the versioned reconnect snapshot.
fn ui_html(b,node){m_text(b,"<p data-ui-error role=\"status\"></p>");return b;}
// Images may be served by the host or resolved to local snapshot URLs.
fn ui_image_policy(){return "img-src 'self' data: blob:; ";}
fn mono_style_css(){return "html,body{height:100%;margin:0}body>[data-mkey=mount]{height:100%;display:flex;flex-direction:column}button,input{font:inherit}button{cursor:pointer}";}
