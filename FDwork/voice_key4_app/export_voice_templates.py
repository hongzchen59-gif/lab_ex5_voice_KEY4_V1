"""Read enrolled templates via the existing OpenOCD Tcl server, using 32-bit reads.

Does not load firmware, write target memory or modify axis controls. If a running
CPU must be halted, its running state is restored in finally before files save.
"""
import argparse
import json
from pathlib import Path
import re
import socket
import struct
import subprocess
import zlib
from datetime import datetime

APP = Path(__file__).resolve().parent
NM = Path('D:/Anlogic/FD/toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-nm.exe')
WORDS_PER_SLOT = 1950
BASE = 0x80010000
NAMES = ['追踪红色圆形', '追踪蓝色方形', '停止追踪', '云台回中']


class Tcl:
    def __init__(self):
        self.s = socket.create_connection(('127.0.0.1', 6666), timeout=8)
        self.s.settimeout(20)

    def command(self, command):
        self.s.sendall(command.encode('ascii') + b'\x1a')
        data = bytearray()
        while not data.endswith(b'\x1a'):
            part = self.s.recv(65536)
            if not part:
                raise RuntimeError('OpenOCD Tcl connection closed')
            data.extend(part)
        return data[:-1].decode('utf-8', errors='replace').strip()

    def words(self, address, count):
        if address % 4:
            raise ValueError('Only aligned 32-bit target reads are permitted')
        reply = self.command(f'read_memory 0x{address:08x} 32 {count}')
        try:
            values = [int(v, 0) & 0xffffffff for v in reply.split()]
            if len(values) == count:
                return values
        except ValueError:
            pass
        reply = self.command(f'capture {{mdw 0x{address:08x} {count}}}')
        values = []
        for line in reply.splitlines():
            match = re.match(r'^\s*(?:0x)?([0-9a-fA-F]{8}):\s*(.*)$', line)
            if match:
                if int(match[1], 16) != address + 4 * len(values):
                    raise RuntimeError('Non-contiguous memory readback')
                values.extend(int(v, 16) for v in match[2].split())
        if len(values) != count:
            raise RuntimeError(f'32-bit read failed at 0x{address:08x}: {reply[:160]}')
        return values

    def close(self):
        self.s.close()


def symbol_addresses(elf):
    result = subprocess.run([str(NM), '-a', '-S', str(elf)], check=True,
                            capture_output=True, text=True)
    symbols = {}
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[-1] in ('lengths', 'threshold', 'margin'):
            symbols[fields[-1]] = int(fields[0], 16)
    if len(symbols) != 3:
        raise RuntimeError('Template metadata symbols not found in the current ELF')
    return symbols


