#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import pathlib
from collections import Counter, defaultdict
from datetime import datetime, timezone

import pandas as pd


def load_csv(path: pathlib.Path) -> pd.DataFrame:
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()
    try:
        return pd.read_csv(path)
    except Exception:
        # Fallback if tshark produced odd quoting
        return pd.read_csv(path, engine="python")


def epoch_to_iso(epoch: float) -> str:
    dt = datetime.fromtimestamp(float(epoch), tz=timezone.utc)
    return dt.isoformat()


def top_n(counter: Counter, n: int = 20) -> list[tuple[str, int]]:
    return counter.most_common(n)


def parse_conv_txt(path: pathlib.Path) -> list[str]:
    if not path.exists():
        return []
    lines = path.read_text(errors="ignore").splitlines()
    # Keep a small useful slice (the "Conversation" table)
    # tshark output varies; include non-empty lines, trimmed.
    out = []
    for ln in lines:
        ln = ln.rstrip()
        if ln.strip():
            out.append(ln)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Analyze extracted tshark CSVs and summarize behavior.")
    ap.add_argument("--input", required=True, help="Directory produced by scripts/collect.sh (e.g., reports/capture_2025...)")
    ap.add_argument("--out", default="", help="Write markdown summary to this path (default: <input>/summary.md)")
    args = ap.parse_args()

    in_dir = pathlib.Path(args.input).expanduser().resolve()
    if not in_dir.exists():
        raise SystemExit(f"Input dir not found: {in_dir}")

    out_path = pathlib.Path(args.out).expanduser().resolve() if args.out else (in_dir / "summary.md")

    meta = {}
    meta_path = in_dir / "meta.json"
    if meta_path.exists():
        meta = json.loads(meta_path.read_text())

    dns = load_csv(in_dir / "dns_queries.csv")
    tls = load_csv(in_dir / "tls_sni.csv")
    http = load_csv(in_dir / "http_requests.csv")
    udp443 = load_csv(in_dir / "udp_443.csv")

    # Normalize columns (tshark uses exact names we set)
    # DNS
    dns_names = Counter()
    dns_srcs = Counter()
    if not dns.empty and "dns.qry.name" in dns.columns:
        dns_names.update(dns["dns.qry.name"].dropna().astype(str).tolist())
        if "ip.src" in dns.columns:
            dns_srcs.update(dns["ip.src"].dropna().astype(str).tolist())

    # TLS
    sni = Counter()
    alpn = Counter()
    tls_srcs = Counter()
    if not tls.empty and "tls.handshake.extensions_server_name" in tls.columns:
        sni.update(tls["tls.handshake.extensions_server_name"].dropna().astype(str).tolist())
        if "tls.handshake.extensions_alpn_str" in tls.columns:
            alpn.update(tls["tls.handshake.extensions_alpn_str"].dropna().astype(str).tolist())
        if "ip.src" in tls.columns:
            tls_srcs.update(tls["ip.src"].dropna().astype(str).tolist())

    # HTTP
    http_hosts = Counter()
    http_paths = Counter()
    http_methods = Counter()
    if not http.empty and "http.host" in http.columns:
        http_hosts.update(http["http.host"].dropna().astype(str).tolist())
        if "http.request_uri" in http.columns:
            http_paths.update(http["http.request_uri"].dropna().astype(str).tolist())
        if "http.request_method" in http.columns:
            http_methods.update(http["http.request_method"].dropna().astype(str).tolist())

    # QUIC hint
    quic_hint = False
    if not udp443.empty:
        quic_hint = True

    conv_tcp = parse_conv_txt(in_dir / "conv_tcp.txt")
    conv_udp = parse_conv_txt(in_dir / "conv_udp.txt")

    # Build report
    lines: list[str] = []
    lines.append(f"# sticky_bandits capture summary\n")
    if meta:
        lines.append("## Capture metadata\n")
        lines.append(f"- PCAP: `{meta.get('pcap_path','')}`")
        lines.append(f"- Size: `{meta.get('pcap_size_bytes','')}` bytes")
        mt = meta.get("pcap_mtime_epoch")
        if mt:
            lines.append(f"- Modified (UTC): `{epoch_to_iso(mt)}`")
        lines.append(f"- SHA256: `{meta.get('pcap_sha256','')}`\n")

    lines.append("## High-level signals\n")
    lines.append(f"- HTTP requests seen: **{0 if http.empty else len(http)}**")
    lines.append(f"- TLS SNI seen: **{0 if tls.empty else len(tls)}**")
    lines.append(f"- DNS queries seen: **{0 if dns.empty else len(dns)}**")
    lines.append(f"- UDP/443 present (QUIC/HTTP3 hint): **{quic_hint}**\n")

    lines.append("## Top DNS names\n")
    if dns_names:
        for name, cnt in top_n(dns_names, 25):
            lines.append(f"- `{name}` — {cnt}")
    else:
        lines.append("_No DNS query names extracted (device may use DoH/DoT, cached DNS, or capture missed DNS)._")
    lines.append("")

    lines.append("## Top TLS SNI hostnames\n")
    if sni:
        for host, cnt in top_n(sni, 25):
            lines.append(f"- `{host}` — {cnt}")
    else:
        lines.append("_No TLS SNI extracted (could be QUIC only, ECH, or no handshakes in capture)._")
    lines.append("")

    lines.append("## ALPN (HTTP version hint)\n")
    if alpn:
        for proto, cnt in top_n(alpn, 20):
            lines.append(f"- `{proto}` — {cnt}")
    else:
        lines.append("_No ALPN values extracted._")
    lines.append("")

    lines.append("## HTTP (if any)\n")
    if not http.empty:
        lines.append("### Methods\n")
        for m, cnt in top_n(http_methods, 10):
            lines.append(f"- `{m}` — {cnt}")
        lines.append("\n### Hosts\n")
        for h, cnt in top_n(http_hosts, 20):
            lines.append(f"- `{h}` — {cnt}")
        lines.append("\n### Paths (top)\n")
        for p, cnt in top_n(http_paths, 30):
            lines.append(f"- `{p}` — {cnt}")
    else:
        lines.append("_No plaintext HTTP requests were captured; traffic is likely HTTPS._")
    lines.append("")

    lines.append("## Conversation summaries (raw)\n")
    lines.append("### TCP conversations (tshark -z conv,tcp)\n")
    if conv_tcp:
        lines.append("```")
        lines.extend(conv_tcp[:200])
        if len(conv_tcp) > 200:
            lines.append("... (truncated)")
        lines.append("```")
    else:
        lines.append("_No tcp conv output._")
    lines.append("\n### UDP conversations (tshark -z conv,udp)\n")
    if conv_udp:
        lines.append("```")
        lines.extend(conv_udp[:200])
        if len(conv_udp) > 200:
            lines.append("... (truncated)")
        lines.append("```")
    else:
        lines.append("_No udp conv output._")
    lines.append("")

    lines.append("## Interpretation / next actions\n")
    if http.empty:
        lines.append("- Since HTTP isn’t visible, focus on **DNS + TLS SNI + flow patterns** to identify the upstream service(s).")
        lines.append("- If you need full request/response bodies, you’ll need a **cooperative path** (device proxy setting, trusted CA install, vendor debug mode, or a configurable base URL).")
    else:
        lines.append("- Plain HTTP was observed — you can reconstruct full request/response schemas directly from Wireshark/pcap.")
    if quic_hint:
        lines.append("- UDP/443 suggests QUIC/HTTP3 traffic; some analyses are easier if you temporarily block UDP/443 on the gateway to force TCP/TLS (for observation only).")
    lines.append("")

    out_path.write_text("\n".join(lines))
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
