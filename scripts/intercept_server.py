#!/usr/bin/env python3
"""
Minimal HTTPS server for intercepting device connections.

Generates a self-signed cert on startup (or uses existing ones).
Logs all connection attempts, TLS handshakes, and HTTP requests.

Usage:
    sudo python scripts/intercept_server.py

Options:
    --host      IP to bind (default: 0.0.0.0)
    --port      Port to bind (default: 443)
    --cert-dir  Directory for certs (default: certs/)
    --log-file  Log file path (default: logs/intercept.log)
"""

import argparse
import datetime
import json
import os
import ssl
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Global log file path
LOG_FILE = None


class InterceptHandler(BaseHTTPRequestHandler):
    """HTTP handler that logs everything and returns minimal responses."""
    
    def log_message(self, format, *args):
        """Override to log to our file instead of stderr."""
        global LOG_FILE
        timestamp = datetime.datetime.now().isoformat()
        client = self.client_address[0]
        message = f"[{timestamp}] [{client}] {format % args}"
        print(message)
        if LOG_FILE:
            with open(LOG_FILE, "a") as f:
                f.write(message + "\n")
    
    def log_request_details(self):
        """Log full request details."""
        global LOG_FILE
        timestamp = datetime.datetime.now().isoformat()
        client = self.client_address[0]
        
        # Read body if present
        content_length = self.headers.get('Content-Length')
        body = None
        if content_length:
            try:
                body = self.rfile.read(int(content_length)).decode('utf-8', errors='replace')
            except Exception as e:
                body = f"<error reading body: {e}>"
        
        details = {
            "timestamp": timestamp,
            "client": client,
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers),
            "body": body,
        }
        
        log_line = f"[{timestamp}] [{client}] REQUEST: {json.dumps(details, indent=2)}"
        print(log_line)
        if LOG_FILE:
            with open(LOG_FILE, "a") as f:
                f.write(log_line + "\n")
        
        return details
    
    def send_json_response(self, status: int, data: dict):
        """Send a JSON response."""
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    
    def do_GET(self):
        self.log_request_details()
        self.send_json_response(200, {"status": "intercepted", "method": "GET", "path": self.path})
    
    def do_POST(self):
        self.log_request_details()
        self.send_json_response(200, {"status": "intercepted", "method": "POST", "path": self.path})
    
    def do_PUT(self):
        self.log_request_details()
        self.send_json_response(200, {"status": "intercepted", "method": "PUT", "path": self.path})
    
    def do_DELETE(self):
        self.log_request_details()
        self.send_json_response(200, {"status": "intercepted", "method": "DELETE", "path": self.path})
    
    def do_OPTIONS(self):
        self.log_request_details()
        self.send_response(200)
        self.send_header('Allow', 'GET, POST, PUT, DELETE, OPTIONS')
        self.end_headers()
    
    def do_HEAD(self):
        self.log_request_details()
        self.send_response(200)
        self.end_headers()


def generate_self_signed_cert(cert_dir: Path, domains: list):
    """Generate a self-signed certificate for the given domains."""
    cert_dir.mkdir(parents=True, exist_ok=True)
    
    key_file = cert_dir / "key.pem"
    cert_file = cert_dir / "cert.pem"
    
    if key_file.exists() and cert_file.exists():
        print(f"[*] Using existing certs in {cert_dir}")
        return str(cert_file), str(key_file)
    
    print(f"[*] Generating self-signed cert for: {', '.join(domains)}")
    
    # Build SAN (Subject Alternative Names)
    san_entries = ",".join([f"DNS:{d}" for d in domains])
    
    # Generate key and cert with openssl
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key_file),
        "-out", str(cert_file),
        "-days", "365",
        "-nodes",  # No password
        "-subj", f"/CN={domains[0]}",
        "-addext", f"subjectAltName={san_entries}",
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[!] openssl failed: {result.stderr}")
        sys.exit(1)
    
    print(f"[+] Generated: {cert_file}, {key_file}")
    return str(cert_file), str(key_file)


def main():
    global LOG_FILE
    
    parser = argparse.ArgumentParser(description="HTTPS intercept server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=443, help="Bind port")
    parser.add_argument("--cert-dir", default="certs", help="Certificate directory")
    parser.add_argument("--log-file", default="logs/intercept.log", help="Log file")
    args = parser.parse_args()
    
    # Ensure log directory exists
    log_path = Path(args.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    LOG_FILE = args.log_file
    
    # Generate or load certs
    cert_dir = Path(args.cert_dir)
    domains = ["ws.stickerbox.com", "localhost"]
    cert_file, key_file = generate_self_signed_cert(cert_dir, domains)
    
    # Create SSL context
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(cert_file, key_file)
    
    # Create server
    server = HTTPServer((args.host, args.port), InterceptHandler)
    server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
    
    print(f"[+] Intercept server starting on https://{args.host}:{args.port}")
    print(f"[+] Logging to: {args.log_file}")
    print(f"[+] Certs: {cert_file}")
    print("")
    print("Waiting for connections... (Ctrl+C to stop)")
    print("")
    
    # Log startup
    with open(LOG_FILE, "a") as f:
        f.write(f"\n[{datetime.datetime.now().isoformat()}] === SERVER STARTED on {args.host}:{args.port} ===\n")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
