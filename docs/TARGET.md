# Target Information

## Device
DEVICE_NAME=stickerbox
DEVICE_MAC=80:b5:4e:95:c3:9c
DEVICE_IP=192.168.60.18
DISCOVERED=2025-12-27

## Endpoints (discovered)
- `api.stickerbox.com` — seen in DNS queries (likely REST API)
- `ws.stickerbox.com` — seen in TLS SNI (likely WebSocket)

## Backend
- IPs resolve to Cloudflare (172.66.148.165, 104.20.35.155)
- All traffic is HTTPS (port 443)
- No QUIC/HTTP3 detected

## Flow (observed)
1. Device connects to wifi
2. Device queries DNS for api.stickerbox.com
3. Device establishes TLS to ws.stickerbox.com (WebSocket?)
4. If WebSocket fails, device cannot proceed to generation

## Phase 1 Status
- [x] Device connects to AP
- [x] Device gets DHCP lease  
- [x] DNS queries captured
- [x] TLS SNI captured
- [ ] Full generation flow captured (device failing before generation)
