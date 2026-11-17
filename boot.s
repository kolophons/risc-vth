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

.macro _word name:req, id:req, code:req, previous:req, flags=0
    .balign CELL_BYTES
dict_\id\():
    .dword \previous
    .byte .Lname_end\@ - .Lname_start\@
    .byte \flags
.Lname_start\@:
    .ascii "\name"
.Lname_end\@:
    .balign CELL_BYTES
xt_\id\():
    .dword \code
.endm

# expand a list of words a, b, c into:
# .dword xt_a
# .dword xt_b
# .dword xt_c
.macro .xt words:vararg
    .irp word, \words
        .dword xt_\word
    .endr
.endm

.macro move_stack cells
  # \cells means "substitute macro argument for cells here"
  addi s0, s0, (\cells * CELL_BYTES)
.endm

# compile a literal
.macro .lit _sym:req
  .dword xt_lit
  .dword \_sym
.endm

# compile fetching an address
.macro .fetch _addr:req # ( -- value )
  .dword xt_lit
  .dword \_addr
  .dword xt_fetch
.endm

.macro .equal _literal:req # ( value -- value flag )
  .dword xt_dup
  .dword xt_lit
  .dword \_literal
  .dword xt_equal
.endm

# store a literal value in memory
.macro .store _sym:req _addr:req 
  .dword xt_lit
  .dword \_sym # ( sym )
  .dword xt_lit
  .dword \_addr # ( sym addr )
  .dword xt_store
.endm

# compile an unconditional branch
.macro .branch _label:req
  .dword xt_branch
  .dword \_label
.endm

# compile a zero-branch
.macro .zbranch _label:req
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

word_hang:
    j word_hang

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

word_sub:
  # - : pop one value and subtract it from the remaining top
  pop_data_stack t0
  get_stack_value t1, 0
  sub t1, t1, t0
  set_stack_value t1, 0
  ret

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


word_plus_one: # ( n1 -- n1+1 )
  get_stack_value t0, 0
  addi t0, t0, 1
  set_stack_value t0, 0
  ret

word_minus_one: # ( n1 -- n1+1 )
  get_stack_value t0, 0
  addi t0, t0, -1
  set_stack_value t0, 0
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

word_twodup: # ( a b -- a b a b )
  get_stack_value t0, 0 # b
  get_stack_value t1, 1 # a
  push_data_stack t1 # ( a b a )
  push_data_stack t0 # ( a b a b )
  ret

word_drop: # ( a -- )
  addi s0, s0, CELL_BYTES
  ret

word_twodrop: # ( a b -- )
  addi s0, s0, CELL_BYTES*2
  ret

word_over: # ( a b -- a b a )
  ld t0, CELL_BYTES(s0)
  push_data_stack t0
  ret

word_twoover: # ( a b c d -- a b c d a b )
  get_stack_value t0, 3 # a
  get_stack_value t1, 2 # b
  push_data_stack t0 # ( a b c d a )
  push_data_stack t1 # ( a b c d a b )
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

word_twoswap: # ( a b c d -- c d a b )
  get_stack_value t0, 0 # d
  get_stack_value t1, 1 # c
  get_stack_value t2, 2 # b
  get_stack_value t3, 3 # a

  set_stack_value t2, 0 # ( a b c b )
  set_stack_value t3, 1 # ( a b a b )
  set_stack_value t0, 2 # ( a d a b )
  set_stack_value t1, 3 # ( c d a b )
  ret

# bitwise helpers
word_and: # ( a b -- a&b )
  pop_data_stack t0
  pop_data_stack t1
  and t2, t1, t0
  push_data_stack t2
  ret

word_or: # ( a b -- a|b )
  pop_data_stack t0
  pop_data_stack t1
  or t2, t1, t0
  push_data_stack t2
  ret

word_xor: # ( a b -- a xor b )
  pop_data_stack t0
  pop_data_stack t1
  xor t2, t1, t0
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
.macro .fetch_entry_nlen # ( entry -- nlen )
    .lit 8
    .dword xt_add
    .dword xt_cfetch
.endm

.macro .fetch_entry_flags # ( entry -- flags )
    .lit 9
    .dword xt_add
    .dword xt_cfetch
.endm


# Typing the first dictionary entry out by hand:
dict_dup:
    .dword 0 # first word
    .byte 3  # length
    .byte 0  # normal execution
    .ascii "DUP"
    .balign CELL_BYTES
xt_dup:
    .dword word_dup

