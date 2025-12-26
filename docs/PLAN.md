# sticky_bandits — Work Plan

## Constraints

- **Device modality:** WiFi network selection + one physical button (generate)
- **No other access:** No USB, no debug mode, no config files, no companion app, no cert installation
- **Assumption:** Device uses HTTPS (TLS) for API calls — we cannot see HTTP payloads passively

## Goal

Replace the device's upstream image generation API with our own, so it generates images from our model instead of the vendor's.

## Approach

Build an end-to-end facade first. Each phase produces a **verified artifact** before proceeding. We do not move forward until verification passes.

---

## Phase 1: Capture and Identify Target Host

**Objective:** Determine the exact hostname(s) the device contacts for image generation.

**Tasks:**
1. Run `sudo bash scripts/install_ubuntu22.sh` on Ubuntu box
2. Identify interfaces with `ip link` — note WiFi interface (AP_IFACE) and internet uplink (UPLINK_IFACE)
3. Run `sudo AP_IFACE=<wifi> UPLINK_IFACE=<uplink> SSID="sticky_bandits" PASSPHRASE="<pass>" bash scripts/ap_up.sh`
4. On device, connect to WiFi network "sticky_bandits" with the passphrase
5. Run `sudo AP_IFACE=<wifi> bash scripts/capture.sh start`
6. Press generate button on device once, wait for it to complete (success or failure)
7. Run `sudo bash scripts/capture.sh stop`
8. Run `bash scripts/collect.sh captures/latest.pcap`
9. Run `. .venv/bin/activate && python analysis/analyze_capture.py --input reports/capture_* --out reports/summary.md` (use the actual capture directory name)

**Output artifact:** `reports/<capture>/summary.md`

**Verification:**

Run: `cat reports/<capture>/summary.md`

- [ ] File exists and is not empty
- [ ] "Top TLS SNI hostnames" section contains at least one hostname
- [ ] One hostname has high request count and large data transfer (this is likely the API)

Record the identified API hostname in `docs/TARGET.md`:
```
echo "TARGET_HOST=api.example.com" > docs/TARGET.md
```

**Done when:** `docs/TARGET.md` exists with a hostname.

---

## Phase 2: DNS Hijack to Local Server

**Objective:** Prove we can intercept the device's connection attempt by redirecting DNS.

**Tasks:**
1. Read target hostname: `cat docs/TARGET.md`
2. Write script `scripts/intercept_server.py` — a minimal HTTPS server that:
   - Generates a self-signed cert on startup (or uses one from `certs/`)
   - Listens on port 443
   - Logs all connection attempts (IP, timestamp) to stdout
   - Logs TLS handshake success/failure
   - If TLS succeeds, logs full HTTP request (method, path, headers, body) and returns HTTP 200 with empty JSON `{}`
3. Generate self-signed cert: `mkdir -p certs && openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/CN=<TARGET_HOST>"`
4. Add DNS override to dnsmasq: `echo "address=/<TARGET_HOST>/192.168.50.1" | sudo tee /etc/dnsmasq.d/intercept.conf`
5. Restart dnsmasq: `sudo systemctl restart dnsmasq`
6. Start intercept server: `sudo python scripts/intercept_server.py --cert certs/cert.pem --key certs/key.pem > logs/intercept.log 2>&1 &`
7. Press generate button on device
8. Wait 30 seconds, then stop server (Ctrl+C or kill)

**Output artifact:** `logs/intercept.log`

**Verification:**

Run: `cat logs/intercept.log`

- [ ] Log contains line showing TCP connection from device IP (192.168.50.x)
- [ ] Log contains line showing TLS handshake attempt

**Done when:** `logs/intercept.log` shows a connection attempt from the device.

---

## Phase 3: Determine TLS Feasibility

**Objective:** Determine if the device validates certificates strictly (pinning) or accepts any valid-looking cert.

**Tasks:**
1. Review `logs/intercept.log` from Phase 2
2. Check for HTTP request data in the log:
   - If log contains HTTP method/path/headers → device accepted self-signed cert → **GREEN PATH**
   - If log shows TLS handshake failed or connection reset → device rejected cert → continue to task 3
