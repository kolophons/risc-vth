.section .text
.globl _start

# conventions and shorthand
# shorthand, *s0 means "memory at address s0"
# basically, familiar C pointer notation

# s0: data stack pointer
# s1: word-instruction pointer
# s2: return stack pointer

.equ CELL_BYTES, 8
.equ F_IMMEDIATE, 1

.macro move_stack cells
  # \cells means "substitute macro argument for cells here"
  addi s0, s0, (\cells * CELL_BYTES)
.endm

# compile a literal
.macro _lit _sym:req
  .dword xt_lit
  .dword \_sym
.endm

# compile fetching an address
.macro _fetch _addr:req # ( -- value )
  .dword xt_lit
  .dword \_addr
  .dword xt_fetch
.endm

# store a literal value in memory
.macro _store _sym:req _addr:req 
  .dword xt_lit
  .dword \_sym # ( sym )
  .dword xt_lit
  .dword \_addr # ( sym addr )
  .dword xt_store
.endm

# compile an unconditional branch
.macro _branch _label:req
  .dword xt_branch
  .dword \_label
.endm

# compile a zero-branch
.macro _zbranch _label:req
  .dword xt_zbranch
  .dword \_label
.endm

# stack surgery macros
.macro get_stack_value reg depth
  ld \reg, (\depth * CELL_BYTES)(s0)
.endm

.macro set_stack_value reg depth
  sd \reg, (\depth * CELL_BYTES)(s0)
.endm

# push/pop macros
.macro push_data_stack reg
  addi s0, s0, -CELL_BYTES
  sd \reg, 0(s0)
.endm

.macro pop_data_stack reg
  ld \reg, 0(s0)
  addi s0, s0, CELL_BYTES
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

# s1: currently pointing at an xt
# 1. load the xt pointed at by s1 into t0. The XT points to the word's code field
# 2. Increment s1
# 3. Load the code address pointed to by the word's code field
# 4. Jump to the code field
next_word:
  # s1 should contain the execution-token of a word.
  # so, we load the value from memory *at* s1
  # t0 = *s1
  ld t0, 0(s1) 
  addi s1, s1, CELL_BYTES # move forward one cell

  ld t1, 0(t0) # load the code field pointed to by xt
  # the code field contains the address of the instructions

  jalr ra, 0(t1) # jump PC to the code address.
  j next_word

hang:
    j hang

word_uless: # ( u1 u2 -- flag ) ( u1<u2? )
    pop_data_stack t1
    pop_data_stack t0
    sltu t0, t0, t1 # t0 < t1? *t0=1 : *t0=0
    sub t0, zero, t0 # 0 - *t0 (0 or -1)
    push_data_stack t0
    ret

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

word_mul: # ( n1 n2 -- n1*n2 )
  # *
  pop_data_stack t0
  pop_data_stack t1
  mul t2, t0, t1
  push_data_stack t2
  ret

word_divmod: # ( n1 n2 -- rem quot )
  # /MOD
  pop_data_stack t0
  pop_data_stack t1
  div t2, t1, t0   # quot
  rem t3, t1, t0   # rem
  push_data_stack t3
  push_data_stack t2
  ret

word_udivmod: # ( u1 u2 -- rem quot )
  # U/MOD
  pop_data_stack t0
  pop_data_stack t1
  divu t2, t1, t0   # quot
  remu t3, t1, t0   # rem
  push_data_stack t3
  push_data_stack t2
  ret

# EMIT : pop a value and write low byte to UART (serial interface?)
word_emit:
  pop_data_stack t1
  li t0, 0x10000000 # set t0 ti 
emit_wait:
  lbu t2, 5(t0)
  andi t2, t2, 0x20
  beqz t2, emit_wait  # wait until "Data Set Ready" flag?

  sb t1, 0(t0)        # write to uart
  ret

# primitive stack words implemented in assembly for speed.
word_dup:
  # DUP : read the current top value, push a copy, and return
  ld t0, 0(s0)    # read from *s0 into t0
  move_stack -1   # push stack
  sd t0, 0(s0)    # load from t0 into *s0 -- copy.
  ret

word_drop: # ( a -- )
  addi s0, s0, CELL_BYTES
  ret

word_2drop: # ( a b -- )
  addi s0, s0, CELL_BYTES*2
  ret

word_over: # ( a b -- a b a )
  ld t0, CELL_BYTES(s0)
  push_data_stack t0
  ret

