# Protocol test inputs

Unmodified XML from upstream wayland-protocols 1.49, copied from the installed
package on the target machine. `manifest.json` records the upstream URL, version
and SHA-256 hashes. Every file retains its upstream license and copyright notice.

These are the canonical inputs for the checked-in Flexscript protocol metadata.
Keeping the inputs here makes scanner/ABI tests reproducible on CI distributions
whose protocol packages predate these versions. The application uses generated
Flexscript metadata and does not load XML, a scanner or a C shim at runtime.

`scripts/wayland-protocols.flex` generates the application tables. The independent
test `scripts/test-wayland-metadata.py` checks regeneration and compares all
interfaces against `wayland-scanner` C metadata and public library ABI headers.
The C scanner is a test oracle only.
