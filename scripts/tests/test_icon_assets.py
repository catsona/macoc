#!/usr/bin/env python3
"""Portable macOS app icon checks. Uses only the Python standard library."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Resources/IconArtwork.jpg"
MASTER = ROOT / "Resources/AppIcon.png"
PREVIEW = ROOT / "Resources/AppIcon-preview.png"
LAYOUT = ROOT / "Resources/AppIconLayout.json"
SVG = ROOT / "Resources/AppIconArtwork.svg"
ICONSET = ROOT / "build/macoc.iconset"

SIZE_NAMES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def jpeg_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        raise ValueError(f"not a JPEG: {path}")
    index = 2
    while index < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        while index < len(data) and data[index] == 0xFF:
            index += 1
        marker = data[index]
        index += 1
        if marker in (0xD8, 0xD9, 0x00) or 0xD0 <= marker <= 0xD7:
            continue
        if index + 2 > len(data):
            break
        segment_length = struct.unpack(">H", data[index:index+2])[0]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3):
            height, width = struct.unpack(">HH", data[index+3:index+7])
            return width, height
        index += segment_length
    raise ValueError(f"no JPEG SOF marker: {path}")


def png_info(path: Path) -> tuple[int, int, int]:
    header = path.read_bytes()[:26]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"not a PNG: {path}")
    width, height = struct.unpack(">II", header[16:24])
    return width, height, header[25]


def alpha_at(path: Path, x: int, y: int) -> int:
    """Decode an RGBA PNG scanline, supporting all five PNG row filters."""
    data = path.read_bytes()
    width, height, color = png_info(path)
    if color != 6 or data[24] != 8:
        raise ValueError("expected 8-bit RGBA PNG")
    if not (0 <= x < width and 0 <= y < height):
        raise ValueError("pixel outside PNG")

    offset = 8
    compressed = []
    while offset < len(data):
        size = struct.unpack(">I", data[offset:offset+4])[0]
        kind = data[offset+4:offset+8]
        if kind == b"IDAT":
            compressed.append(data[offset+8:offset+8+size])
        offset += 12 + size
        if kind == b"IEND":
            break

    raw = zlib.decompress(b"".join(compressed))
    stride = width * 4
    previous = bytearray(stride)
    position = 0

    for row_number in range(y + 1):
        filter_type = raw[position]
        position += 1
        row = bytearray(raw[position:position+stride])
        position += stride

        for i in range(stride):
            left = row[i-4] if i >= 4 else 0
            above = previous[i]
            upper_left = previous[i-4] if i >= 4 else 0

            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                prediction = left + above - upper_left
                da = abs(prediction - left)
                db = abs(prediction - above)
                dc = abs(prediction - upper_left)
                predictor = left if da <= db and da <= dc else (
                    above if db <= dc else upper_left
                )
            elif filter_type == 0:
                predictor = 0
            else:
                raise ValueError(f"unsupported PNG filter: {filter_type}")

            row[i] = (row[i] + predictor) & 0xFF

        previous = row

    return previous[x * 4 + 3]


class AppIconAssetTests(unittest.TestCase):
    def test_artwork_source_is_square(self):
        w, h = jpeg_dimensions(SOURCE)
        self.assertEqual(w, h)
        self.assertGreaterEqual(w, 256)

    def test_reference_layout_uses_centered_1024_grid(self):
        layout = json.loads(LAYOUT.read_text())
        self.assertEqual(layout["canvasPixels"], 1024)
        self.assertEqual(layout["bodyPixels"], 824)
        self.assertEqual(layout["bodyOrigin"], [100, 100])
        self.assertGreater(layout["superellipseExponent"], 3)
        self.assertLess(layout["superellipseExponent"], 6)
        self.assertEqual(len(layout["sourceCrop"]), 4)
        self.assertTrue(all(0 <= x <= 1 for x in layout["sourceCrop"]))
        self.assertLess(layout["sourceCrop"][0], layout["sourceCrop"][2])
        self.assertLess(layout["sourceCrop"][1], layout["sourceCrop"][3])

    def test_master_has_transparent_corners(self):
        self.assertEqual(png_info(MASTER), (1024, 1024, 6))
        for point in [(0, 0), (1023, 0), (0, 1023), (1023, 1023)]:
            with self.subTest(corner=point):
                self.assertEqual(alpha_at(MASTER, *point), 0)
        self.assertEqual(alpha_at(MASTER, 512, 512), 255)

    def test_preview_is_real_png_and_linked_from_readme(self):
        w, h, color = png_info(PREVIEW)
        self.assertEqual((w, h, color), (256, 256, 6))
        self.assertEqual(alpha_at(PREVIEW, 0, 0), 0)
        readme = (ROOT / "README.md").read_text()
        self.assertIn("Resources/AppIcon-preview.png", readme)

    def test_svg_is_editable_and_pipeline_uses_master(self):
        svg = SVG.read_text()
        self.assertIn('viewBox="0 0 1024 1024"', svg)
        self.assertIn('clipPath id="icon-body"', svg)
        self.assertIn('IconArtwork.jpg', svg)
        script = (ROOT / "scripts/icon.sh").read_text()
        self.assertIn("Resources/AppIcon.png", script)
        self.assertIn("iconutil -c icns", script)
        self.assertIn("sips -s format png", script)

    @unittest.skipUnless(ICONSET.exists(), "generated macOS iconset unavailable")
    def test_iconset_contains_all_ten_variants(self):
        self.assertEqual({p.name for p in ICONSET.glob("*.png")}, set(SIZE_NAMES))
        for name, pixels in SIZE_NAMES.items():
            with self.subTest(filename=name):
                w, h, color = png_info(ICONSET / name)
                self.assertEqual((w, h), (pixels, pixels))
                self.assertIn(color, (2, 6))


if __name__ == "__main__":
    unittest.main(verbosity=2)
