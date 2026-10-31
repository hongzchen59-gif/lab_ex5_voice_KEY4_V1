ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x08000000, LENGTH = 128K }
SECTIONS {
 .text : { *(.text.start) *(.text*) *(.rodata*) } > ram
 .data : { *(.data*) *(.sdata*) } > ram
 .bss (NOLOAD) : { . = ALIGN(4); _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > ram
 end = _bss_end;
 _stack_top = ORIGIN(ram) + LENGTH(ram);
}
