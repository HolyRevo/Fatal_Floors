# Fatal Floors Hub — v1.0

Single-file Roblox Lua release. The access key entered at runtime determines which server-authorized build is loaded:

- Customer keys load the public release.
- A key the backend identifies a valid key and locks it to you hardware id.

Supabase remains authoritative for license validation and status.

## Features retained

- Supabase-backed license validation
- Saved access key and automatic revalidation
- Change / switch access key from the hub settings
- Teleport re-execution when the executor supports `queue_on_teleport`
- Existing hub features from the lua single-file baseline

## v1.0 key-screen changes

- Refreshed key-gate layout and gradient header
- Drag the key window by its title bar (mouse or touch)
- X button exits the script cleanly while the key gate is open
