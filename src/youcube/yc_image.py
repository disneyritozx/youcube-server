#!/usr/bin/env python3
from subprocess import run, PIPE
from typing import List

CC_COLORS = [
    (240, 240, 240), (242, 178, 51),  (229, 127, 216), (153, 178, 242),
    (222, 222, 108), (127, 204, 25),  (242, 178, 204), (76,  76,  76),
    (153, 153, 153), (76,  153, 178), (178, 102, 229), (51,  102, 204),
    (127, 102, 76),  (87,  166, 78),  (204, 76,  76),  (17,  17,  17),
]

HEX = "0123456789abcdef"


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
    result = run(
        [
            "ffmpeg", "-i", url,
            "-vf", f"scale={width}:{height}:flags=lanczos",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        stdout=PIPE, stderr=PIPE, timeout=60,
    )
    raw = result.stdout
    if not raw:
        raise ValueError("ffmpeg produced no output — unsupported URL or format")
    frame_size = width * height * 3
    frames = [
        _raw_to_nfp(raw[i: i + frame_size], width, height)
        for i in range(0, len(raw), frame_size)
        if len(raw[i: i + frame_size]) == frame_size
    ]
    if not frames:
        raise ValueError("no frames decoded")
    return frames