# Thereafter, I use this macro:
# _word "name", id, XT, flags
# Length is calculated in the macro body

# stack helpers
_word "2DUP", twodup, word_twodup, dict_dup
_word "DROP", drop, word_drop, dict_twodup, 0
_word "2DROP", twodrop, word_twodrop, dict_drop, 0
_word "SWAP", swap, word_swap, dict_twodrop, 0
_word "OVER", over, word_over, dict_swap, 0
_word "2OVER", twoover, word_twoover, dict_over, 0
_word "NIP", nip, word_nip, dict_twoover, 0
_word "ROT", rot, word_rot, dict_nip, 0
_word "-ROT", nrot, word_nrot, dict_rot, 0

# arithmetic:
_word "+", add, word_add, dict_nrot
_word "-", sub, word_sub, dict_add
_word "*", mul, word_mul, dict_sub
_word "/MOD", divmod, word_divmod, dict_mul
_word "U/MOD", udivmod, word_udivmod, dict_divmod
_word "1-", minus_one, word_minus_one, dict_udivmod
_word "1+", plus_one, word_plus_one, dict_minus_one
_word "EMIT", emit, word_emit, dict_plus_one
_word ";", semicolon, docol, dict_emit, F_IMMEDIATE
    .fetch pending_entry  # ( entry|0 )
    .xt dup
    .zbranch bad_token    # reject ; without an active definition

    .lit xt_exit
    .xt comma # append EXIT to new def

    .lit latest_ptr
    .xt store # set latest* = entry

    .store 0 pending_entry # unset pending_entry
    .store 0 compiling_ptr # unset compiling flag
    .xt exit # return from semicolon

_word ":", colon, docol, dict_semicolon, 0
    .xt read_token # ( addr len|0 )
    .xt dup
    .zbranch colon_bad_name
    .xt make_header # ( entry )
    .lit pending_entry    
    .xt store       # keep track of current word entry
    .lit docol
    .xt comma       # write code field (docol, since it's a forth word)
    .store -1 compiling_ptr # set COMPILING flag to true
    .xt exit        # return to interpret
  colon_bad_name:
    .xt twodrop
    .lit 63
    .xt emit        # emit ?
    .xt hang 

_word "ECHO-ON", echo_on, docol, dict_colon, 0
    .store -1 echo_enabled
    .xt exit

_word "ECHO-OFF", echo_off, docol, dict_echo_on, 0
    .store 0 echo_enabled
    .xt exit

_word "FIND", find, word_find, dict_echo_off, 0
_word ">CFA", to_cfa, word_to_cfa, dict_find, 0
_word "U<", uless, word_uless, dict_to_cfa, 0

_word "BRANCH", branch, word_branch, dict_uless, 0
_word "ZBRANCH", zbranch, word_zbranch, dict_branch, 0
_word "LIT", lit, word_lit, dict_zbranch, 0
_word "EXIT", exit, word_exit, dict_lit, 0
_word "KEY", key, word_key, dict_exit, 0
_word "HANG", hang, word_hang, dict_key, 0

# bitwise helpers
_word "AND", and, word_and, dict_hang, 0
_word "OR", or, word_or, dict_and, 0
_word "XOR", xor, word_xor, dict_or, 0

# memory helpers
_word "!", store, word_store, dict_xor, 0
_word "@", fetch, word_fetch, dict_store, 0
_word "C!", cstore, word_cstore, dict_fetch, 0
_word "C@", cfetch, word_cfetch, dict_cstore, 0
_word "EXECUTE", execute, word_execute, dict_cfetch, 0
_word "MAKE-HEADER", make_header, word_make_header, dict_execute, 0

xt_ten_times: # ( n -- n*10 )
  .dword docol
  .lit 10
  .xt mul
  .xt exit

_word "PARSE-NUMBER", parse_number, docol, dict_make_header
    .xt dup
    .zbranch parse_bad_input # reject empty token
    .lit 0
  parse_again: # ( addr remaining acc )
    .xt over # ( addr rem acc rem )
    .zbranch parse_done # if remaining == 0, we're done
    .xt ten_times
    .xt rot # ( remaining acc*10 addr )
    .xt dup
    .xt lit
    .dword 1
    .xt add
    .xt swap
    .xt cfetch # ( remaining acc*10 next-addr char )
    .lit -48
    .xt add # ( remaining acc*10 next-addr digit )
    .xt dup
    .lit 10
    .xt uless # ( remaining acc*10 next-addr digit digit<10? )
    .zbranch parse_bad_digit

    .xt rot 
    .xt add # ( remaining next-addr new-acc ) new-acc=acc*10+digit
    .xt rot # ( next-addr new-acc remaining )
    .xt lit
    .dword -1
    .xt add
    .xt swap # ( next-addr new-remaining new-acc ) decrement remaining
    .branch parse_again
  parse_done: # ( addr 0 accumulator )
    .xt nip
    .xt nip
    .lit -1
    .xt exit # ( accumulator flag-true )
  parse_bad_digit: # ( remaining acc*10 next-addr bad-digit )
    .xt twodrop
  parse_bad_input: # ( leftover-cell-1 leftover-cell-2 )
    .xt twodrop
    .lit 0
    .lit 0
    .xt exit


