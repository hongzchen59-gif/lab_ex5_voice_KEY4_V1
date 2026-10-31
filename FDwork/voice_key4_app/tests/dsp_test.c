#include "../voice_dsp.h"
#include <limits.h>
volatile unsigned test_result;
volatile unsigned test_checks;
#define CHECK(condition, code) do { if (!(condition)) {test_result=(code);return;} ++test_checks; } while(0)
void test_main(void) {
    /* FD's instruction simulator lacks C/F support: run integer DTW/CMN
       from the production source; MFCC golden selfcheck runs on the board. */
    volatile uint32_t *ram=(volatile uint32_t *)(uintptr_t)0x80010000u;
    for(unsigned i=0;i<49152/4;i++)ram[i]=0;
    ram[39000/4]=0x13579bdf;
    voice_feature_put(0,0,-32768);voice_feature_put(0,1,32767);
    CHECK(voice_feature_get(0,0)==-32768 && voice_feature_get(0,1)==32767, 2);
    voice_feature_put(0,1,-3);
    CHECK(voice_feature_get(0,0)==-32768 && voice_feature_get(0,1)==-3, 3);
    for(unsigned i=0;i<40;i++)for(unsigned d=0;d<VOICE_DIM;d++) {
        int16_t value=(int16_t)((i/2)*10+d);
        voice_feature_put(0,i*VOICE_DIM+d,value);
        voice_feature_put(1,i*VOICE_DIM+d,value);
        voice_feature_put(2,i*VOICE_DIM+d,value+100);
    }
    CHECK(voice_distance(0,40,1,40)==0, 4);
    CHECK(voice_distance(0,40,2,40)>100, 5);
    for(unsigned i=0;i<80;i++)for(unsigned d=0;d<VOICE_DIM;d++)
        voice_feature_put(3,i*VOICE_DIM+d,(int16_t)((i/4)*10+d));
    CHECK(voice_distance(0,40,3,80)==0, 6);
    CHECK(voice_distance(0,0,1,40)==0x3fffffffu, 7);
    CHECK(voice_distance(0,301,1,40)==0x3fffffffu, 8);
    CHECK(voice_distance(0,19,3,80)==0x3fffffffu, 9);
    voice_normalize(0,40);voice_normalize(2,40);
    CHECK(voice_distance(0,40,2,40)==0, 10);
    /* Last packed halfword of the last feature slot and adjacent guard. */
    voice_feature_put(4,VOICE_SLOT_SAMPLES-1,INT16_MIN);
    CHECK(voice_feature_get(4,VOICE_SLOT_SAMPLES-1)==INT16_MIN && ram[39000/4]==0x13579bdf, 11);
    test_result=0x50415353;
}
