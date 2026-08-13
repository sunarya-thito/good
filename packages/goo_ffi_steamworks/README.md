# goo_ffi_steamworks

Raw `ffigen` bindings to Steamworks' `steam_api_flat.h` (Valve's own
flattened C API). Kept separate from [`goo_net_steam`](../goo_net_steam)'s
ergonomic API so the generated bindings can be regenerated independently of
the API built on top of them.

The Steamworks SDK itself is not redistributed in this repo (Valve's EULA) -
consumers of this package fetch it themselves.

Status: **placeholder.** This is Phase 3 of the project root plan; nothing
here is implemented yet.
