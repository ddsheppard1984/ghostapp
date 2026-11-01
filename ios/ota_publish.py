#!/usr/bin/env python3
"""Create a SideStore AltSource feed from a checked, unsigned SpiritLab IPA.

No Apple credentials or provisioning profiles are uploaded. The public repo
contains only the unsigned application and its update metadata.
"""
from __future__ import annotations
import datetime as dt
import json
import math
import plistlib
import struct
import sys
import zlib
from pathlib import Path
from zipfile import ZipFile

BASE_URL = (
    "https://raw.githubusercontent.com/ddsheppard1984/ghostapp/"
    "spiritlab-ios-updates/ota/"
)
BUNDLE_ID = "com.houseofsqueak.spiritlab"


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


def make_icon(path: Path) -> None:
    size = 128
    scanlines = bytearray()
    for y in range(size):
        scanlines.append(0)
        for x in range(size):
            bg = (12, 17, 32)
            head = ((x - 64) / 43) ** 2 + ((y - 53) / 38) ** 2 <= 1
            body = 25 <= x <= 103 and 49 <= y <= 106
            scallop = y > 93 and (y - 94) > 7 * (1 + math.sin((x - 25) * 0.27))
            ghost = (head or body) and not scallop
            eye = ((x - 49) ** 2 + (y - 53) ** 2 <= 28 or
                   (x - 79) ** 2 + (y - 53) ** 2 <= 28)
            color = (107, 234, 201) if ghost and not eye else bg
            scanlines.extend(color)
    raw = bytes(scanlines)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")
    )


def main(ipa_file: str, output_dir: str) -> None:
    ipa = Path(ipa_file)
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    with ZipFile(ipa) as archive:
        assert archive.testzip() is None, "IPA archive corrupted"
        data = plistlib.loads(archive.read("Payload/SpiritLab.app/Info.plist"))
    assert data["CFBundleIdentifier"] == BUNDLE_ID, "Unexpected bundle identifier"
    version = data.get("CFBundleShortVersionString")
    build = data.get("CFBundleVersion")
    assert version == "4.3.1" and str(build) == "431", (
        f"Unexpected version {version!r} / {build!r}"
    )
    (out / "SpiritLab.ipa").write_bytes(ipa.read_bytes())
    make_icon(out / "icon.png")
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    feed = {
        "name": "House of Squeak — SpiritLab",
        "identifier": "com.houseofsqueak.spiritlab.source",
        "sourceURL": BASE_URL + "source.json",
        "description": "Free iPhone updates for the SpiritLab native field investigation app.",
        "iconURL": BASE_URL + "icon.png",
        "tintColor": "6BEAC9",
        "apps": [{
            "name": "SpiritLab",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "House of Squeak",
            "subtitle": "Real-time field investigation tools",
            "localizedDescription": (
                "Private Lenovo-powered EVP, camera, LiDAR depth readings, "
                "body-pose estimates, motion sensors and virtual spirit box. "
                "Measurements are not proof of paranormal phenomena."
            ),
            "iconURL": BASE_URL + "icon.png",
            "category": "utilities",
            "versions": [{
                "version": version,
                "buildVersion": str(build),
                "date": now,
                "localizedDescription": "v4.3.1 improves free SideStore update delivery.",
                "downloadURL": BASE_URL + "SpiritLab.ipa",
                "size": ipa.stat().st_size,
                "minOSVersion": "17.0"
            }]
        }],
        "news": []
    }
    (out / "source.json").write_text(json.dumps(feed, indent=2) + "\n")
    assert json.loads((out / "source.json").read_text())["apps"][0]["versions"][0]["version"] == version
    print("SideStore source generated:", out / "source.json", "version", version)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: ota_publish.py IPA_FILE OUTPUT_DIRECTORY")
    main(sys.argv[1], sys.argv[2])
