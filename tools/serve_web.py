#!/usr/bin/env python3
"""Serve web/ with COOP/COEP so Godot threaded WASM can use SharedArrayBuffer."""
from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class CoopHandler(SimpleHTTPRequestHandler):
	extensions_map = {
		**getattr(SimpleHTTPRequestHandler, "extensions_map", {}),
		".wasm": "application/wasm",
		".pck": "application/octet-stream",
		".js": "application/javascript",
	}

	def end_headers(self) -> None:
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		self.send_header("Cross-Origin-Resource-Policy", "same-origin")
		self.send_header("Cache-Control", "no-store")
		super().end_headers()


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--dir", default="web")
	parser.add_argument("--port", type=int, default=8060)
	args = parser.parse_args()
	root = Path(args.dir).resolve()
	handler = partial(CoopHandler, directory=str(root))
	server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
	print(f"Serving {root} at http://127.0.0.1:{args.port}/ (COOP/COEP)")
	server.serve_forever()


if __name__ == "__main__":
	main()
