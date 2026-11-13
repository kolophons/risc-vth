set pagination off
target remote 127.0.0.1:1234
# tbreak *_start
# continue
# program counter
# word instruction pointer
# and return address
display/ag $pc
display/ag $s1
display/ag $ra

# stack pointers
display/x $s0
display/4ag $s2

# temp registers
display/d $t0
display/d $t1

# 4 literal stack values, decimal
display "=== DATA STACK (decimal/hex) ==="
display/4gd $s0
# the same, hexadecimal
display/4ag $s0
# display 8-bytes of the token buffer  address
display "=== TOKEN BUFFER (hex/chars) ==="
display/8bx &token_buffer
display/8cb &token_buffer

display "=== COMPILE SPACE ==="
display/4ag &compile_space
display/1ag &here_ptr

# set up a breakpoint
# break *docol if $t0 == (unsigned long long)&xt_read_token
# break *read_token_overflow
break *next_word if $s1 == (unsigned long long)&stop
continue 
