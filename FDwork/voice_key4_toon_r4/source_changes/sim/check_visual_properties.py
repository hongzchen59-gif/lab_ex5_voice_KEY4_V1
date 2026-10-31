"""R4 separates non-darkening color fill from a thin structural ink mask."""
from pathlib import Path
import itertools,json,random
from natural_reference import process_image,color_fill,gray,quant_up
from toon_r3_reference import process_image as previous,natural_color as previous_color

for y in range(256):
    p=(y,)*3;q=color_fill(p)
    assert q==(quant_up(y),)*3 and gray(q)>=y
assert color_fill((255,)*3)==(255,)*3
assert color_fill((240,)*3)==(255,)*3
probes=[(127,129,127),(127,127,129),(180,60,60),(60,150,60),(50,80,180)]
records=[]
for p in probes:
    q=color_fill(p);assert gray(q)>=gray(p)
    if max(p)-min(p)<32:
        assert q[0]-q[1]==p[0]-p[1] and q[1]-q[2]==p[1]-p[2]
    records.append({'input':p,'R3_flat':previous_color(p,0),'R4_fill':q})
for p in itertools.product(range(0,256,17),repeat=3):
    q=color_fill(p);assert min(q)>=0 and max(q)<=255 and gray(q)>=gray(p)
    for a,b in itertools.combinations(range(3),2):
        assert (p[a]-p[b])*(q[a]-q[b])>=0

W,H=32,16
step=[[(64,)*3 if x<16 else (192,)*3 for x in range(W)] for _ in range(H)]
out=process_image(step,2)
black=[(x,y) for y in range(1,H-1) for x in range(1,W-1) if out[y][x]==(0,)*3]
assert black==[(16,y) for y in range(1,H-1)]
assert out[8][15]==(80,)*3 and out[8][17]==(208,)*3
white=process_image([[(255,)*3 for _ in range(W)] for _ in range(H)],2)
assert all(p==(255,)*3 for row in white for p in row)
ramp=[[(max(0,min(240,(x-8)*40)),)*3 for x in range(W)] for _ in range(H)]
out=process_image(ramp,2)
assert all(out[y][x]==(quant_up((x-8)*40),)*3 for y in range(1,H-1) for x in range(10,14))
boundary=[[(240,40,0) if x<16 else (0,40,240) for x in range(W)] for _ in range(H)]
out=process_image(boundary,2)
assert out[8][15]==(240,40,0) and out[8][16]==(0,40,240)
for mode in (0,1,3):assert process_image(boundary,mode)==previous(boundary,mode)
report={'scope':'synthetic post-gamma image properties; not hardware color calibration',
 'fill_non_darkening_sampled_RGB':4096,'all_neutral_gray_levels_non_darkening':True,
 'flat_white_stays_white':True,'gray240_fill':[255]*3,'color_probes':records,
 'near_neutral_channel_differences_preserved':True,'standard_step_ink_columns':[16],
 'standard_step_ink_pixels':len(black),'linear_shading_not_ink':True,
 'same_luma_color_boundary_no_bleed':True,'KEY1_KEY2_KEY4_pixel_identical':True,
 'outline_note':'Local one-sided structural test, not a full Canny/NMS algorithm; general scene line widths may vary.'}
Path(__file__).with_name('visual_properties.json').write_text(json.dumps(report,indent=2)+'\n')
print('VISUAL PASS: '+json.dumps(report))
