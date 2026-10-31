#include "voice_dsp.h"
#include <math.h>
#include <limits.h>
#include "voice_tables.h"

static union {
    struct {float re[512],im[512];} fft;
    uint32_t rows[2][VOICE_MAX_FRAMES+1];
} scratch;
static float mel[26];

static volatile uint32_t *feature_word(unsigned slot,unsigned index) {
    return (volatile uint32_t *)(uintptr_t)(0x80010000u+slot*7800u+(index/2u)*4u);
}
int16_t voice_feature_get(unsigned slot,unsigned index) {
    uint32_t word=*feature_word(slot,index);
    return (int16_t)(word>>((index&1u)*16u));
}
void voice_feature_put(unsigned slot,unsigned index,int16_t value) {
    volatile uint32_t *p=feature_word(slot,index);
    unsigned shift=(index&1u)*16u;
    uint32_t mask=0xffffu<<shift;
    // The allocated slot is initialized explicitly before feature extraction.
    *p=(*p&~mask)|((uint32_t)(uint16_t)value<<shift);
}
void voice_features(const int16_t *samples,int16_t output[VOICE_DIM]) {
    float *re=scratch.fft.re,*im=scratch.fft.im;
    for(unsigned i=0;i<512;i++) {
        re[i]=i<400?((float)samples[i]-(i?0.97f*samples[i-1]:0.0f))*voice_window[i]/32768.0f:0.0f;
        im[i]=0;
    }
    for(unsigned i=1,j=0;i<512;i++) {
        unsigned bit=256;
        for(;j&bit;bit>>=1)j^=bit;
        j^=bit;
        if(i<j){float t=re[i];re[i]=re[j];re[j]=t;}
    }
    for(unsigned len=2;len<=512;len<<=1) {
        unsigned half=len/2,step=512/len;
        for(unsigned base=0;base<512;base+=len)for(unsigned j=0;j<half;j++) {
            float wr=voice_twiddle[j*step][0],wi=voice_twiddle[j*step][1];
            unsigned a=base+j,b=a+half;
            float tr=wr*re[b]-wi*im[b],ti=wr*im[b]+wi*re[b];
            re[b]=re[a]-tr;im[b]=im[a]-ti;re[a]+=tr;im[a]+=ti;
        }
    }
    for(unsigned k=0;k<26;k++) {
        unsigned lo=voice_mel_bins[k],mid=voice_mel_bins[k+1],hi=voice_mel_bins[k+2];
        float power=0;
        for(unsigned j=lo;j<mid;j++)power+=(re[j]*re[j]+im[j]*im[j])*(float)(j-lo)/(float)(mid-lo);
        for(unsigned j=mid;j<hi;j++)power+=(re[j]*re[j]+im[j]*im[j])*(float)(hi-j)/(float)(hi-mid);
        mel[k]=logf(power>1e-9f?power:1e-9f);
    }
    // Exclude energy coefficient C0; use orthonormal DCT coefficients C1..C13.
    for(unsigned d=0;d<VOICE_DIM;d++) {
        float x=0;
        for(unsigned k=0;k<26;k++)x+=mel[k]*voice_dct[d][k];
        x*=64;
        if(x>32767)x=32767;
        if(x<-32768)x=-32768;
        output[d]=(int16_t)(x>=0?x+0.5f:x-0.5f);
    }
}
void voice_normalize(unsigned slot,unsigned frames) {
    if(!frames)return;
    for(unsigned d=0;d<VOICE_DIM;d++) {
        int32_t sum=0;
        for(unsigned i=0;i<frames;i++)sum+=voice_feature_get(slot,i*VOICE_DIM+d);
        int32_t mean=sum/(int32_t)frames;
        for(unsigned i=0;i<frames;i++) {
            int32_t x=voice_feature_get(slot,i*VOICE_DIM+d)-mean;
            if(x>32767)x=32767;
            if(x<-32768)x=-32768;
            voice_feature_put(slot,i*VOICE_DIM+d,(int16_t)x);
        }
    }
}
uint32_t voice_distance(unsigned query,unsigned n,unsigned reference,unsigned m) {
    const uint32_t infinity=0x3fffffffu;
    if(!n || !m || n>300 || m>300)return infinity;
    if(n*2<m || m*2<n)return infinity;
    uint32_t *previous=scratch.rows[0],*current=scratch.rows[1];
    for(unsigned j=0;j<=m;j++)previous[j]=infinity;
    previous[0]=0;
    for(unsigned i=1;i<=n;i++) {
        current[0]=infinity;
        for(unsigned j=1;j<=m;j++) {
            // Normalized Sakoe-Chiba band, 20% of utterance duration.
            int32_t delta=(int32_t)(i*m)-(int32_t)(j*n);
            if(delta<0)delta=-delta;
            if((uint32_t)delta*5>n*m){current[j]=infinity;continue;}
            uint32_t local=0;
            for(unsigned d=0;d<VOICE_DIM;d++) {
                int32_t x=(int32_t)voice_feature_get(query,(i-1)*VOICE_DIM+d)-voice_feature_get(reference,(j-1)*VOICE_DIM+d);
                local+=(uint32_t)(x<0?-x:x);
            }
            uint32_t best=previous[j];
            if(current[j-1]<best)best=current[j-1];
            if(previous[j-1]<best)best=previous[j-1];
            current[j]=best>=infinity-local?infinity:best+local;
        }
        uint32_t *tmp=previous;previous=current;current=tmp;
    }
    return previous[m]>=infinity?infinity:previous[m]/(n+m);
}
int voice_dsp_selfcheck(void) {
    int16_t result[VOICE_DIM];
    voice_features(voice_test_tone,result);
    for(unsigned d=0;d<VOICE_DIM;d++) {
        int error=result[d]-voice_test_expected[d];
        if(error>2 || error<-2)return 0;
    }
    return 1;
}
