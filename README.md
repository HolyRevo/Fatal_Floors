# Fatal Floors Hub — v1.0

Single-file Roblox Lua release. The access key entered at runtime determines which server-authorized build is loaded:

- Customer keys load the public release.
- A key the backend identifies as an owner key loads Owner Beta.

The client does not hardcode the owner key. Supabase remains authoritative for license validation and owner status.

## Features retained

- Supabase-backed license validation
- Saved access key and automatic revalidation
- Change / switch access key from the hub settings
- Teleport re-execution when the executor supports `queue_on_teleport`
- Existing hub features from the v8.2 single-file baseline

## v1.0 key-screen changes

- Refreshed key-gate layout and gradient header
- Drag the key window by its title bar (mouse or touch)
- X button exits the script cleanly while the key gate is open

## Install

Run `Fatal_Floors_Hub_v1.0.lua` in an executor that supports the APIs used by the script. Keep the backend URL and publishable key configuration intact. Never add Supabase service-role keys or provider secrets to the client script.

## Notes

This release is based on the saved `Fatal_Floors_Hub_v8.2_KeyBased.lua` source. The gameplay automation and game-specific remote interactions are inherited from that baseline and have not been independently validated against a live game server in this packaging step.