word_nip: # (a b -- b )
  get_stack_value t0, 0
  move_stack 1
  set_stack_value t0, 0
  ret

word_rot: # ( a b c -- b c a )
  get_stack_value t0, 0 # [t0]=c
  get_stack_value t1, 1 # [t1]=b
  get_stack_value t2, 2 # [t2]=a
  set_stack_value t2, 0 # a
  set_stack_value t0, 1 # c
  set_stack_value t1, 2 # b
  ret

word_nrot: # ( a b c -- c a b )
  get_stack_value t0, 0 # [t0]=c
  get_stack_value t1, 1 # [t1]=b
  get_stack_value t2, 2 # [t2]=a
  set_stack_value t1, 0 # b
  set_stack_value t2, 1 # a
  set_stack_value t0, 2 # c
  ret

word_swap: # ( a b -- b a )
  get_stack_value t0, 0 # b
  get_stack_value t1, 1 # a
  set_stack_value t0, 1 
  set_stack_value t1, 0
  ret

# boolean helpers
word_and: # ( a b -- a&b )
  pop_data_stack t0
  pop_data_stack t1
  and t2, t1, t0
  push_data_stack t2
  ret

word_fetch: # ( addr -- value )
  pop_data_stack t0 # load address to register t0
  ld t0, 0(t0)      # t0 = *t0
  push_data_stack t0
  ret

word_store: # (value addr -- )
  pop_data_stack t0 # t0 contains addr
  pop_data_stack t1 # t1 contains value
  sd t1, 0(t0)      # t0* = t1
  ret

word_cfetch: # ( addr -- byte )
  pop_data_stack t0 # load address to register t0
  lbu t0, 0(t0)      # t0 = *t0
  push_data_stack t0
  ret

word_cstore: # (value addr -- ) ( write the low byte of value to addr )
  pop_data_stack t0 # t0 contains addr
  pop_data_stack t1 # t1 contains value
  sb t1, 0(t0)      # t0* = t1
  ret

# xt is a word's execution token
word_execute: # ( ... xt -- ... | at jump [t0=xt] [t1=*xt] ) ( jumps pc to *xt )
  pop_data_stack t0
  ld t1, 0(t0)
  jr t1

# at entry to docol, t0 holds the execution token
docol: 
  # return ( -- s1 )
  # reg ( [t0=xt] -- [s1'=xt+1] )
  push_return_stack
  addi s1, t0, CELL_BYTES
  ret

word_exit:
  # return ( addr -- )
  # reg ( -- [s1'=addr] )
  pop_return_stack
  ret

# loads one cell from the UART
word_key: # [t0]=[UART]
    li t0, 0x10000000

  key_wait:
    lbu t1, 5(t0)     # read UART status
    andi t1, t1, 1    # keep only input-ready bit
    beqz t1, key_wait # if zero, check again

    lbu t1, 0(t0)     # read the available byte
    push_data_stack t1
    ret

word_branch: # [s1]=*s1
    # Unconditionally jumps the ip 
    # to the address currently pointed at by the ip
    ld s1, 0(s1)
    ret

word_zbranch: # ( flag -- ) ( executes branch if flag=0 )
    pop_data_stack t0       # pop data stack
    beqz t0, word_branch    # check if 0 -- if so, jump to it.

    # otherwise
    addi s1, s1, CELL_BYTES # move forward one cell
    ret


word_to_cfa: # ( entry -- xt )
    # >CFA
    # entry is a dictionary-entry address
    # load the xt of a dictionary entry onto the stack
    pop_data_stack t0
    lbu t1, CELL_BYTES(t0) # read nlen into t1
    addi t0, t0, 10        # skip link, nlen, flags
    add t0, t0, t1         # skip name bytes
    # round up to next cell boundry
    addi t0, t0, 7
    andi t0, t0, -8 # ( address + 7 ) & ~7 -- ceil to next multiple of 8
    push_data_stack t0
    ret

