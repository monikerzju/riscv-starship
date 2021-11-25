#define ROM_BASE 0x20000

.section .text.start, "ax", @progbits
.globl _start
_start:
  li s0, ROM_BASE
  csrr a0, mhartid
  li a1, 0
  jr s0