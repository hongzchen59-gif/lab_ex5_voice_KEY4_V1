from pathlib import Path
W,H=96,64;DW,DH=W//8,H//8
# Unique IDs, intentional repeats, global illumination, gap, paused axes, mode exit.
seq=[(1,2,False,3),(1,2,False,3),(2,3,False,3),(2,3,False,3),(3,4,False,3),(4,5,False,3),(5,5,False,3),(6,5,False,3),(7,5,False,3),(8,3,False,3),(9,2,False,3),(10,-1,False,3),(11,-1,False,3),(12,-1,False,3),(13,3,True,3),(14,3,False,3),(15,4,False,3),(17,5,False,3),(18,4,False,0),(19,3,False,3)]
prev=None;last=None;active=False;on=off=events=0;status=0;cells=0;bbox=0;frames=[];expected=[];cfg=[]
for sid,pos,pause,mode in seq:
 image=[]
 for y in range(H):
  for x in range(W):
   value=(200 if pos<0 else (144 if pos<=x//8<pos+4 and 2<=y//8<6 else 32))+((x*3+y*5)%7)-3
   image.append((value<<16)|(value<<8)|value)
 gray=[[0]*DW for _ in range(DH)]
 for by in range(DH):
  for bx in range(DW):
   total=0
   for y in range(by*8,by*8+8):
    for x in range(bx*8,bx*8+8):
     p=image[y*W+x];r=p>>16;g=(p>>8)&255;b=p&255;total+=(r+2*g+b+2)//4
   gray[by][bx]=(total+32)//64
 if mode!=3: prev=None;last=None;active=False;on=off=events=0;status=0;cells=bbox=0
 elif pause:prev=None;last=sid;active=False;on=off=0;status=4;cells=bbox=0
 elif sid!=last:
  warm=prev is None or last is None or sid!=(last+1)&0xffffffff
  mask=[[0 if warm else int(abs(gray[y][x]-prev[y][x])>=12) for x in range(DW)] for y in range(DH)]
  clean=[]
  for y in range(DH):
   for x in range(DW):
    votes=sum(mask[yy][xx] for yy in range(max(0,y-1),min(DH,y+2)) for xx in range(max(0,x-1),min(DW,x+2)))
    if mask[y][x] and votes>=3:clean.append((x,y))
  cells=len(clean);last=sid
  if sum(map(sum,mask))>=DW*DH*3//5:
   prev=None;active=False;on=off=0;status=5;bbox=0
  elif warm:
   prev=gray;active=False;on=off=0;status=2;cells=bbox=0
  else:
   prev=gray
   if cells>=2:
    off=0;x0=min(x for x,y in clean)*8;x1=max(x for x,y in clean)*8+7;y0=min(y for x,y in clean)*8;y1=max(y for x,y in clean)*8+7
    bbox=x0|(x1<<11)|(y0<<22)|(y1<<32)
    if active or on>=1:
     status=3;on=0
     if not active:events+=1
     active=True
    else:on+=1;status=2
   else:
    on=0
    if active and off<2:off+=1;status=3
    else:active=False;off=0;status=2;bbox=0
 frames.extend(image);expected.append((status<<72)|(events<<56)|(cells<<42)|bbox);cfg.append((sid<<8)|(pause<<2)|mode)
root=Path(__file__).resolve().parent
(root/'motion_pixels.hex').write_text('\n'.join(f'{p:06x}' for p in frames)+'\n')
(root/'motion_expected.hex').write_text('\n'.join(f'{p:020x}' for p in expected)+'\n')
(root/'motion_config.hex').write_text('\n'.join(f'{p:010x}' for p in cfg)+'\n')
print('MOTION independent reference:',len(seq),'frames;',W,H)