3. (Only if cert rejected) Test with real CA cert:
   - Option A: Use a domain you control, get Let's Encrypt cert, point DNS to gateway
   - Option B: Use mitmproxy with `--certs` option for a real cert
   - Repeat Phase 2 tasks 6-8 with real cert
   - If HTTP request appears → **YELLOW PATH** (rejects self-signed, accepts valid CA)
   - If still rejected → **RED PATH** (cert pinning, project blocked)
4. Write findings to `docs/TLS_FINDINGS.md`:
   ```
   TLS_STATUS=green|yellow|red
   EVIDENCE=<one-line summary of what logs showed>
   ```

**Output artifact:** `docs/TLS_FINDINGS.md`

**Verification:**

Run: `cat docs/TLS_FINDINGS.md`

- [ ] File contains TLS_STATUS line with value green, yellow, or red
- [ ] If red: STOP. Document findings and assess if project can continue.

**Done when:** `docs/TLS_FINDINGS.md` exists with green or yellow status (or project stops on red).

---

## Phase 4: Capture Full HTTP Request

**Objective:** See the actual HTTP request the device sends.

**Precondition:** `cat docs/TLS_FINDINGS.md` shows TLS_STATUS=green or TLS_STATUS=yellow

**Tasks:**
1. Ensure `scripts/intercept_server.py` logs full HTTP request details (method, path, headers, body)
2. If Phase 3 was yellow (needs real cert), update cert paths in the command
3. Start intercept server: `sudo python scripts/intercept_server.py --cert <cert> --key <key> --log-requests > logs/http_capture.log 2>&1 &`
4. Press generate button on device
5. Wait for device to complete or timeout (60 seconds)
6. Stop server
7. Extract request data from log to JSON:
   ```
   python scripts/extract_request.py logs/http_capture.log > reports/http_request_sample.json
   ```
   (Write `scripts/extract_request.py` to parse log into structured JSON if not exists)

**Output artifact:** `reports/http_request_sample.json`

**Verification:**

Run: `cat reports/http_request_sample.json | python -m json.tool`

- [ ] JSON is valid (command succeeds)
- [ ] Contains "method" field (e.g., "POST", "GET")
- [ ] Contains "path" field (e.g., "/v1/generate")
- [ ] Contains "headers" object
- [ ] Contains "body" field (string, object, or null)

**Done when:** `reports/http_request_sample.json` contains valid request structure.

---

## Phase 5: Capture Full HTTP Response

**Objective:** Understand what response format the device expects.

**Precondition:** `reports/http_request_sample.json` exists with valid request structure

**Tasks:**
1. Write `scripts/proxy_server.py` — HTTPS server that:
   - Accepts device request
   - Forwards request to real upstream API (read TARGET_HOST from `docs/TARGET.md`)
   - Logs full response (status, headers, body) to file
   - Returns response to device unchanged
2. Start proxy server: `sudo python scripts/proxy_server.py --cert <cert> --key <key> > logs/proxy.log 2>&1 &`
3. Press generate button on device
4. Wait for full flow to complete (image generation may take 10-60 seconds)
5. Stop server
6. Extract response data:
   ```
   python scripts/extract_response.py logs/proxy.log > reports/http_response_sample.json
   ```
7. Document the API flow in `docs/API_FLOW.md`:
   - Is it single request/response?
   - Is there a job ID returned, then polling?
   - Is response streamed or chunked?
   - Where does the image come from (inline base64, URL, separate download)?

**Output artifacts:** 
- `reports/http_response_sample.json`
- `docs/API_FLOW.md`

**Verification:**

Run: `cat reports/http_response_sample.json | python -m json.tool`

- [ ] JSON is valid
- [ ] Contains "status" field (e.g., 200)
- [ ] Contains "headers" object
- [ ] Contains "body" field

Run: `cat docs/API_FLOW.md`

- [ ] Describes request/response pattern
- [ ] Describes how image data is delivered

**Done when:** Both files exist and `docs/API_FLOW.md` describes the full flow.

---

