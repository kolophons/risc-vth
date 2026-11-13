#!/bin/sh

set -e

DEBUG=false
GDB_ADDR='127.0.0.1:1234'
if [ "${1:-}" = "-d" ]; then DEBUG=true; fi

# assemble, link, and objcopy
echo ":: assembling boot.o ::"
riscv64-none-elf-as -march=rv64im -mabi=lp64 -o boot.o boot.s
echo ":: linking boot.elf"
NIX_BUILD_ID_STYLE=none riscv64-none-elf-ld -Ttext=0x80000000 --build-id=none -o boot.elf boot.o
echo ":: objcopy boot.bin"
riscv64-none-elf-objcopy -O binary boot.elf boot.bin

if [ $DEBUG = true ]; then
  echo ":: gdb -q boot.elf -x debug.gdb "
  echo ":: <C-a> + x to exit"
  qemu-system-riscv64 \
    -machine virt \
    -smp 1 -m 128M \
    -bios none -kernel boot.bin \
    -nographic \
    -S -gdb "tcp:$GDB_ADDR"
else
  echo ":: Starting "
  echo ":: <C-a> + x to exit"
  qemu-system-riscv64 \
    -machine virt \
    -smp 1 -m 128M \
    -bios none -kernel boot.bin \
    -nographic
fi
