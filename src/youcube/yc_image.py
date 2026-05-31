#!/usr/bin/env python3
import ipaddress
import socket
from subprocess import run, PIPE
from typing import List
from urllib.parse import urlparse

import requests as _requests

CC_COLORS = [
    (240, 240, 240), (242, 178, 51),  (229, 127, 216), (153, 178, 242),
    (222, 222, 108), (127, 204, 25),  (242, 178, 204), (76,  76,  76),
    (153, 153, 153), (76,  153, 178), (178, 102, 229), (51,  102, 204),
    (127, 102, 76),  (87,  166, 78),  (204, 76,  76),  (17,  17,  17),
]

HEX = "0123456789abcdef"

MAX_DOWNLOAD = 50 * 1024 * 1024  # 50 MB

def _is_blocked(addr: ipaddress._BaseAddress) -> bool:
    # Normalize IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1) before checking
    if isinstance(addr, ipaddress.IPv6Address) and addr.ipv4_mapped is not None:
        addr = addr.ipv4_mapped
    return (
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_multicast
        or addr.is_reserved
        or addr.is_unspecified
    )


def validate_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("URL must use http or https")
    if not parsed.hostname:
        raise ValueError("URL has no hostname")
    if parsed.username or parsed.password:
        raise ValueError("URL must not contain credentials")
    try:
        results = socket.getaddrinfo(parsed.hostname, None)
    except socket.gaierror:
        raise ValueError("could not resolve hostname")
    for result in results:
        addr = ipaddress.ip_address(result[4][0])
        if _is_blocked(addr):
            raise ValueError("URL resolves to a private address")


def _fetch(url: str, max_redirects: int = 5) -> bytes:
    """Fetch URL with manual redirect validation — ffmpeg never touches the network."""
    for _ in range(max_redirects):
        validate_url(url)  # re-validate every hop to catch open-redirect to private IP
        resp = _requests.get(url, allow_redirects=False, timeout=30, stream=True)
        if resp.status_code in (301, 302, 303, 307, 308):
            location = resp.headers.get("Location", "")
            if not location:
                raise ValueError("redirect with no Location header")
            url = location
            continue
        resp.raise_for_status()
        data = b""
        for chunk in resp.iter_content(chunk_size=65536):
            data += chunk
            if len(data) > MAX_DOWNLOAD:
                raise ValueError("response too large (max 50 MB)")
        return data
    raise ValueError("too many redirects")


def _nearest(r: int, g: int, b: int) -> int:
    best, best_d = 0, float("inf")
    for i, (cr, cg, cb) in enumerate(CC_COLORS):
        d = (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2
        if d < best_d:
            best_d, best = d, i
    return best


def _raw_to_nfp(raw: bytes, width: int, height: int) -> str:
    lines = []
    for y in range(height):
        row = []
        for x in range(width):
            o = (y * width + x) * 3
            row.append(HEX[_nearest(raw[o], raw[o + 1], raw[o + 2])])
        lines.append("".join(row))
    return "\n".join(lines)


def convert_image(url: str, width: int, height: int) -> List[str]:
    data = _fetch(url)  # we fetch; ffmpeg reads from stdin only
    result = run(
        [
            "ffmpeg", "-i", "pipe:0",
            "-vf", f"scale={width}:{height}:flags=lanczos",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        input=data, stdout=PIPE, stderr=PIPE, timeout=60,
    )
    raw = result.stdout
    if not raw:
        raise ValueError("unsupported format")
    frame_size = width * height * 3
    frames = [
        _raw_to_nfp(raw[i: i + frame_size], width, height)
        for i in range(0, len(raw), frame_size)
        if len(raw[i: i + frame_size]) == frame_size
    ]
    if not frames:
        raise ValueError("no frames decoded")
    return frames
