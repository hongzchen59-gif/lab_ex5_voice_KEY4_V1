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
            colors = [max(abs(a-b) for a,b in zip(p,taps[4])) for p in taps]
            weights = [s*(2 if d<=12 and k<=24 else 1 if d<=32 and k<=48 else 0)
                       for s,d,k in zip(SPATIAL,diffs,colors)]
            denom = sum(weights)
            assert 8 <= denom <= 32
            sums = [sum(p[c]*a for p, a in zip(taps, weights)) for c in range(3)]
            result[y][x] = tuple((2*n+denom)//(2*denom) for n in sums)
    return result


def quant_up(y):
    return y if y<16 else min(255,(y//16+1)*16)


def candidate_chroma(p):
    y=gray(p)
    return tuple(c+(c-y)//8 for c in p) if 32<=y<=208 and max(p)-min(p)>=32 else p


def color_fill(p):
    y=gray(p);target=quant_up(y)
    if min(p)<=8 and max(p)>=224:
        return p  # Already saturated bright colors keep their original hue.
    candidate=candidate_chroma(p)
    lift=target-gray(candidate)
    if min(candidate)>=0 and max(candidate)<=255 and lift>=0 and max(candidate)+lift<=255:
        return tuple(c+lift for c in candidate)
    lift=min(target-y,255-max(p))
    return tuple(c+lift for c in p)


def edge_ink(taps,luma,gx,gy):
    if abs(gx)+abs(gy)<256:return False
    if abs(gx)>2*abs(gy):a,b=3,5
    elif abs(gy)>2*abs(gx):a,b=1,7
    elif (gx<0)==(gy<0):a,b=2,6
    else:a,b=0,8
    return 2*luma[4]>luma[a]+luma[b]+16


def natural_color(p,magnitude):
    # Numeric fill API: ink needs the actual neighborhood, not magnitude alone.
    return color_fill(p)


def process_image(img, mode):
    h, w = len(img), len(img[0])
    source = preserve_image(img) if mode==2 else img
    output = [row[:] for row in source]
    for y in range(h):
        for x in range(w):
            if mode in (0,3):
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
                output[y][x] = (0,0,0) if edge_ink(taps,luma,gx,gy) else color_fill(source[y][x])
            else:
                blur = [sum(p[c]*k for p, k in zip(taps, SPATIAL))//16 for c in range(3)]
                output[y][x] = tuple(clamp(GAMMA85[v]+(v-b)//2) for v, b in zip(source[y][x], blur))
    return output
