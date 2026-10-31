"""Independent image-domain reference: exact divisions, no RTL reciprocal LUT."""
SPATIAL = (1, 2, 1, 2, 4, 2, 1, 2, 1)
GAMMA85 = [round(255*(i/255)**0.85) for i in range(256)]


def clamp(v):
    return max(0, min(255, v))


def gray(p):
    return (p[0] + 2*p[1] + p[2]) // 4


def interior(x, y, w, h):
    return 0 < x < w-1 and 0 < y < h-1


def neighborhood(img, x, y):
    return [img[y+dy][x+dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)]


def preserve_image(img):
    h, w = len(img), len(img[0])
    result = [row[:] for row in img]
    for y in range(1, h-1):
        for x in range(1, w-1):
            taps = neighborhood(img, x, y)
            center = gray(img[y][x])
            diffs = [abs(gray(p)-center) for p in taps]
            weights = [s*(2 if d<=8 else 1 if d<=24 else 0) for s, d in zip(SPATIAL, diffs)]
            denom = sum(weights)
            assert 8 <= denom <= 32
            sums = [sum(p[c]*a for p, a in zip(taps, weights)) for c in range(3)]
            result[y][x] = tuple((2*n+denom)//(2*denom) for n in sums)
    return result


def natural_color(p, magnitude):
    y = gray(p)
    delta = (((y+8)//17)*17-y)//2
    toned = tuple(clamp(v+delta) for v in p)
    y = gray(toned)
    colored = toned if y>=224 else tuple(clamp(v+(v-y)//8) for v in toned)
    alpha = 0 if magnitude<96 else 1 if magnitude<160 else 2 if magnitude<224 else 3
    return tuple(v*(8-alpha)//8 for v in colored)


def process_image(img, mode):
    h, w = len(img), len(img[0])
    source = preserve_image(img) if mode==2 else img
    output = [row[:] for row in source]
    for y in range(h):
        for x in range(w):
            if mode==0:
                continue
            if not interior(x, y, w, h):
                output[y][x] = (0, 0, 0) if mode==1 else source[y][x]
                continue
            taps = neighborhood(source, x, y)
            luma = [gray(p) for p in taps]
            gx = sum(a*b for a, b in zip(luma, (-1, 0, 1, -2, 0, 2, -1, 0, 1)))
            gy = sum(a*b for a, b in zip(luma, (1, 2, 1, 0, 0, 0, -1, -2, -1)))
            mag = abs(gx)+abs(gy)
            if mode==1:
                output[y][x] = (255, 255, 255) if mag>=80 else (0, 0, 0)
            elif mode==2:
                output[y][x] = natural_color(source[y][x], mag)
            else:
                blur = [sum(p[c]*k for p, k in zip(taps, SPATIAL))//16 for c in range(3)]
                output[y][x] = tuple(clamp(GAMMA85[v]+(v-b)//2) for v, b in zip(source[y][x], blur))
    return output