word_find: # ( addr len -- entry|0 )
    # FIND
    # [t0] = address
    # [t1] = length
    # [t2] = walks dictionary addresses
    # [t3] = walks matching-length name
    pop_data_stack t1 # length
    pop_data_stack t0 # address
    la t2, latest_ptr 
    ld t2, 0(t2)      # load *latest_ptr -- 
    # [t0],[t1] are a counted string, [t2]=latest dictionary entry addr

  find_entry:
    beqz t2, find_done     # [t2]=0 means "end of dictionary", didn't find it.
    lbu t3, CELL_BYTES(t2) # get dict entry's name length
    # compare search tem len with current entry len.
    # if the don't match, go to the next entry
    bne t3, t1, find_previous 
    li t3, 0               # init byte index

  # compare bytewise
  # [t3] = current byte index
  # if all bytes match, then [t3] should equal [t1]
  find_compare:
    beq t3, t1, find_done  # all bytes match, return done.

    add t4, t0, t3
    lbu t4, 0(t4)          # [t4] = token[index]

    add t5, t2, t3
    lbu t5, 10(t5)         # [t5] = entry-name[index]

    bne t4, t5, find_previous # [t4] != [t5]? go to the next entry

    addi t3, t3, 1         # increment current byte index
    j find_compare

  find_previous:
    ld t2, 0(t2) # dereference current entry link addr, update current entry
    j find_entry

  find_done:
    push_data_stack t2
    ret

# compiles a dictionary entry header
word_make_header: # ( addr len -- entry )
    pop_data_stack t1 # [t1]=name len
    pop_data_stack t0 # [t0]=source name address

    la t2, here_ptr   # [t2] = here_ptr
    ld t3, 0(t2)      # [t3] = *here_ptr

    la t4, latest_ptr 
    ld t4, 0(t4)      # [t4] = latest_ptr*

    # [t3] points to the new dictionary entry
    sd t4, 0(t3)      # store link to previous latest entry
    sb t1, 8(t3)      # store name length
    sb zero, 9(t3)    # store 0 flag

    addi t4, t3, 10   # set [t4] to point at entry's name field.

  header_copy:
    beqz t1, header_align # if name is fully written, jump to alignment
    # read one byte from name_address
    lbu t5, 0(t0)     # load byte from name address
    sb t5, 0(t4)      # st
    # iterate
    addi t0, t0, 1    # name_address++
    addi t4, t4, 1    # entry_name++
    addi t1, t1, -1   # remaining_length--
    j header_copy

  header_align:
    addi t4, t4, 7     
    andi t4, t4, -8   # align upcoming code field to next multiple of 8
    sd t4, 0(t2)       # update HERE
    push_data_stack t3 # return entry's address
    ret


.balign CELL_BYTES # align to 8 bytes
# build the program table.

# dictionary entry layout
# 8 bytes: address for previous entry (aka "link")
# 1 byte : name length (nlen)
# 1 byte : flags
# nlen bytes : literal name characters
# padding* (aligned to CELL_BYTES)
# 8 bytes: code field
#
# so, a dictionary entry is at least 3 cells (when nlen < 7, 3 cells)
# for colon-words, the entry also contains the threaded body.

# lookup helpers:
.macro _fetch_entry_nlen # ( entry -- nlen )
    _lit 8
    .dword xt_add
    .dword xt_cfetch
.endm

.macro _fetch_entry_flags # ( entry -- flags )
    _lit 9
    .dword xt_add
    .dword xt_cfetch
.endm


dict_dup:
    .dword 0              # first entry
    .byte 3
    .byte 0
    .ascii "DUP"
    .balign CELL_BYTES
xt_dup:   .dword word_dup
dict_add:
    .dword dict_dup       # previous dictionary entry
    .byte 1               # length
    .byte 0
    .ascii "+"
    .balign CELL_BYTES
xt_add:   .dword word_add
dict_emit:
    .dword dict_add
    .byte 4
    .byte 0
    .ascii "EMIT"
    .balign CELL_BYTES
xt_emit:  .dword word_emit

dict_semicolon: # append EXIT to a word, then set compiling_ptr*=0
    .dword dict_emit
    .byte 1
    .byte F_IMMEDIATE
    .ascii ";"
    .balign CELL_BYTES
xt_semicolon: 
    .dword docol

    _fetch pending_entry  # ( entry|0 )
    .dword xt_dup
    _zbranch bad_token    # reject ; without an active definition

    _lit xt_exit
    .dword xt_comma # append EXIT to new def

    _lit latest_ptr
    .dword xt_store # set latest* = entry

    _store 0 pending_entry # unset pending_entry
    _store 0 compiling_ptr # unset compiling flag
    .dword xt_exit # return from semicolon

dict_colon:
    .dword dict_semicolon
    .byte 1
    .byte 0       # ordinary
    .ascii ":"
    .balign CELL_BYTES