_word "READ-TOKEN", read_token, docol, dict_parse_number, 0
    .xt skip_blanks # ( char )
    .xt lit
    .dword 0 # initialize token buffer offset
    .xt swap # ( 0 char )

    read_token_again: # ( offset char )
    .xt over # ( offset char offset )

    # begin overflow handling
    .xt dup # ( offset char offset offset )
    .lit 32 # ( ... 32 )
    .xt uless # ( offset char offset offset<32? )
    .xt zbranch
    .dword read_token_overflow # if we've read 32 bytes, overflow

    read_token_continue:
    .xt lit
    .dword token_buffer # ( offset char offset addr )
    .xt add # ( offset char addr+o )
    .xt cstore # ( offset )
    .lit 1
    .xt add # ( offset+1 )
    .xt console_key
    .xt dup
    .xt lit
    .dword 33
    .xt uless           # ( offset+1 char char<33? )
    .xt zbranch 
    .dword read_token_again # if it's not a space, read it
    # .xt branch
    # .dword read_token_done
    read_token_done:          # ( offset whitespace-char )
    .xt drop
    .xt lit
    .dword token_buffer
    .xt swap            # ( addr offset )
    .xt exit

    read_token_overflow: # ( offset char offset )
    .xt drop
    .xt drop
    .xt drop

    drop_overflow_char_again:
    .xt console_key
    .xt lit
    .dword 33
    .xt uless # ( char<33? )
    .xt zbranch # if it's not whitespace, drop another
    .dword drop_overflow_char_again

    # finally, exit
    .xt lit
    .dword token_buffer
    .xt lit
    .dword 0
    .xt exit # ( &token_buffer 0 )


# SKIP-BLANKS ( -- char )
# skips whitespace until the first non-whitespace char
# leaves non-whitespace char on the stack
_word "SKIP-BLANKS", skip_blanks, docol, dict_read_token, 0
    
    skip_blanks_again:
    .xt console_key       # ( char )
    .xt dup 
    .lit 33 
    .xt uless                   # ( char char<33? )
    .zbranch skip_blanks_done   # zero means non whitespace, finish
    .xt drop                    # drop the whitespace char
    .branch skip_blanks_again
    
    skip_blanks_done:
    .xt exit


_word "HERE", here, docol, dict_skip_blanks, 0
    .fetch here_ptr
    .xt exit

# 
_word ",", comma, docol, dict_here, 0 # ( xt -- )
    .xt here # ( xt here_ptr )
    .xt swap over store # ( here_ptr ) store xt at here_ptr
    .lit CELL_BYTES
    .xt add   # ( here_ptr++ )
    .lit here_ptr   # ( here_ptr+1 here_ptr )
    .xt store exit # increment here_ptr to next free memory cell

_word "CONSOLE-KEY", console_key, docol, dict_comma, 0 # ( -- char )
    .xt key     # raw input
    .fetch echo_enabled
    .zbranch console_key_done
    .xt dup emit   # dup char and display it
  console_key_done:
    .xt exit

# IF: ( -- addr )
# leaves the address of the branch instruction on the stack
_word "IF", if, docol, dict_console_key, F_IMMEDIATE
    .lit xt_zbranch
    .xt comma      # append runtime branch instruction
    .xt here       # retain address of its target cell
    .lit 0
    .xt comma      # compile placeholder 0
    .xt exit

# THEN: ( patch-addr -- )
# Backpatches the current address to a given address in memory
# Expected to be called after IF during compilation
_word "THEN", then, docol, dict_if, F_IMMEDIATE
    .xt here       # ( patch-address target-address )
    .xt swap store # write the target address to the patch address
    .xt exit

# BEGIN: ( -- loop-start-addr )
# Compilation word.
_word "BEGIN", begin, docol, dict_then, F_IMMEDIATE
    .xt here
    .xt exit

