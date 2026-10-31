"""Independent BFS oracle and integer geometric rules for detector verification."""
from collections import deque
from pathlib import Path
import json,random
W,H=320,180
def classify(r,g,b):
    if max(r,g,b)<48 or max(r,g,b)-min(r,g,b)<24:return 0
    if r>=g+16 and r>=b+16:return 1
    if g>=r+16 and g>=b+16:return 2
    if b>=r+16 and b>=g+16:return 3
    return 0
def shape(points,box):
    x0,y0,x1,y1=box;w=x1-x0+1;h=y1-y0+1;a=len(points)
    widths=[0]*h
    for x,y in points:widths[y-y0]+=1
    p0,p1,p2,p3,p4=[widths[(h-1)*t//8] for t in (1,2,4,6,7)]
    ry=sum(y-y0 for x,y in points);ah=a*(h-1);area100=a*100;ba=w*h
    centered=3*ah<=10*ry<=7*ah
    symmetric=abs(p0-p4)<=w//5+2 and abs(p1-p3)<=w//5+2
    rising=p0<=p1+2 and p1<=p2+2 and p2<=p3+2 and p3<=p4+2 and p4>=p0+w//2 and p0*3<=w+3 and p4*3>=w*2 and ry*2>=ah
    falling=p4<=p3+2 and p3<=p2+2 and p2<=p1+2 and p1<=p0+2 and p0>=p4+w//2 and p4*3<=w+3 and p0*3>=w*2 and ry*2<=ah
    if area100>=88*ba and centered and all(v*4>=w*3 for v in (p0,p1,p2,p3,p4)):return 3
    if 64*ba<=area100<=87*ba and w*4>=h*3 and h*4>=w*3 and centered and symmetric and p2*5>=w*4 and p0*5>=w*2 and p4*5>=w*2 and p0*10<=w*9 and p4*10<=w*9 and p1*3>=w*2 and p3*3>=w*2:return 1
    if 35*ba<=area100<=65*ba and (rising or falling) and w<=p2*4<=3*w:return 2
    return 0
def bcd(v):return int(f'{v:04d}',16)
def regions(mask):
    seen=set();out=[]
    for y in range(H):
        for x in range(W):
            color=mask[y][x]
            if not color or (x,y) in seen:continue
            q=deque([(x,y)]);seen.add((x,y));pts=[]
            while q:
                xx,yy=q.popleft();pts.append((xx,yy))
                for dy in (-1,0,1):
                    for dx in (-1,0,1):
                        nx,ny=xx+dx,yy+dy
                        if 0<=nx<W and 0<=ny<H and (nx,ny) not in seen and mask[ny][nx]==color:
                            seen.add((nx,ny));q.append((nx,ny))
            x0=min(p[0] for p in pts);x1=max(p[0] for p in pts);y0=min(p[1] for p in pts);y1=max(p[1] for p in pts)
            w=x1-x0+1;h=y1-y0+1
            if len(pts)<96 or min(w,h)<16 or max(w,h)>4*min(w,h) or x0==0 or y0==0 or x1==W-1 or y1==H-1:continue
            sh=shape(pts,(x0,y0,x1,y1));bx0=x0*4;bx1=x1*4+3;by0=y0*4;by1=y1*4+3
            record=bx0|(bx1<<11)|(by0<<22)|(by1<<32)|(color<<42)|(sh<<44)|(bcd((bx0+bx1)//2)<<46)|(bcd((by0+by1)//2)<<62)
            out.append(dict(area=len(pts),color=color,shape=sh,box=[x0,y0,x1,y1],record=record))
    return out
def blank():return [[0]*W for _ in range(H)]
def draw(m,x0,y0,w,h,color,kind):
    for y in range(h):
        for x in range(w):
            yes=kind=='rect' or (kind=='circle' and (2*x-w+1)**2*h*h+(2*y-h+1)**2*w*w<=w*w*h*h)
            if kind in ('triangle','down'):
                width=(y+1)*w//h if kind=='triangle' else (h-y)*w//h
                yes=(w-width)//2<=x<(w-width)//2+width
            if yes and 0<=x+x0<W and 0<=y+y0<H:m[y+y0][x+x0]=color
def generate():
    cases=[]
    for col in (1,2,3):
        for kind in ('circle','triangle','rect','down'):
            m=blank();draw(m,24+col*8,20,40,40,col,kind);cases.append((f'{col}_{kind}',m,1))
    m=blank();draw(m,20,20,40,40,1,'circle');draw(m,90,30,40,40,1,'triangle');draw(m,180,50,40,32,3,'rect');draw(m,250,90,36,36,2,'circle');cases.append(('four_same_color_separation',m,1))
    m=blank()
    # Two stems joining late: incorrect union handling would count this twice.
    for y in range(25,70):
        for x in range(30,70):
            if x<40 or x>=60 or y>=60:m[y][x]=1
    cases.append(('late_U_merge_unknown',m,1))
    m=blank();draw(m,25,20,24,24,1,'rect');draw(m,49,44,24,24,1,'rect');cases.append(('diagonal_eight_connected',m,1))
    m=blank();draw(m,30,30,32,32,1,'rect');draw(m,62,30,32,32,2,'rect');cases.append(('different_colors_touch',m,1))
    m=blank();draw(m,0,10,40,40,3,'rect');draw(m,90,30,8,8,1,'rect');cases.append(('border_and_tiny_rejected',m,1))
    m=blank()
    for i in range(6):draw(m,12+i*48,20,24+i*2,24+i*2,(i%3)+1,'rect')
    cases.append(('count_more_than_four',m,1))
    cases.append(('empty_clears_old',blank(),1))
    m=blank()
    for i in range(64):m[20][i*2+10]=1
    cases.append(('run_capacity_exact',m,1))
    m=blank()
    for i in range(65):m[20][i*2+10]=1
    cases.append(('run_capacity',m,2))
    m=blank()
    for i in range(129):m[4+(i//50)*4][4+(i%50)*5]=1
    cases.append(('label_capacity',m,2))
    m=blank()
    for i in range(128):m[4+(i//50)*4][4+(i%50)*5]=1
    cases.append(('label_capacity_exact',m,1))
    m=blank()
    for y in range(25,81):
        for x in range(20,77):
            if y>=70 or (x-20)%4<2:m[y][x]=2
    cases.append(('many_stems_late_union',m,1))
    rng=random.Random(20261017)
    for i in range(4):
        m=blank()
        for j in range(4):draw(m,12+74*j,15+rng.randrange(55),24+rng.randrange(18),32,(j+i)%3+1,('rect','circle','triangle','down')[(j+i)%4])
        cases.append((f'mixed_{i}',m,1))
    for i in range(8):
        m=blank()
        for y in range(16):
            for x in range(16):
                if rng.random()<0.69:m[y+60][x+100]=3
        cases.append((f'random_branching_{i}',m,1))
    here=Path(__file__).parent
    all_masks=[];expected=[];report=[]
    for name,m,status in cases:
        found=regions(m) if status==1 else []
        chosen=sorted(found,key=lambda d:d['area'],reverse=True)[:4]
        # Ties are accepted separately by area only; fixtures use unique cutoff.
        records=[d['record'] for d in chosen]+[0]*(4-len(chosen))
        expected.append((status<<323)|(min(5,len(found))<<320)|sum(v<<(80*i) for i,v in enumerate(records)))
        all_masks.extend(f'{v:x}\n' for row in m for v in row)
        report.append(dict(name=name,status=status,count=len(found),objects=[{**d,'record':f'{d["record"]:020x}'} for d in chosen]))
        if name.endswith('_circle'):assert chosen[0]['shape']==1
        if name.endswith('_triangle') or name.endswith('_down'):assert chosen[0]['shape']==2
        if name.endswith('_rect'):assert chosen[0]['shape']==3
    (here/'detect_masks.hex').write_text(''.join(all_masks))
    (here/'detect_expected.hex').write_text(''.join(f'{v:082x}\n' for v in expected))
    (here/'detect_cases.vh').write_text(f'localparam CASES={len(cases)};\n')
    (here/'detect_reference.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'DETECT REFERENCE PASS: {len(cases)} BFS fixtures; all 12 color/shape combinations classified')
if __name__=='__main__':generate()