xt_colon: # ( -- )
    .dword docol
    .dword xt_read_token # ( addr len|0 )
    .dword xt_dup
    _zbranch colon_bad_name
    .dword xt_make_header # ( entry )
    _lit pending_entry    
    .dword xt_store       # keep track of current word entry
    _lit docol
    .dword xt_comma       # write code field (docol, since it's a forth word)
    _store -1 compiling_ptr # set COMPILING flag to true
    .dword xt_exit        # return to interpret
  colon_bad_name:
    .dword xt_2drop
    _lit 63
    .dword xt_emit        # emit ?
    .dword xt_hang 

xt_find: .dword word_find
xt_mul: .dword word_mul

xt_to_cfa: .dword word_to_cfa
xt_uless: .dword word_uless
xt_branch: .dword word_branch
xt_zbranch: .dword word_zbranch
xt_lit:   .dword word_lit
xt_exit:  .dword word_exit
xt_key:   .dword word_key
xt_hang:  .dword hang
xt_drop:  .dword word_drop
xt_2drop:  .dword word_2drop
xt_swap:  .dword word_swap
xt_over:  .dword word_over
xt_nip:   .dword word_nip
xt_rot:   .dword word_rot
xt_nrot:  .dword word_nrot

# boolean helpers
xt_and:   .dword word_and

xt_store: .dword word_store
xt_fetch: .dword word_fetch
xt_cstore: .dword word_cstore
xt_cfetch: .dword word_cfetch
xt_execute: .dword word_execute
xt_make_header: .dword word_make_header

xt_ten_times: # ( n -- n*10 )
  .dword docol
  _lit 10
  .dword xt_mul
  .dword xt_exit

xt_parse_number: # ( addr len )
    .dword docol 
    .dword xt_dup
    _zbranch parse_bad_input # reject empty token
    _lit 0
  parse_again: # ( addr remaining acc )
    .dword xt_over # ( addr rem acc rem )
    _zbranch parse_done # if remaining == 0, we're done
    .dword xt_ten_times
    .dword xt_rot # ( remaining acc*10 addr )
    .dword xt_dup
    .dword xt_lit
    .dword 1
    .dword xt_add
    .dword xt_swap
    .dword xt_cfetch # ( remaining acc*10 next-addr char )
    _lit -48
    .dword xt_add # ( remaining acc*10 next-addr digit )
    .dword xt_dup
    _lit 10
    .dword xt_uless # ( remaining acc*10 next-addr digit digit<10? )
    _zbranch parse_bad_digit

    .dword xt_rot 
    .dword xt_add # ( remaining next-addr new-acc ) new-acc=acc*10+digit
    .dword xt_rot # ( next-addr new-acc remaining )
    .dword xt_lit
    .dword -1
    .dword xt_add
    .dword xt_swap # ( next-addr new-remaining new-acc ) decrement remaining
    _branch parse_again
  parse_done: # ( addr 0 accumulator )
    .dword xt_nip
    .dword xt_nip
    _lit -1
    .dword xt_exit # ( accumulator flag-true )
  parse_bad_digit: # ( remaining acc*10 next-addr bad-digit )
    .dword xt_2drop
  parse_bad_input: # ( leftover-cell-1 leftover-cell-2 )
    .dword xt_2drop
    _lit 0
    _lit 0
    .dword xt_exit


xt_read_token:
    .dword docol
    .dword xt_skip_blanks # ( char )
    .dword xt_lit
    .dword 0 # initialize token buffer offset
    .dword xt_swap # ( 0 char )

    read_token_again: # ( offset char )
    .dword xt_over # ( offset char offset )

    # begin overflow handling
    .dword xt_dup # ( offset char offset offset )
    _lit 32 # ( ... 32 )
    .dword xt_uless # ( offset char offset offset<32? )
    .dword xt_zbranch
    .dword read_token_overflow # if we've read 32 bytes, overflow

    read_token_continue:
    .dword xt_lit
    .dword token_buffer # ( offset char offset addr )
    .dword xt_add # ( offset char addr+o )
    .dword xt_cstore # ( offset )
    _lit 1
    .dword xt_add # ( offset+1 )
    .dword xt_key
    .dword xt_dup
    .dword xt_lit
    .dword 33
    .dword xt_uless           # ( offset+1 char char<33? )
    .dword xt_zbranch 
    .dword read_token_again # if it's not a space, read it
    # .dword xt_branch
    # .dword read_token_done
    read_token_done:          # ( offset whitespace-char )
    .dword xt_drop
    .dword xt_lit
    .dword token_buffer
    .dword xt_swap            # ( addr offset )
    .dword xt_exit

    read_token_overflow: # ( offset char offset )
    .dword xt_drop
    .dword xt_drop
    .dword xt_drop

    drop_overflow_char_again:
    .dword xt_key
    .dword xt_lit
    .dword 33
    .dword xt_uless # ( char<33? )
    .dword xt_zbranch # if it's not whitespace, drop another
    .dword drop_overflow_char_again

    # finally, exit
    .dword xt_lit
    .dword token_buffer
    .dword xt_lit
    .dword 0
    .dword xt_exit # ( &token_buffer 0 )