def capture(elf, expected):
    symbols = symbol_addresses(elf)
    client = Tcl()
    was_running = False
    try:
        state = client.command('riscv0.cpu curstate')
        if state not in ('running', 'halted'):
            raise RuntimeError(f'Unexpected target state: {state}')
        was_running = state == 'running'
        if was_running:
            client.command('halt 1000')
        if client.command('riscv0.cpu curstate') != 'halted':
            raise RuntimeError('Could not confirm halted state')
        flags = client.words(0x8000000c, 1)[0]
        if flags & 2:
            raise RuntimeError('Recording is active; export postponed')
        control = client.words(0x80000030, 1)[0]
        if control & 3:
            raise RuntimeError('Axes are enabled; send d before exporting')
        identity = client.words(0x80000000, 1)[0]
        if identity != 0x564f4937:
            raise RuntimeError(f'Expected R5/VOI7, read 0x{identity:08x}')
        length_words = client.words(symbols['lengths'], 2)
        lengths = list(struct.unpack('<4H', struct.pack('<2I', *length_words)))
        if lengths != expected:
            raise RuntimeError(f'Live lengths {lengths} differ from supplied log {expected}')
        if not all(20 <= n <= 300 for n in lengths):
            raise RuntimeError(f'Invalid lengths: {lengths}')
        threshold = client.words(symbols['threshold'], 1)[0]
        margin = client.words(symbols['margin'], 1)[0]
        print(f'CAPTURE_BEGIN lengths={lengths} threshold={threshold} margin={margin}', flush=True)
        raw = bytearray()
        for slot in range(4):
            for offset in range(0, WORDS_PER_SLOT, 128):
                words = client.words(BASE + slot * 7800 + offset * 4,
                                     min(128, WORDS_PER_SLOT - offset))
                raw.extend(struct.pack(f'<{len(words)}I', *words))
            print(f'CAPTURED class={slot + 1} frames={lengths[slot]} bytes=7800', flush=True)
        again = client.words(symbols['lengths'], 2)
        if again != length_words:
            raise RuntimeError('Metadata changed during export')
        return bytes(raw), lengths, threshold, margin, symbols
    finally:
        try:
            if was_running:
                try:
                    client.command('resume')
                    restored = client.command('riscv0.cpu curstate')
                except (OSError, RuntimeError):
                    client.close()
                    client = Tcl()
                    client.command('resume')
                    restored = client.command('riscv0.cpu curstate')
                if restored != 'running':
                    raise RuntimeError(f'CPU_RESUME_FAILED state={restored}; Resume in FD')
                print('CPU_STATE_RESTORED=running', flush=True)
            else:
                print('CPU_STATE_PRESERVED=halted', flush=True)
        finally:
            client.close()


def save(output, raw, lengths, threshold, margin, symbols, elf, record_log):
    entries = []
    errors = []
    for slot, frames in enumerate(lengths):
        active = raw[slot * 7800:slot * 7800 + frames * 26]
        values = struct.unpack(f'<{len(active) // 2}h', active)
        sums = [sum(values[d::13]) for d in range(13)]
        if not any(values) or any(abs(v) >= frames for v in sums):
            errors.append(f'class {slot + 1}: feature data not consistent with CMN')
        entries.append({'class': slot + 1, 'phrase': NAMES[slot], 'frames': frames,
                        'slot_offset_bytes': slot * 7800, 'active_bytes': len(active),
                        'crc32_active': f'{zlib.crc32(active) & 0xffffffff:08x}',
                        'min': min(values), 'max': max(values), 'cmn_sums': sums})
    output.mkdir(parents=True, exist_ok=False)
    binary = output / 'templates_ram.bin'
    binary.write_bytes(raw)
    if binary.read_bytes() != raw:
        raise RuntimeError('Host file readback mismatch')
    manifest = {'format': 'voice-templates-v1', 'captured_local_time': datetime.now().isoformat(),
                'fabric_id': '564f4937', 'sample_rate': 15625, 'dimensions': 13,
                'dtype': 'int16-le', 'normalization': 'per-utterance CMN',
                'slot_bytes': 7800, 'threshold': threshold, 'margin': margin,
                'binary': binary.name, 'bytes': len(raw),
                'crc32_binary': f'{zlib.crc32(raw) & 0xffffffff:08x}',
                'source_elf': str(elf), 'symbol_addresses': symbols,
                'source_log': str(record_log), 'templates': entries, 'validation_errors': errors}
    (output / 'templates.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    if record_log:
        (output / record_log.name).write_bytes(record_log.read_bytes())
    print(f'SAVED {output} bytes={len(raw)} validation_errors={len(errors)}', flush=True)
    if errors:
        raise RuntimeError('Raw data preserved, but validation failed: ' + '; '.join(errors))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--elf', type=Path, required=True, help='ELF matching the recording firmware currently running on the board')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--expected-lengths', default='131,134,84,106')
    p.add_argument('--record-log', type=Path)
    a = p.parse_args()
    if a.output.exists():
        raise RuntimeError('Output already exists; existing template exports are never overwritten')
    expected = [int(x) for x in a.expected_lengths.split(',')]
    raw, lengths, threshold, margin, symbols = capture(a.elf, expected)
    save(a.output, raw, lengths, threshold, margin, symbols, a.elf, a.record_log)


if __name__ == '__main__':
    main()
