// Preset voice templates in FPGA RAM, with four external control buttons.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "al_core.h"
#include "al_usart_ll.h"
#include "voice_dsp.h"
#define REG(off) (*(volatile uint32_t *)(uintptr_t)(0x80000000u+(off)))
static const uint32_t commands[4]={0x00010101,0x00040301,2,3};
static const char *names[4]={"ZHUI ZONG HONG SE YUAN XING","ZHUI ZONG LAN SE FANG XING","TING ZHI ZHUI ZONG","YUN TAI HUI ZHONG"};
static uint16_t lengths[4];
static int16_t ring[400],ordered[400],coefficients[13];
static uint32_t threshold=0,margin=0;
static int presets_active;
static uint32_t crc_word(uint32_t crc,uint32_t word) {
    for(unsigned b=0;b<4;b++) {
        crc^=word&255u;word>>=8;
        for(unsigned k=0;k<8;k++)crc=(crc>>1)^(0xedb88320u&(0u-(crc&1u)));
    }
    return crc;
}
static void load_presets(void) {
    uint32_t h[16],crc=~0u;
    for(unsigned i=0;i<16;i++)h[i]=REG(0x1bc00u+i*4u);
    for(unsigned i=0;i<15;i++)crc=crc_word(crc,h[i]);
    if(h[0]!=0x5654504cu || h[1]!=1 || h[2]!=VOICE_RATE || h[3]!=VOICE_DIM ||
       h[4]!=7800 || h[12]!=31200 || (crc^~0u)!=h[15] || !h[9]) {
        printf("PRESET_TEMPLATES=FAIL header\r\n");return;
    }
    for(unsigned i=0;i<4;i++)if(h[5+i]<20 || h[5+i]>VOICE_MAX_FRAMES) {
        printf("PRESET_TEMPLATES=FAIL lengths\r\n");return;
    }
    crc=~0u;
    for(unsigned i=0;i<7800;i++)crc=crc_word(crc,REG(0x10000u+i*4u));
    if((crc^~0u)!=h[11]){printf("PRESET_TEMPLATES=FAIL data_crc\r\n");return;}
    for(unsigned i=0;i<4;i++)lengths[i]=(uint16_t)h[5+i];
    threshold=h[9];margin=h[10];presets_active=1;
    printf("PRESET_TEMPLATES=PASS frames=%u,%u,%u,%u threshold=%u margin=%u\r\n",
           lengths[0],lengths[1],lengths[2],lengths[3],(unsigned)threshold,(unsigned)margin);
}
static int button_abort_pending(void) {
    unsigned pending=REG(0x58)&15u;
    if(pending&3u)REG(0x58)=pending&3u; // Busy RECORD/CLASSIFY drops queued normal actions.
    return ((pending|REG(0x5c))&12u)!=0;
}
static void axis_status(void) {
    unsigned status=(unsigned)REG(0x40);
    printf("AXIS status=%x pan_steps=%ld target=%ld servo_us=%u active_us=%u\r\n",
           status,(long)(int32_t)REG(0x44),(long)(int32_t)REG(0x34),
           (unsigned)REG(0x38),(unsigned)REG(0x48));
    printf("FOLLOW cfg=%x fresh=%u age_ms=%u frame=%u\r\n",(unsigned)REG(0x30),
           (status>>6)&1u,(unsigned)REG(0x50),(unsigned)REG(0x54));
    uint32_t xy=REG(0x28),info=REG(0x2c);
    printf("VISION x=%u y=%u valid=%u\r\n",(unsigned)(xy&0xffffu),
           (unsigned)(xy>>16),(unsigned)((info>>8)&1u));
    printf("SELECT detect=%u count=%u color=%u continued=%u\r\n",
           (unsigned)((info>>9)&3u),(unsigned)((info>>11)&7u),
           (unsigned)((info>>14)&1u),(unsigned)((info>>15)&1u));
    printf("BUTTONS pending=%x held=%x\r\n",(unsigned)REG(0x58),(unsigned)REG(0x5c));
}
static uint64_t ticks(void) {
    uint32_t hi,lo,again;
    do {__asm__ volatile("csrr %0,mcycleh":"=r"(hi));
        __asm__ volatile("csrr %0,mcycle":"=r"(lo));
        __asm__ volatile("csrr %0,mcycleh":"=r"(again));}while(hi!=again);
    return ((uint64_t)hi<<32)|lo;
}
static int input_char(void) {
    if(AlUsart_ll_GetStatus(USART0_BASE_ADDR)&(1u<<AL_USART_STATUS_EMPTY))return -1;
    int c=AlUsart_ll_RecvData(USART0_BASE_ADDR)&0xff;
    AlUsart_ll_ClrStatus(USART0_BASE_ADDR,AL_USART_STATUS_RX_EOT);
    AlUsart_ll_SetRxSize(USART0_BASE_ADDR,1);return c;
}
static int send_command(uint32_t command) {
    uint64_t deadline=ticks()+30000000;
    while(REG(0x24)&1)if(ticks()>deadline)return 0;
    REG(0x20)=command;__asm__ volatile("fence iorw,iorw":::"memory");
    while(REG(0x24)&1)if(ticks()>deadline)return 0;
    return 1;
}
static unsigned record(unsigned slot) {
    if(button_abort_pending()){printf("REJECT BUTTON_STOP\r\n");return 0;}
    if(!(REG(0x0c)&1)){printf("MIC_NOT_READY\r\n");return 0;}
    volatile uint32_t *p=(volatile uint32_t *)(uintptr_t)(0x80010000u+7800u*slot);
    for(unsigned i=0;i<1950;i++)p[i]=0;
    unsigned total=0,index=0,hop=0,frames=0,bank=0;
    unsigned started=0,voiced=0,silence=0,noise=32,sum=0,peak=0,clipped=0;
    unsigned speech_begin=0,energy_min=32768,energy_max=0,last_gate=0,voiced_max=0;
    uint32_t max_block_cycles=0;
    uint64_t start=ticks();REG(8)=1;
    printf("RECORD: start within 3 seconds; then max 3 seconds including ending silence\r\n");
    for(;;) {
        uint32_t state=REG(0x0c);
        if(button_abort_pending()){printf("REJECT BUTTON_STOP\r\n");frames=0;break;}
        if(state&(1u<<4)){printf("REJECT AUDIO_OVERFLOW\r\n");frames=0;break;}
        if(ticks()-start>2400000000ULL){printf("REJECT AUDIO_TIMEOUT\r\n");frames=0;break;}
        if(!(state&(1u<<(2+bank))))continue;
        uint64_t block_begin=ticks();
        int finished=0;
        for(unsigned i=0;i<512 && !finished;i++) {
            uint32_t pair=REG(0x1000u+bank*2048u+i*4u);
            for(unsigned half=0;half<2 && !finished;half++) {
                int16_t x=(int16_t)(pair>>(half*16));
                unsigned amplitude=x<0?-(int32_t)x:x;
                if(amplitude>peak)peak=amplitude;
                if(amplitude>=32760)clipped++;
                ring[index]=x;index=(index+1)%400;sum+=amplitude;total++;hop++;
                if(hop==160) {
                    unsigned energy=sum/160;hop=0;sum=0;
                    unsigned gate=noise*4;if(gate<120)gate=120;
                    if(energy<energy_min)energy_min=energy;
                    if(energy>energy_max)energy_max=energy;
                    last_gate=gate;
                    if(!started) {
                        if(energy>gate)voiced++;else {voiced=0;noise=(noise*15+energy)/16;}
                        if(voiced>voiced_max)voiced_max=voiced;
                        if(voiced>=3){started=1;speech_begin=total-3*VOICE_HOP;}
                    }
                    if(started) {
                        silence=energy>gate?0:silence+1;
                        if(total>=400 && frames<300) {
                            for(unsigned j=0;j<400;j++)ordered[j]=ring[(index+j)%400];
                            voice_features(ordered,coefficients);
                            for(unsigned d=0;d<13;d++)voice_feature_put(slot,frames*13+d,coefficients[d]);
                            frames++;
                        }
                        if(silence>=30 && frames>=20)finished=1;
                    }
                }
                if(!started && total>=VOICE_RATE*3){printf("REJECT NO_SPEECH\r\n");frames=0;finished=1;}
                if(started && total-speech_begin>=VOICE_RATE*3 && !finished){printf("REJECT TRUNCATED\r\n");frames=0;finished=1;}
            }
        }
        uint32_t block_cycles=(uint32_t)(ticks()-block_begin);
        if(block_cycles>max_block_cycles)max_block_cycles=block_cycles;
        if(finished)break;
        REG(0x18)=1u<<bank;bank^=1;
    }
    uint32_t final_state=REG(0x0c);REG(8)=0;
    if(button_abort_pending())frames=0;
    if(final_state&(1u<<4))frames=0;
    printf("VAD started=%u onset_sample=%u samples=%u energy_min=%u energy_max=%u noise=%u gate=%u voiced_run_max=%u\r\n",
           started,speech_begin,total,energy_min,energy_max,noise,last_gate,voiced_max);
    if(clipped>100 || frames<20){printf("REJECT QUALITY frames=%u peak=%u clip=%u\r\n",frames,peak,clipped);return 0;}
    voice_normalize(slot,frames);
    printf("FEATURES frames=%u samples=%u peak=%u cycles=%u\r\n",frames,total,peak,(unsigned)(ticks()-start));
    printf("MAX_BLOCK_CYCLES=%u budget_at_300MHz=19660800\r\n",(unsigned)max_block_cycles);
    return frames;
}
static void recognize(void) {
    for(unsigned c=0;c<4;c++)if(!lengths[c]){printf("NOT_READY: enroll all four complete commands first\r\n");return;}
    if(!threshold){printf("NOT_READY: calibrate rejection (T distance margin)\r\n");return;}
    unsigned frames=record(4);if(!frames)return;
    uint32_t best=0x3fffffff,second=0x3fffffff;unsigned label=0;
    uint64_t begin=ticks();
    for(unsigned c=0;c<4;c++) {
        if(button_abort_pending()){printf("REJECT BUTTON_STOP\r\n");return;}
        uint32_t d=voice_distance(4,frames,c,lengths[c]);printf("DIST class=%u score=%u\r\n",c+1,(unsigned)d);
        if(d<best){second=best;best=d;label=c;}else if(d<second)second=d;
    }
    if(button_abort_pending()){printf("REJECT BUTTON_STOP\r\n");return;}
    if(best==0x3fffffff || best>=threshold || second-best<margin)printf("REJECT DISTANCE_OR_MARGIN\r\n");
    else printf("ACCEPT class=%u bus_ack=%d\r\n",label+1,send_command(commands[label]));
    printf("CLASSIFY_CYCLES=%u\r\n",(unsigned)(ticks()-begin));
}
static void handle_buttons(unsigned keys) {
    unsigned control=REG(0x30),flags=control&12u;
    if(keys&12u) {
        if(keys&8u)REG(0x30)=flags;
        send_command(2);
        while(input_char()>=0){} // Discard serial actions accumulated while busy.
        REG(0x58)=15;
        printf("BUTTON %s\r\n",keys&8u?"DISABLE":"STOP");axis_status();return;
    }
    if(keys==2) {
        if(!(control&1u)) {REG(0x30)=flags|1u;printf("BUTTON MANUAL: confirm pose; press MODE again for follow\r\n");}
        else if(control&2u) {REG(0x30)=flags|1u;printf("BUTTON MANUAL\r\n");}
        else {
            for(unsigned i=0;i<4;i++)if(!lengths[i]){printf("NOT_READY: voice templates missing\r\n");return;}
            if(!threshold){printf("NOT_READY: threshold missing\r\n");return;}
            REG(0x30)=flags|3u;printf("BUTTON FOLLOW: press VOICE then speak\r\n");
        }
        axis_status();
    } else if(keys==1)recognize();
    else printf("BUTTON_MULTI_IGNORED\r\n");
}
int main(void) {
    printf("VOICE_KEY4_V8 VOICE_BUTTONS_R1 AXIS_FOLLOW_R5: preset voice; fs=15625\r\n");
    if(REG(0)!=0x564f4938u){printf("FABRIC_ID_FAIL: load matching VOICE_BUTTONS_R1 bit first\r\n");for(;;);}
    REG(0x30)=0; // Disarm before DSP/self-tests, including an ELF-only restart.
    int dsp_ok=voice_dsp_selfcheck();printf("MFCC_SELFTEST=%s\r\n",dsp_ok?"PASS":"FAIL");
    if(!dsp_ok){for(;;);}
    REG(0x1bffc)=0x1234abcd;
    if(REG(0x1bffc)!=0x1234abcd){printf("FABRIC_RAM_FAIL\r\n");for(;;);}
    printf("FABRIC_ID_RAM_PASS; fs=%u\r\n",(unsigned)REG(4));
    load_presets();
    printf("KEYS: VOICE / MODE / STOP / DISABLE; UART r/s/h/p/T also available\r\n");
    printf("AXIS: e manual; f follow; d disable; j/l pan -/+32 pulses; i/k servo +/-50us; z pan origin\r\n");
    printf("a red circle; b blue square; x/y reverse pan/tilt and return to manual mode\r\n");
    AlUsart_ll_EnableRx(USART0_BASE_ADDR,AL_TRUE);AlUsart_ll_SetRxSize(USART0_BASE_ADDR,1);
    char line[48];unsigned used=0;int last_key=0;
    for(;;) {
        unsigned buttons=REG(0x58)&15u;
        if(buttons) {
            REG(0x58)=buttons;buttons|=REG(0x5c)&12u;
            if(buttons&12u)used=0;
            handle_buttons(buttons);last_key=(REG(0x0c)>>6)&1;continue;
        }
        int key=(REG(0x0c)>>6)&1;
        if(key && !last_key)recognize();
        last_key=key;
        int c=input_char();if(c<0)continue;
        if(used || c=='T') {
            if(c=='\r' || c=='\n') {
                line[used]=0;char *tail;
                threshold=(uint32_t)strtoul(line+1,&tail,10);margin=(uint32_t)strtoul(tail,0,10);used=0;
                printf("EXPERIMENTAL threshold=%u margin=%u\r\n",(unsigned)threshold,(unsigned)margin);
            } else if(used<sizeof(line)-1)line[used++]=(char)c;
            else {used=0;threshold=0;printf("REJECT BAD_CONFIG\r\n");}
        } else if(c>='1' && c<='4') {
            if(presets_active){printf("PRESET_LOCKED: use enrollment firmware to replace templates\r\n");continue;}
            unsigned slot=(unsigned)(c-'1');printf("ENROLL %s\r\n",names[slot]);
            lengths[slot]=record(slot);
            if(lengths[slot])printf("ENROLLED class=%u frames=%u (volatile)\r\n",slot+1,lengths[slot]);
            else printf("ENROLL_FAILED class=%u template_invalid\r\n",slot+1);
        } else if(c=='r')recognize();
        else if(c=='s' || c=='h')printf("UART_TEST_COMMAND ack=%d\r\n",send_command(c=='s'?2:3));
        else if(c=='a' || c=='b') {
            unsigned slot=c=='a'?0:1;
            printf("UART_SELECT class=%u ack=%d\r\n",slot+1,send_command(commands[slot]));
        }
        else if(c=='p') {
            printf("STATE=%x XY=%x TRACK=%x templates=%u,%u,%u,%u\r\n",(unsigned)REG(0x0c),(unsigned)REG(0x28),(unsigned)REG(0x2c),lengths[0],lengths[1],lengths[2],lengths[3]);
            axis_status();
        } else if(c=='e' || c=='d' || c=='f') {
            unsigned control=REG(0x30),flags=control&12u;
            if(c=='f' && !(control&1u))
                printf("FOLLOW_NEEDS_MANUAL_POSE: send e, position with i/k, then f\r\n");
            else REG(0x30)=flags|(c=='f'?3u:(c=='e'?1u:0u));
            axis_status();
        } else if(c=='x' || c=='y') {
            unsigned flags=REG(0x30);
            REG(0x30)=(flags^(c=='x'?4u:8u))&13u;axis_status();
        } else if(c=='j' || c=='l') {
            REG(0x34)=c=='j'?(uint32_t)-32:32;axis_status();
        } else if(c=='i' || c=='k') {
            REG(0x38)=c=='i'?50:(uint32_t)-50;axis_status();
        } else if(c=='z') {
            REG(0x3c)=1;axis_status();
        }
    }
}
