.section .text
.globl _start

# conventions and shorthand
# shorthand, *s0 means "memory at address s0"
# basically, familiar C pointer notation

# s0: data stack pointer
# s1: word-instruction pointer
# s2: return stack pointer

.equ CELL_BYTES, 8

.macro move_stack cells
  # \cells means "substitute macro argument for cells here"
  addi s0, s0, (\cells * CELL_BYTES)
.endm

.macro push_return_stack
  # push current table position to return stack
  addi s2, s2, -CELL_BYTES
  sd s1, 0(s2)
.endm

.macro pop_return_stack
  # pop stored table position from return stack
  ld s1, 0(s2)
  addi s2, s2, CELL_BYTES
.endm
  

_start:
  # t0-t2 are "temporary"
  # s0 i
    li s0, 0x80010000 # load 0x80010000 into s0, we will grow downwards
    li s2, 0x80020000 # begin return stack at 0x8002000

  # put the table's address into s1
    la s1, program    # la -- load the symbol's address

next_word:
  # read the next routine's address from the table
  ld t0, 0(s1)        # load *s1 into t0
  # advance to the next table entry
  addi s1, s1, CELL_BYTES
  # jump to routine's address in t0, saves return address to ra
  # s1 tracks current position in the program table.
  jalr ra, 0(t0)
  j next_word         


hang:
    j hang

word_lit:
  ld t0, 0(s1)      # read from s1 into t0
  move_stack -1     # push stack
  sd t0, 0(s0)      # store t0 in stack
  addi s1, s1, CELL_BYTES # advance past the literal
  ret

word_add:
  # + : pop one value, add it to the remaining top
  ld t0, 0(s0)      # read from s0 into t0 (load top of stack)
  move_stack 1      # pop stack
  ld t1, 0(s0)      # read from s0 into t1 (load top of stack)
  add t1, t1, t0    # add t1 and t0 together, store into t1
  sd t1, 0(s0)      # store t1 at top of stack
  ret # transfer execution back to address in ra

word_emit:
  # EMIT : pop a value and write low byte to UART (serial interface?)
  ld t1, 0(s0)      # load top of stack into t1
  move_stack 1      # pop stack
  li t0, 0x10000000 # load 0x10000000 into t0 (UART's address?)
  sb t1, 0(t0)      # store byte from t1 to t0 (write to UART?)
  ret # return to ra

word_dup:
  # DUP : read the current top value, push a copy, and return
  ld t0, 0(s0)    # read from *s0 into t0
  move_stack -1   # push stack
  sd t0, 0(s0)    # load from t0 into *s0 -- copy.
  ret

word_double:
  push_return_stack
  la s1, double_body
  ret

word_exit:
  pop_return_stack
  ret

.balign CELL_BYTES # align to 8 bytes
# build the program table.
program:
  .dword word_lit
  .dword 33
  .dword word_double
  .dword word_emit
  .dword hang

double_body:
  .dword word_dup
  .dword word_add
  .dword word_exit
