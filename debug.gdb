set pagination off
target remote 127.0.0.1:1234
tbreak *_start
continue
display/i $pc
display/x $s0
display/d $t0
display/d $t1
# display our stack
display/2gd 0x8000fff0
