"""Independent integer image reference for the streaming RTL regression."""
from pathlib import Path
import random
from natural_reference import process_image

HERE = Path(__file__).resolve().parent
W, H, HT, VT = 16, 8, 24, 13
FRAMES = 56
GAMMA = [round(255 * (i / 255) ** 0.85) for i in range(256)]


def image(frame):
    rng = random.Random(20261016 + frame//4)
    pattern = frame // 4
    def pixel(x, y):
        if pattern == 0:
            return (40, 100, 180)
        if pattern == 1:
            return (255, 255, 255) if x >= W // 2 else (0, 0, 0)
        if pattern == 2:
            return (255, 0, 90) if y >= H // 2 else (0, 255, 200)
        if pattern == 3:
            return (255, 255, 255) if (x, y) == (8, 4) else (8, 8, 8)
        if pattern == 4:
            return (x * 17, y * 36, (x * 13 + y * 23) % 256)
        if pattern == 5:
            return tuple(rng.randrange(256) for _ in range(3))
        if pattern == 6:
            return (min(255,90+8*x),60+5*x+2*y,45+3*x+2*y)
        if pattern == 7:
            v=96+rng.randrange(-12,13)
            return (v,v,v)
        if pattern == 8:
            return (240,40,0) if x<W//2 else (0,40,240)
        if pattern == 9:
            return (0,0,0)
        if pattern == 10:
            return (255,255,255)
        if pattern == 11:
            return (8,8,8)
        if pattern == 12:
            return (x*17,x*17,x*17)
        return (255,250,4) if (x+y)%4==0 else (4,250,255)
    return [[pixel(x, y) for x in range(W)] for y in range(H)]


def pack(rgb, mode, de, sof, eol, hs, vs):
    r, g, b = rgb
    return (mode << 29) | (eol << 28) | (sof << 27) | (de << 26) | (hs << 25) | (vs << 24) | (r << 16) | (g << 8) | b


def main():
    count = 0
    with (HERE / 'input.hex').open('w') as inp, (HERE / 'expected.hex').open('w') as exp:
        for frame in range(FRAMES):
            img = image(frame)
            mode = frame % 4
            processed = process_image(img,mode)
            for y in range(VT):
                for x in range(HT):
                    de = x < W and y < H
                    args = (mode, int(de), int(de and x == 0 and y == 0), int(de and x == W-1), int(19 <= x < 21), int(10 <= y < 12))
                    raw = img[y][x] if de else (0, 0, 0)
                    result = processed[y][x] if de else (0, 0, 0)
                    inp.write(f'{pack(raw, *args):08x}\n')
                    exp.write(f'{pack(result, *args):08x}\n')
                    count += 1
    print(f'Generated {count} raster clocks: 56 frames, fourteen scenes, four modes.')


if __name__ == '__main__':
    main()

# Base gamma independent numeric reference.
from pathlib import Path
Path(__file__).with_name("gamma80.hex").write_text("\n".join(f"{round(255*(i/255)**0.80):02x}" for i in range(256))+"\n")

# Independent address-indexed reference for logo pipeline alignment.
import re
root=Path(__file__).resolve().parents[1]
logo=[0]*25600
for a,v in re.findall(r"15'd(\d+): O_pixel = 25'h([0-9a-fA-F]+);",(root/'user_source/hdl_source/anlogic_logo_rom.v').read_text()):
 if int(a)<len(logo):logo[int(a)]=int(v,16)
Path(__file__).with_name('logo_reference.hex').write_text('\n'.join(f'{v:07x}' for v in logo)+'\n')
