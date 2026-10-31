#ifndef VOICE_DSP_H
#define VOICE_DSP_H
#include <stdint.h>
#define VOICE_RATE 15625
#define VOICE_FRAME 400
#define VOICE_HOP 160
#define VOICE_DIM 13
#define VOICE_MAX_FRAMES 300
#define VOICE_SLOT_SAMPLES (VOICE_MAX_FRAMES*VOICE_DIM)
// Each slot is 7800 bytes, padded to a word boundary. Slots 0..3 templates,
// slot 4 query. No 8/16-bit CPU bus accesses are emitted for Fabric RAM.
void voice_features(const int16_t *samples,int16_t output[VOICE_DIM]);
int16_t voice_feature_get(unsigned slot,unsigned index);
void voice_feature_put(unsigned slot,unsigned index,int16_t value);
void voice_normalize(unsigned slot,unsigned frames);
uint32_t voice_distance(unsigned query,unsigned n,unsigned reference,unsigned m);
int voice_dsp_selfcheck(void);
#endif
