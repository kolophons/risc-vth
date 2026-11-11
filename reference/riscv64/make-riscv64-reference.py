#!/usr/bin/env python3
"""Generate the US Letter reference with Python's stdlib and Ghostscript.

Run from the project root:
  nix-shell -p python3 ghostscript --run \
    'python3 reference/riscv64/make-riscv64-reference.py'
The source is PostScript rendered to vector PDF; no Python packages are needed.
"""

import argparse
import glob
from pathlib import Path
import shutil
import subprocess
import tempfile


def ps_string(value):
    value.encode("ascii")
    return "(" + value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


class Sheet:
    def __init__(self):
        self.lines = [
            "%!PS-Adobe-3.0",
            "%%BoundingBox: 0 0 612 792",
            "%%Pages: 1",
            "<< /PageSize [612 792] >> setpagedevice",
            "[ /Title (RISC-V RV64I - Assembly Quick Reference)",
            "  /Subject (A US Letter reference for the XO bare-metal Forth project)",
            "  /Creator (make-riscv64-reference.py and Ghostscript) /DOCINFO pdfmark",
        ]

    def text(self, x, y, value, size=9.3, font="Helvetica", width=262):
        if y < 35:
            raise ValueError(f"Text below printable area: {value}")
        literal = ps_string(value)
        self.lines += [
            f"/{font} findfont {size} scalefont setfont",
            f"{literal} stringwidth pop {width} gt",
            "{ " + ps_string("OVERFLOW: " + value) + " = } if",
            f"0 setgray {x} {y} moveto {literal} show",
        ]

    def rule(self, x1, y, x2, gray=0.65):
        self.lines.append(f"{gray} setgray 0.4 setlinewidth {x1} {y} moveto {x2} {y} lineto stroke")

    def box(self, x, y, width, height):
        self.lines.append(f"0.95 setgray {x} {y} {width} {height} rectfill")

    def heading(self, x, y, title):
        self.text(x, y, title, 10.2, "Helvetica-Bold")
        self.rule(x, y - 5, x + 262)
        return y - 20

    def row(self, x, y, code, meaning, split=128, size=9):
        self.text(x, y, code, size, "Courier", split - 4)
        self.text(x + split, y, meaning, 9.1, width=262 - split)
        return y - 14

    def note(self, x, y, value):
        self.text(x, y, value, 8.7)
        return y - 12

    def render(self):
        self.text(36, 754, "RISC-V / RV64I", 23, "Helvetica-Bold", 380)
        self.text(36, 735, "Assembly quick reference  |  XO bare-metal Forth", 10.5, width=420)
        self.text(470, 754, "US LETTER", 9, "Helvetica-Bold", 106)
        self.text(470, 740, "8.5 x 11 in / 100%", 9, width=106)
        self.rule(36, 725, 576, 0.2)

        x, y = 36, 708
        y = self.heading(x, y, "READING THE NOTATION")
        for line in [
            "Integer registers are 64 bits; addresses count bytes.",
            "rd = destination; rs / r1 / r2 = source registers.",
            "These names are placeholders, e.g. t0, t1, s0.",
            "In grouped instruction names, / means 'or'.",
            "imm = literal number; off = signed byte offset.",
            "70 is decimal; 0x46 is hex. Both are ASCII F.",
            "sext32(v) = sign-extend a 32-bit value to 64 bits.",
        ]:
            y = self.note(x, y, line)

        y = self.heading(x, y - 7, "REGISTER NAMES / STANDARD ABI")
        for name, number, role in [
            ("zero", "x0", "Always zero; writes ignored"),
            ("ra", "x1", "Return address; not saved"),
            ("sp", "x2", "ABI stack pointer; saved"),
            ("gp / tp", "x3 / x4", "Global / thread; reserved"),
            ("t0-t2", "x5-x7", "Temporaries; not saved"),
            ("s0-s1", "x8-x9", "Saved; s0 also named fp"),
            ("a0-a7", "x10-x17", "Arguments; a0/a1 results"),
            ("s2-s11", "x18-x27", "Saved registers"),
            ("t3-t6", "x28-x31", "Temporaries; not saved"),
        ]:
            self.text(x, y, name, 8.7, "Courier", 66)
            self.text(x + 66, y, number, 8.3, "Courier", 64)
            self.text(x + 130, y, role, 8.7, width=132)
            y -= 14
        y = self.note(x, y, '"Saved" = callee restores the value before returning.')
        y = self.note(x, y, "ABI sp alignment: 16 bytes. Our Forth stack uses s0.")
        y = self.note(x, y, "pc is separate: the address of the current instruction.")

        y = self.heading(x, y - 7, "LOADS AND STORES")
        y = self.note(x, y, "Address: off(base) means base + off, in bytes.")
        self.text(x, y, "ld t0,8(s0)", 9, "Courier", 123)
        self.text(x + 128, y, "Read 8 bytes at s0 + 8", 9.1, width=134)
        y -= 14
        self.text(x, y, "sd t0,8(s0)", 9, "Courier", 123)
        self.text(x + 128, y, "Write t0 at s0 + 8", 9.1, width=134)
        y -= 17
        for width, load, store in [
            ("Bytes", "Load", "Store"),
            ("8", "ld", "sd"),
            ("4", "lw / lwu", "sw"),
            ("2", "lh / lhu", "sh"),
            ("1", "lb / lbu", "sb"),
        ]:
            for dx, item in [(0, width), (66, load), (178, store)]:
                self.text(x + dx, y, item, 9, "Courier", 100)
            y -= 14
        for line in [
            "lb/lh/lw sign-extend; lbu/lhu/lwu zero-extend.",
            "Stores use low bits. No implicit address adjustment.",
            "off: -2048..2047. Use 8-byte alignment for ld/sd.",
            "A word is 32 bits; a doubleword is 64 bits.",
        ]:
            y = self.note(x, y, line)

        y = self.heading(x, y - 7, "OUR FORTH DATA STACK")
        y = self.note(x, y, "Project convention: 8-byte cells; s0 points to top.")
        y = self.note(x, y, "Empty s0 = 0x80010000. Push grows downward.")
        y -= 5
        self.box(x, y - 48, 262, 59)
        self.text(x + 8, y - 1, "PUSH t0", 9, "Helvetica-Bold", 118)
        self.text(x + 140, y - 1, "POP into t0", 9, "Helvetica-Bold", 114)
        self.text(x + 8, y - 19, "addi s0,s0,-8", 8.8, "Courier", 118)
        self.text(x + 8, y - 33, "sd t0,0(s0)", 8.8, "Courier", 118)
        self.text(x + 140, y - 19, "ld t0,0(s0)", 8.8, "Courier", 114)
        self.text(x + 140, y - 33, "addi s0,s0,8", 8.8, "Courier", 114)
        y -= 65
        y = self.note(x, y, "RV64I has no built-in push/pop instructions.")
        y = self.note(x, y, "Forth + has stack effect ( a b -- a+b ); b is top.")

        x, y = 314, 708
        y = self.heading(x, y, "INTEGER ARITHMETIC")
        for code, meaning in [
            ("add rd,r1,r2", "rd = r1 + r2"),
            ("addi rd,rs,imm", "rd = rs + imm"),
            ("sub rd,r1,r2", "rd = r1 - r2"),
            ("and/or/xor rd,r1,r2", "Bitwise AND / OR / XOR"),
            ("andi/ori/xori", "Same ops: rd,rs,imm"),
            ("sll/srl/sra rd,r1,r2", "Left / right / signed right"),
            ("lui rd,imm20", "rd = sext32(imm20 << 12)"),
            ("auipc rd,imm20", "rd = pc + sext32(imm20 << 12)"),
        ]:
            y = self.row(x, y, code, meaning, split=120, size=8.8)
        for line in [
            "slli/srli/srai rd,rs,n: immediate shifts, n = 0..63.",
            "Register shifts use low 6 bits of r2. sra sign-fills.",
            "Arithmetic wraps to 64 bits. No condition-code flags.",
            "addi/andi/ori/xori imm: -2048..2047, sign-extended.",
            "addw/addiw/subw: 32-bit result, sign-extended to 64.",
        ]:
            y = self.note(x, y, line)

        y = self.heading(x, y - 7, "COMPARISONS AND BRANCHES")
        y = self.row(x, y, "slt/sltu rd,r1,r2", "rd = (r1 < r2) ? 1 : 0")
        y = self.note(x, y, "slt is signed; sltu is unsigned. slti/sltiu use imm.")
        y = self.note(x, y, "Two-register branches: op r1,r2,label")
        for code, meaning in [
            ("beq / bne", "Equal / not equal"),
            ("blt / bge", "Signed < / >="),
            ("bltu / bgeu", "Unsigned < / >="),
            ("beqz / bnez", "Pseudo: rs,label; ==0 / !=0"),
        ]:
            y = self.row(x, y, code, meaning, split=106)

        y = self.heading(x, y - 7, "ASSEMBLER SHORTHAND / PSEUDOINSTRUCTIONS")
        for code, meaning in [
            ("li rd,value", "Load constant; may expand"),
            ("la rd,symbol", "Load the symbol's address"),
            ("mv rd,rs", "Copy a register"),
            ("j label", "Jump without saving return"),
            ("jr rs", "Jump to address in rs"),
            ("call label", "Save return in ra; jump"),
            ("ret", "Return to address in ra"),
            ("nop", "Advance to next instruction"),
        ]:
            y = self.row(x, y, code, meaning, split=110)
        y = self.note(x, y, "call/ret do not push/pop memory. Save ra if needed.")
        y = self.note(x, y, "Register jumps (jr/ret) clear target address bit 0.")

        y = self.heading(x, y - 7, "GNU ASSEMBLER DIRECTIVES")
        for code, meaning in [
            ("name:", "Define label at this position"),
            (".section .text", "Select the code section"),
            (".globl name", "Export a symbol for linking"),
            (".equ NAME,value", "Define a constant"),
            (".balign 8", "Align next item to 8 bytes"),
            (".byte / .dword", "Emit 8-bit / 64-bit values"),
            ('.asciz "text"', "Emit bytes plus a zero byte"),
        ]:
            y = self.row(x, y, code, meaning, split=110)

        self.rule(36, 81, 576)
        self.text(36, 67, "Scope: selected RV64I + GNU assembler shorthand. No M, floating-point, compressed, or privileged instructions.", 8, width=540)
        self.text(36, 55, "Sources: docs.riscv.org  |  github.com/riscv-non-isa/riscv-asm-manual  |  riscv-non-isa.github.io/riscv-elf-psabi-doc/", 7.7, width=540)
        self.text(36, 43, "XO project convention is marked separately from the standard ABI.  /  2026-11-11", 8, width=540)
        self.lines += ["showpage", "%%EOF"]
        return "\n".join(self.lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gs", help="Ghostscript executable")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("riscv64-quick-reference.pdf"))
    args = parser.parse_args()
    gs = args.gs or shutil.which("gs")
    if gs is None:
        candidates = sorted(glob.glob("/nix/store/*ghostscript*/bin/gs"))
        gs = candidates[0] if candidates else None
    if gs is None:
        parser.error("Ghostscript is required; run inside nix-shell -p ghostscript.")
    with tempfile.TemporaryDirectory(prefix="xo-reference-") as temp:
        source = Path(temp) / "reference.ps"
        source.write_text(Sheet().render(), encoding="ascii")
        result = subprocess.run([
            gs, "-q", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4", "-dEmbedAllFonts=true", "-dSubsetFonts=true",
            f"-sOutputFile={args.output.resolve()}",
            "-c", "<< /NeverEmbed [] >> setdistillerparams", "-f", str(source),
        ], check=True, capture_output=True, text=True)
        if "OVERFLOW:" in result.stdout:
            raise RuntimeError(result.stdout)
    print(args.output.resolve())


if __name__ == "__main__":
    main()
