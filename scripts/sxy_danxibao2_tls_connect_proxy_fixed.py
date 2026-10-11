#!/usr/bin/env python3
"""Loopback CONNECT-only proxy with pinned trusted endpoints, no TLS interception."""
import select
import socket
import socketserver

LISTEN = ("127.0.0.1", 19324)
TARGETS = {
    b"pan.evren.cn:443": ("172.67.149.132", "104.21.33.205"),
    b"qd01-httpdown.guangyacdn.com:443": ("150.139.136.76",),
    b"qd02-httpdown.guangyacdn.com:443": ("150.139.132.12", "120.221.22.46"),
    b"sh01-httpdown.guangyacdn.com:443": ("218.91.199.89",),
    b"sh02-httpdown.guangyacdn.com:443": ("218.91.170.219",),
    b"ydfh01-httpdown.guangyacdn.cn:443": ("223.109.90.155",),
    b"ydfh02-httpdown.guangyacdn.cn:443": ("223.109.91.146",),
}

class ProxyHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(20)
        request = b""
        while b"\r\n\r\n" not in request and len(request) < 8192:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            request += chunk
        first_line = request.split(b"\r\n", 1)[0].split()
        if len(first_line) != 3 or first_line[0] != b"CONNECT":
            self.request.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            return
        target = first_line[1].lower()
        if target not in TARGETS:
            self.request.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            return
        upstream = None
        for ip in TARGETS[target]:
            try:
                upstream = socket.create_connection((ip, 443), timeout=8)
                break
            except OSError:
                continue
        if upstream is None:
            self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        with upstream:
            self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            self.request.settimeout(None)
            upstream.settimeout(None)
            channels = (self.request, upstream)
            while True:
                readable, _, _ = select.select(channels, [], [], 180)
                if not readable:
                    break
                for sock in readable:
                    data = sock.recv(65536)
                    if not data:
                        return
                    (upstream if sock is self.request else self.request).sendall(data)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    with Server(LISTEN, ProxyHandler) as server:
        server.serve_forever(poll_interval=0.5)
