"""Merge raw FPGA configuration and the TCM reset shim; no hardware access."""
import json
from pathlib import Path
import zlib

root = Path(__file__).resolve().parent
offset = 0x00E00000
fpga = (root / "voice_toon_r4_fpga.bin").read_bytes()
bit = (root / "voice_toon_r4.bit").read_bytes()
boot = (root / "voice_boot.bin").read_bytes()
payload = (root / "app_payload.bin").read_bytes()
assert fpga and len(fpga) < offset
assert bit.endswith(fpga), "Raw FPGA data differs from the fresh TOON_R4 bitstream"
assert boot.endswith(payload), "Boot payload differs from the captured TCM program"
assert offset + len(boot) <= 16 * 1024 * 1024
image = fpga + b"\xff" * (offset - len(fpga)) + boot
dest = root / "voice_toon_r4_flash.bin"
dest.write_bytes(image)
actual = dest.read_bytes()
assert actual[:len(fpga)] == fpga
assert actual[len(fpga):offset] == b"\xff" * (offset - len(fpga))
assert actual[offset:] == boot
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest.update(fpga_raw_bytes=len(fpga), fpga_crc32=f"{zlib.crc32(fpga):08x}",
                fpga_matches_built_bit=True, merged_file=dest.name,
                merged_bytes=len(image), merged_crc32=f"{zlib.crc32(image):08x}",
                flash_required_bytes=16 * 1024 * 1024,
                flash_tool_start_address="0x00000000",
                simulator_note="Vendor GDB simulator stopped with SIGILL; no full reset/QSPI simulation pass claimed")
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"STANDALONE_MERGE_LAYOUT_PASS file={dest} bytes={len(image)} crc32={zlib.crc32(image):08x}")
