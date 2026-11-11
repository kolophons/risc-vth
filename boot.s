.section .text
.globl _start

_start:
  # t0-t2 are "temporary"
  # s0 i
    li s0, 0x80010000 # load 0x80010000 into s0, we will grow downwards
    
    # push 65
    li t0, 65         # load 65 into t0
    addi s0, s0, -8   # add -8 to s0 ... in effect, move "down" one word length
    sd t0, 0(s0)      # store contents of t0 into s0 (no offset)

    # push 1
    li t0, 1          # same as above, load 1 into t0
    addi s0, s0, -8   # set stack pointer
    sd t0, 0(s0)      # store t0 into s-

    # + : pop one value, add it to the remaining top
    ld t0, 0(s0)      # read from s0 into t0 (load top of stack)
    addi s0, s0, 8    # move stack pointer (pop)
    ld t1, 0(s0)      # read from s0 into t1 (load top of stack)
    add t1, t1, t0    # add t1 and t0 together, store into t1
    sd t1, 0(s0)      # store t1 at top of stack

    # EMIT : pop a value and write low byte to UART (serial interface?)
    ld t1, 0(s0)      # load top of stack into t1
    addi s0, s0, 8    # pop stack
    li t0, 0x10000000 # load 0x10000000 into t0 (UART's address?)
    sb t1, 0(t0)      # store byte from t1 to t0 (write to UART?)

hang:
    j hang
