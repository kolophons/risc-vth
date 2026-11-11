# RV64I assembly quick reference

A printable companion to building our bare-metal Forth on QEMU's RISC-V
`virt` machine.

- [Print-ready PDF](riscv64-quick-reference.pdf): one US Letter page
  (8.5 × 11 inches), portrait. Print at **100% / actual size**.
- [Generator](make-riscv64-reference.py): Python standard library and
  Ghostscript, producing a vector PDF with embedded fonts.

The sheet covers selected RV64I instructions, register aliases and standard ABI
roles, assembler pseudoinstructions, GNU assembler directives, and our current
Forth data-stack convention. It omits multiplication/division, floating-point,
compressed, and privileged instructions.

The section labeled **Our Forth Data Stack** is a project design choice:
eight-byte cells, `s0` pointing to the top, an empty pointer of `0x80010000`, and
growth toward lower addresses. Update that section if the implementation changes.

## Rebuild

From the project root:

```sh
nix-shell -p python3 ghostscript --run \
  'python3 reference/riscv64/make-riscv64-reference.py'
```

The generator overwrites the PDF beside itself. With Python and Ghostscript
already available, run the Python script directly. An explicit Ghostscript
executable can be supplied with `--gs /path/to/gs`; `--output /path/to/file.pdf`
selects another destination. The script also discovers installed Ghostscript
binaries in the Nix store as a local fallback. The command above uses the host's
Nixpkgs selection; these document tools are not pinned in the project's flake.

After changes, inspect the rendered page for clipping and readability. The
generator checks text widths and the lower page boundary. The delivered version
was also visually checked; `pdfinfo` reported one 612 × 792-point page, and
`pdffonts` confirmed embedded fonts.

## Sources

- [RISC-V base integer instructions](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [RV64I additions and 64-bit loads/stores](https://docs.riscv.org/reference/isa/v20240411/unpriv/rv64.html)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual/blob/main/src/asm-manual.adoc)
- [RISC-V ABI register and calling conventions](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/)
- [GNU assembler RISC-V directives](https://sourceware.org/binutils/docs/as/RISC_002dV_002dDirectives.html)

