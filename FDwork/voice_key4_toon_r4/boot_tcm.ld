OUTPUT_ARCH("riscv")
ENTRY(_boot_start)
MEMORY { FLASH (rx) : ORIGIN = 0x20e00000, LENGTH = 2M }
SECTIONS {
    .text : { KEEP(*(.text.boot)) } > FLASH
    /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
ASSERT(_boot_start == 0x20e00000, "Wrong PH1P35 reset address")
ASSERT(app_payload_end - app_payload <= 48K, "Payload exceeds TCM")
