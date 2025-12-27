# Target Information

## Device
- Name: stickerbox
- MAC: 80:b5:4e:95:c3:9c
- IP: 192.168.60.18 (DHCP from our AP)

## Endpoints (verified via capture)
- `api.stickerbox.com` — REST API (authentication, config)
- `ws.stickerbox.com` — WebSocket (generation jobs, image transfer)

## Backend
- IPs: 104.20.35.155, 172.66.148.165 (Cloudflare)
- Protocol: HTTPS/WSS (port 443)
- No QUIC/HTTP3

## Phase 1 Status: COMPLETE
- [x] Device connects to AP
- [x] Device gets DHCP lease
- [x] DNS queries captured (api.stickerbox.com, ws.stickerbox.com)
- [x] TLS SNI captured (confirms both endpoints)
- [x] Traffic flow observed (auth + websocket pattern)

## Next: Phase 2
DNS hijack both endpoints to our local server to test if device accepts our cert.
