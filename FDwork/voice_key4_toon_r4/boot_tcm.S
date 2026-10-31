/* PH1P35 reset shim. Keep the tested TCM application unchanged. */
#include "app_layout.h"
    .option norvc
    .option norelax
    .section .text.boot,"ax",@progbits
    .global _boot_start, boot_copy, boot_failed, app_payload, app_payload_end
_boot_start:
    csrw mie, zero
    csrci mstatus, 8
    /* Same scratchpad/cache setup used by the SDK application's _start. */
    li t0, 2
    csrw 0x7ca, t0
boot_copy:
    la t0, app_payload
    li t1, APP_TCM_BASE
    la t2, app_payload_end
1:
    lw t3, 0(t0)
    sw t3, 0(t1)
    lw t4, 0(t1)
    bne t3, t4, boot_failed
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t0, t2, 1b
    fence rw, rw
    fence.i
    li t0, APP_ENTRY
    jr t0
boot_failed:
    j boot_failed
    .balign 4
app_payload:
    .incbin "app_payload.bin"
app_payload_end:
