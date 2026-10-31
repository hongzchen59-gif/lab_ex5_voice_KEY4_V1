"""Render the real integer model, not an AI-generated or measured-board result."""
from pathlib import Path
import sys
from PIL import Image,ImageDraw
from natural_reference import process_image
from toon_r3_reference import process_image as r3
source=Path(sys.argv[1]);output=Path(sys.argv[2]);output.mkdir(parents=True,exist_ok=True)
slide=Image.open(source).convert('RGB')
assert slide.size==(1048,687),slide.size
image=slide.crop((256,387,468,558))
data=list(image.getdata());rows=[data[y*image.width:(y+1)*image.width] for y in range(image.height)]
variants=[image]
for fn in (r3,process_image):
    pixels=fn(rows,2);im=Image.new('RGB',image.size);im.putdata([p for row in pixels for p in row]);variants.append(im)
panel=Image.new('RGB',(3*424,342+58),(28,28,28));draw=ImageDraw.Draw(panel)
for i,(im,label) in enumerate(zip(variants,['Input (slide thumbnail)','TOON_R3','TOON_R4 integer model'])):
    panel.paste(im.resize((424,342),Image.Resampling.NEAREST),(i*424,28));draw.text((i*424+8,8),label,fill='white')
draw.text((8,378),'Software preview from a slide thumbnail; not real-board capture or camera color calibration.',fill='white')
panel.save(output/'key3_comparison.png');image.save(output/'preview_input.png')
print('KEY3_MODEL_PREVIEW '+str(output/'key3_comparison.png'))
