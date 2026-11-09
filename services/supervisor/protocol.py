"""BYOND's native Topic protocol. Never send control secrets to game clients."""
import json
import socket
import struct
import urllib.parse


def topic(port, key, action, payload=None, timeout=10):
    query = urllib.parse.urlencode({"babylon_control": 1, "format": "json",
                                   "key": key, "action": action,
                                   "payload": json.dumps(payload or {})}).encode()
    packet = b"\x00\x83" + struct.pack(">H", len(query) + 6) + b"\0" * 5 + query + b"\0"
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(packet)

        def exact(size):
            result = b""
            while len(result) < size:
                block = sock.recv(size - len(result))
                if not block:
                    raise ConnectionError("Child disconnected")
                result += block
            return result

        header = exact(4)
        if header[:2] != b"\x00\x83":
            raise ValueError("Invalid BYOND response")
        body = exact(struct.unpack(">H", header[2:])[0])
        if body[:1] != b"\x06":
            raise ValueError("Expected BYOND text response")
        return json.loads(body[1:].rstrip(b"\0"))
