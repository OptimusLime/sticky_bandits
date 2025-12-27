#!/usr/bin/env python3
"""
Minimal HTTPS server for intercepting device connections.

Generates a self-signed cert on startup (or uses existing ones).
Logs ALL connection attempts including TLS failures.

Usage:
    sudo python scripts/intercept_server.py
"""

import argparse
import datetime
import json
import os
import socket
import ssl
import subprocess
import sys
import threading
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from socketserver import ThreadingMixIn

# Global log file path
LOG_FILE = None


def log(msg):
    """Log to stdout and file."""
    global LOG_FILE
    timestamp = datetime.datetime.now().isoformat()
    line = f"[{timestamp}] {msg}"
    print(line)
    if LOG_FILE:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


class InterceptHandler(BaseHTTPRequestHandler):
    """HTTP handler that logs everything and returns minimal responses."""
    
    def log_message(self, format, *args):
        """Override to log to our file."""
        log(f"[HTTP] [{self.client_address[0]}] {format % args}")
    
    def log_request_details(self):
        """Log full request details."""
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
            "client": client,
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers),
            "body": body,
        }
        
        log(f"[HTTP REQUEST] {json.dumps(details, indent=2)}")
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


class LoggingSSLSocket:
    """Wrapper around SSL socket that logs all connection attempts."""
    
    def __init__(self, sock, ssl_context, log_func):
        self.sock = sock
        self.ssl_context = ssl_context
        self.log_func = log_func
    
    def accept(self):
        """Accept connection and log TLS handshake attempts."""
        client_sock, addr = self.sock.accept()
        self.log_func(f"[TCP CONNECT] {addr[0]}:{addr[1]}")
        
        try:
            ssl_sock = self.ssl_context.wrap_socket(client_sock, server_side=True)
            self.log_func(f"[TLS SUCCESS] {addr[0]}:{addr[1]} - Handshake completed!")
            return ssl_sock, addr
        except ssl.SSLError as e:
            self.log_func(f"[TLS FAILED] {addr[0]}:{addr[1]} - SSLError: {e}")
            raise
        except Exception as e:
            self.log_func(f"[TLS FAILED] {addr[0]}:{addr[1]} - Error: {e}")
            raise
    
    def __getattr__(self, name):
        return getattr(self.sock, name)


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in separate threads."""
    daemon_threads = True
    

def generate_self_signed_cert(cert_dir: Path, domains: list):
    """Generate a self-signed certificate for the given domains."""
    cert_dir.mkdir(parents=True, exist_ok=True)
    
    key_file = cert_dir / "key.pem"
    cert_file = cert_dir / "cert.pem"
    
    # Always regenerate to ensure fresh certs
    log(f"[CERT] Generating self-signed cert for: {', '.join(domains)}")
    
    # Build SAN (Subject Alternative Names)
    san_entries = ",".join([f"DNS:{d}" for d in domains])
    
    # Generate key and cert with openssl
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key_file),
        "-out", str(cert_file),
        "-days", "365",
        "-nodes",
        "-subj", f"/CN={domains[0]}",
        "-addext", f"subjectAltName={san_entries}",
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log(f"[CERT ERROR] openssl failed: {result.stderr}")
        sys.exit(1)
    
    log(f"[CERT] Generated: {cert_file}")
    return str(cert_file), str(key_file)


def run_raw_ssl_listener(host, port, ssl_context):
    """
    Run a raw socket listener that logs ALL connection attempts,
    even ones that fail TLS handshake.
    """
    log(f"[RAW] Starting raw SSL listener on {host}:{port}")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    sock.listen(5)
    
    while True:
        try:
            client_sock, addr = sock.accept()
            log(f"[RAW TCP] Connection from {addr[0]}:{addr[1]}")
            
            # Try to do TLS handshake
            try:
                ssl_sock = ssl_context.wrap_socket(client_sock, server_side=True)
                log(f"[RAW TLS OK] {addr[0]}:{addr[1]} - Handshake SUCCESS!")
                
                # Try to read data
                try:
                    data = ssl_sock.recv(4096)
                    log(f"[RAW DATA] {addr[0]}:{addr[1]} - Received {len(data)} bytes: {data[:200]}")
                except Exception as e:
                    log(f"[RAW READ ERROR] {addr[0]}:{addr[1]} - {e}")
                
                ssl_sock.close()
            except ssl.SSLError as e:
                log(f"[RAW TLS FAIL] {addr[0]}:{addr[1]} - SSL Error: {e}")
                client_sock.close()
            except Exception as e:
                log(f"[RAW TLS FAIL] {addr[0]}:{addr[1]} - Error: {e}")
                client_sock.close()
                
        except Exception as e:
            log(f"[RAW ERROR] Accept error: {e}")


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
    
    log("=" * 60)
    log("INTERCEPT SERVER STARTING")
    log("=" * 60)
    
    # Generate certs
    cert_dir = Path(args.cert_dir)
    domains = ["ws.stickerbox.com", "localhost", "192.168.60.1"]
    cert_file, key_file = generate_self_signed_cert(cert_dir, domains)
    
    # Create SSL context
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(cert_file, key_file)
    
    log(f"[SERVER] Binding to {args.host}:{args.port}")
    log(f"[SERVER] Log file: {args.log_file}")
    log("")
    log("Waiting for connections...")
    log("")
    
    # Use raw SSL listener for maximum logging
    run_raw_ssl_listener(args.host, args.port, ssl_context)


if __name__ == "__main__":
    main()
