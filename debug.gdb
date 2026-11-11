set pagination off
target remote 127.0.0.1:1234
tbreak *_start
continue
# program counter
# word instruction pointer
# and return address
display/i $pc
display/x $s1
display/x $ra

# stack pointers
display/x $s0
display/x $s2

# temp registers
display/d $t0
display/d $t1

# literal stack values
display/2gd 0x8000fff0