# UNTIL: ( loop-start-addr -- )
# Compilation word.
_word "UNTIL", until, docol, dict_begin, F_IMMEDIATE
    .lit xt_zbranch   # ( loop-start-addr 0branch-xt )
    .xt comma         # compile 0branch instruction
    .xt comma         # compile loop-start-addr 
    .xt exit
_word "IMMEDIATE", immediate, docol, dict_until
    .fetch latest_ptr
    .lit 9 # ( addr 9 ) 9 is flags-offset
    .xt add dup cfetch # ( dict-flag-addr flags)
    .lit F_IMMEDIATE
    .xt or # ( dict-flag-addr flags|F_IMMEDIATE )
    .xt swap cstore
    .xt exit


# # ACCEPT: ( buffer capacity -- length )
# # Accepts characters up to a newline, and returns length
# # Handles backspaces and key echoing.
# _word "ACCEPT", accept, docol, dict_equal, 0
#     .lit 0 # push current char count of 0
#     .xt begin # BEGIN: ( buffer capacity length )
#     accept_loop:
# 
#       # get raw input
#       .xt key     # ( buffer capacity len char ) 
# 
#       # handle optional echoing
#       .fetch echo_enabled
#       .zbranch echo_done
#         .xt dup emit   # dup char and display it
#       echo_done:
# 
#       # check if it's a backspace, if so, decrement len and loop
#       # macro .equal: `DUP LIT <n> =`
#       .equal 8 # ascii backspace
#       .xt if
#         .xt drop            # ( buffer capacity len )
#         .xt minus_one       # ( buffer capacity len-1 )
#         .branch accept_loop # continue
#       .xt then
# 
#       # check if we're not at capacity. If so, push:
#       # ( buffer capacity len char )
#       .xt nrot twodup swap uless # ( buffer char capacity len len<capacity )
#       .xt if             # ( buffer char capacity len )
#         .xt plus_one     # ( buffer char capacity len+1 )
#         .xt twoover swap # ( buffer char capacity len+1 char buffer )
#         .xt cstore       # stores the char at the buffer.
#       .xt then  # ( buffer char capacity len )
#       .xt rot   # ( buffer capacity len char)
#                 # check if it's a linefeed, if so, quit
#       .equal 10 # ascii LF
#       
#     .xt until # UNTIL: char=='\n'
#     .xt drop nip nip # ( len )
# 
#     .xt exit
# 
# _word "INTERPRET", interpret, docol, dict_accept, 0

program:
  interpret_again:
    .xt read_token # ( addr len )
    .xt over
    .xt over
    .xt find # ( addr len entry|0 )
    .xt dup
    .zbranch try_number 
    .xt nip
    .xt nip
    # word found

    # check if we're compiling
    .fetch compiling_ptr # ( entry compiling? )
    .zbranch execute_entry # not compiling? execute it

    # otherwise, check if it's an immediate word
    .xt dup         # ( entry entry )
    .fetch_entry_flags    # ( entry flags )
    .lit F_IMMEDIATE      # ( entry flags F_IMMEDIATE )
    .xt and         # ( entry immediate? )
    .zbranch compile_entry # if not immediate, then compile
  execute_entry:
    .xt to_cfa      # ( xt )
    .xt execute     # do word
    .branch interpret_again
  compile_entry:
    .xt to_cfa       # ( xt )
    .xt comma        # compile xt to HERE and increment HERE
    .branch interpret_again

    # else, execute it
  try_number: # ( addr len 0 )
    .xt drop # ( addr len )
    .xt parse_number    # ( number success? )
    .zbranch bad_token
    .fetch compiling_ptr      # ( number compiling? )
    .zbranch interpret_again  # interpreting, retain the number
    .lit xt_lit               # ( number xt-of-LIT )
    .xt comma           # write xt_lit
    .xt comma           # write number
    .branch interpret_again
  bad_token:
    .xt drop

    .lit 63
    .xt emit
    stop:
    .xt hang

# state cells
.balign CELL_BYTES
compiling_ptr:
    .dword 0 # boolean flag, either 0 or -1 by convention
latest_ptr:
    .dword dict_immediate
pending_entry:
    .dword 0
echo_enabled:
    .dword -1

token_buffer:
    .space 32

accept_buffer:
    .space 256

.balign CELL_BYTES
here_ptr:
    .dword compile_space

compile_space:
    .space 1024 # reserves 1024 bytes
