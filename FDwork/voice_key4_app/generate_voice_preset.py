"""Build the FPGA work-RAM initialization image from a verified board export."""
import argparse
import json
from pathlib import Path
import struct
import zlib

HEADER_OFFSET = 0xbc00
RAM_BYTES = 49152
MAGIC = 0x5654504c


def build(manifest_path):
    meta = json.loads(manifest_path.read_text(encoding='utf-8'))
    data = (manifest_path.parent / meta['binary']).read_bytes()
    if meta['format'] != 'voice-templates-v1' or meta['validation_errors']:
        raise ValueError('Only a validated board export is accepted')
    if len(data) != 31200 or f'{zlib.crc32(data) & 0xffffffff:08x}' != meta['crc32_binary']:
        raise ValueError('Template export length/CRC mismatch')
    if meta['sample_rate'] != 15625 or meta['dimensions'] != 13 or meta['slot_bytes'] != 7800:
        raise ValueError('Incompatible feature format')
    frames = []
    for i, entry in enumerate(meta['templates']):
        n = entry['frames']
        if entry['class'] != i + 1 or not 20 <= n <= 300:
            raise ValueError('Invalid class metadata')
        active = data[i * 7800:i * 7800 + n * 26]
        if f'{zlib.crc32(active) & 0xffffffff:08x}' != entry['crc32_active']:
            raise ValueError('Active template CRC mismatch')
        frames.append(n)
    if len(frames) != 4 or not meta['threshold']:
        raise ValueError('Four templates and a nonzero rejection threshold are required')
    header = [MAGIC, 1, 15625, 13, 7800, *frames, meta['threshold'], meta['margin'],
              zlib.crc32(data) & 0xffffffff, len(data), 0, 0]
    header.append(zlib.crc32(struct.pack('<15I', *header)) & 0xffffffff)
    ram = bytearray(RAM_BYTES)
    ram[:len(data)] = data
    ram[HEADER_OFFSET:HEADER_OFFSET + 64] = struct.pack('<16I', *header)
    return bytes(ram), header


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    ram, header = build(a.manifest)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(''.join(f'{w:08x}\n' for w in struct.unpack('<12288I', ram)), encoding='ascii')
    check = b''.join(struct.pack('<I', int(w, 16)) for w in a.output.read_text().split())
    if check != ram:
        raise RuntimeError('Initialization file readback mismatch')
    print(f'PRESET_IMAGE_PASS frames={header[5:9]} payload_crc={header[11]:08x} header_crc={header[15]:08x}')


if __name__ == '__main__':
    main()