## Phase 6: Build Stub Shim

**Objective:** Return a hardcoded valid response to prove the device accepts our server's output.

**Precondition:** `docs/API_FLOW.md` exists and describes the expected response format

**Tasks:**
1. Create `shim/` directory: `mkdir -p shim`
2. Add a test image: `cp <any-png-or-jpg> shim/test_image.png` (or download one)
3. Write `shim/stub_server.py` — HTTPS server that:
   - Reads expected response format from `docs/API_FLOW.md` or `reports/http_response_sample.json`
   - Returns a hardcoded response matching that format
   - Substitutes `shim/test_image.png` as the image (base64 encode if inline, or serve at expected URL path)
4. Start stub server: `sudo python shim/stub_server.py --cert <cert> --key <key> &`
5. Ensure DNS override still points TARGET_HOST to gateway (from Phase 2)
6. Press generate button on device
7. Observe device behavior — does it print?

**Output artifact:** `shim/stub_server.py`

**Verification:**

Physical check:
- [ ] Device prints a sticker
- [ ] Sticker contains the test image from `shim/test_image.png`

If device does NOT print:
- Check `logs/stub.log` for errors
- Compare response format against `reports/http_response_sample.json`
- Iterate on `shim/stub_server.py` until device accepts response

**Done when:** Device prints a sticker with the test image.

---

## Phase 7: Integrate Local Model

**Objective:** Replace hardcoded image with output from our image generation model.

**Precondition:** Phase 6 verified — device prints sticker with stub server

**Tasks:**
1. Document local model API in `docs/LOCAL_MODEL.md`:
   - Endpoint URL
   - Request format (how to send prompt)
   - Response format (how image is returned)
2. Write `shim/model_client.py` — module that:
   - Takes a prompt string
   - Calls local model API
   - Returns image bytes
3. Modify `shim/stub_server.py` → `shim/server.py`:
   - Extract prompt from device request (based on `reports/http_request_sample.json` structure)
   - Call `model_client.generate(prompt)`
   - Format response with generated image
4. Start server: `sudo python shim/server.py --cert <cert> --key <key> &`
5. Press generate button on device

**Output artifact:** `shim/server.py` with model integration

**Verification:**

1. Press generate button
2. Wait for sticker to print
3. Examine printed sticker:
   - [ ] Sticker printed successfully
   - [ ] Image is NOT the test image from Phase 6 (proves model was called)
   - [ ] Image is reasonable output from your model

Optional additional check — inspect server logs:
```
grep "model request" logs/shim.log
```
- [ ] Log shows prompt was extracted and sent to model

**Done when:** Device prints a sticker with an image generated by your local model.

---

## Phase Dependency Graph

```
Phase 1 (identify host)
    │
    v
Phase 2 (DNS hijack)
    │
    v
Phase 3 (TLS feasibility) ──── RED PATH ───> STOP or research pinning bypass
    │
    GREEN/YELLOW PATH
    v
Phase 4 (capture request)
    │
    v
Phase 5 (capture response)
    │
    v
Phase 6 (stub shim)
    │
    v
Phase 7 (model integration)
```

---

## Current Status

**Phase:** 1 — Not started  
**Next action:** Run `sudo bash scripts/install_ubuntu22.sh` on Ubuntu box

---

## Status Checklist

- [ ] Phase 1: `docs/TARGET.md` exists with hostname
- [ ] Phase 2: `logs/intercept.log` shows device connection
- [ ] Phase 3: `docs/TLS_FINDINGS.md` shows green or yellow
- [ ] Phase 4: `reports/http_request_sample.json` is valid JSON
- [ ] Phase 5: `reports/http_response_sample.json` + `docs/API_FLOW.md` exist
- [ ] Phase 6: Device prints test image sticker
- [ ] Phase 7: Device prints model-generated image sticker

---

## Notes

- If Phase 3 results in RED PATH (cert pinning), document findings and stop. Bypassing pinning on embedded firmware is out of scope.
- Each phase depends only on the previous phase. No skipping.
- All scripts referenced must exist before the task that uses them. If a task says "run script X", a prior task must create script X.