xt_skip_blanks:
    .dword docol
    
    skip_blanks_again:
    .dword xt_key           # ( char )
    .dword xt_dup           # ( char char )
    .dword xt_lit
    .dword 33               # ( char char 33 )
    .dword xt_uless         # ( char char<33? )
    .dword xt_zbranch
    .dword skip_blanks_done   # zero means non whitespace, finish
    .dword xt_drop
    .dword xt_branch
    .dword skip_blanks_again
    
    skip_blanks_done:
    .dword xt_exit


xt_here:
    .dword docol
    _fetch here_ptr
    .dword xt_exit

xt_comma: # ( xt -- )
    .dword docol
    .dword xt_here  # ( xt here_ptr )
    .dword xt_swap  # ( here_ptr xt ) 
    .dword xt_over  # ( here_ptr xt here_ptr )
    .dword xt_store # ( here_ptr ) store xt at here_ptr
    _lit CELL_BYTES
    .dword xt_add   # ( here_ptr++ )
    _lit here_ptr   # ( here_ptr+1 here_ptr )
    .dword xt_store # increment here_ptr to next free memory cell
    .dword xt_exit

scratch:
  .dword 0x4242424242424242

xt_double:
  .dword docol

double_body:
  .dword xt_dup
  .dword xt_add
  .dword xt_exit

xt_quadruple:
  .dword docol

quadruple_body:
  .dword xt_double
  .dword xt_double
  .dword xt_exit

program:
  interpret_again:
    .dword xt_read_token # ( addr len )
    .dword xt_over
    .dword xt_over
    .dword xt_find # ( addr len entry|0 )
    .dword xt_dup
    _zbranch try_number 
    .dword xt_nip
    .dword xt_nip
    # word found

    # check if we're compiling
    _fetch compiling_ptr # ( entry compiling? )
    _zbranch execute_entry # not compiling? execute it

    # otherwise, check if it's an immediate word
    .dword xt_dup         # ( entry entry )
    _fetch_entry_flags    # ( entry flags )
    _lit F_IMMEDIATE      # ( entry flags F_IMMEDIATE )
    .dword xt_and         # ( entry immediate? )
    _zbranch compile_entry # if not immediate, then compile
  execute_entry:
    .dword xt_to_cfa      # ( xt )
    .dword xt_execute     # do word
    _branch interpret_again
  compile_entry:
    .dword xt_to_cfa       # ( xt )
    .dword xt_comma        # compile xt to HERE and increment HERE
    _branch interpret_again

    # else, execute it
  try_number: # ( addr len 0 )
    .dword xt_drop # ( addr len )
    .dword xt_parse_number    # ( number success? )
    _zbranch bad_token
    _fetch compiling_ptr      # ( number compiling? )
    _zbranch interpret_again  # interpreting, retain the number
    _lit xt_lit               # ( number xt-of-LIT )
    .dword xt_comma           # write xt_lit
    .dword xt_comma           # write number
    _branch interpret_again
  bad_token:
    .dword xt_drop

    _lit 63
    .dword xt_emit
    stop:
    .dword xt_hang

# program:
#   .dword xt_lit
#   .dword 33
#   .dword xt_here
#   .dword xt_lit
#   .dword docol
#   .dword xt_comma
#   .dword xt_lit
#   .dword xt_dup
#   .dword xt_comma
#   .dword xt_lit
#   .dword xt_add
#   .dword xt_comma
#   .dword xt_lit
#   .dword xt_exit
#   .dword xt_comma
#   .dword xt_execute
#   .dword xt_emit
#   .dword xt_hang 

.balign CELL_BYTES
compiling_ptr:
    .dword 0 # boolean flag, either 0 or -1 by convention
latest_ptr:
    .dword dict_colon
pending_entry:
    .dword 0

token_buffer:
    .space 32

.balign CELL_BYTES
here_ptr:
    .dword compile_space

compile_space:
    .space 1024 # reserves 1024 bytes
