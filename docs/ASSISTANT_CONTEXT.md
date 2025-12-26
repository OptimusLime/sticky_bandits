# sticky_bandits — assistant context

## What this repo is
We’re building a controlled Wi‑Fi network (AP + gateway) on Ubuntu 22.04 to observe a device’s network behavior so we can:
- identify which domains/services it talks to for image generation,
- understand request/response structures *when feasible*,
- and eventually build a local “compatibility shim” that speaks the same API contract but routes generation to our own local image model + LoRA.

## Important constraints
- If the device uses HTTPS with normal certificate validation, network-side capture will not reveal HTTP headers/bodies.
- This repo intentionally avoids bypassing TLS protections (pinning/mTLS). The “plan A” is cooperative configuration:
  - a device setting for custom endpoint / base URL,
  - a proxy setting,
  - ability to install a trusted CA (dev mode),
  - or vendor-provided debugging/logging.
- When HTTPS is opaque, we still learn a lot from metadata:
  - DNS names and TLS SNI hostnames,
  - TCP/443 vs UDP/443 (QUIC/HTTP3),
  - polling patterns and CDN downloads,
  - payload size ranges and timing.

## Key files & directories (bash-friendly)
From repo root:
- `scripts/install_ubuntu22.sh`
- `scripts/ap_up.sh`
- `scripts/ap_down.sh`
- `scripts/capture.sh`
- `scripts/collect.sh`
- `analysis/analyze_capture.py`
- `captures/` (pcap outputs; `captures/latest.pcap` symlink)
- `reports/` (structured CSV/text outputs and markdown summary)
- `config/` (templates used by scripts)

## Current plans (incremental)
1) Bring up AP/gateway reliably (hostapd + dnsmasq + NAT).
2) Capture traffic and extract:
   - DNS names
   - TLS SNI and ALPN
   - any plaintext HTTP (if present)
   - endpoints and conversation summaries
3) Confirm feasibility:
   - If plaintext HTTP exists: reconstruct exact schemas from PCAP.
   - If only HTTPS: seek cooperative methods to observe payloads (proxy setting / trusted CA / configurable base URL / debug logs).
4) Endgame:
   - Implement a local API shim that matches the upstream contract.
   - Route generation to a local model endpoint (LoRA-enabled).
   - Keep output formatting identical to what the device expects (job polling, presigned URL flow, streaming, etc.).

## How assistants should respond
- Prefer safe, reproducible debugging steps.
- Avoid instructions that enable covert interception or TLS-bypass.
- When proposing new scripts, keep them idempotent and reversible, and prefer drop-in configs (e.g., `/etc/dnsmasq.d/*.conf`).
