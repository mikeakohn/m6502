Soft Core 6502
==============

This is a 6502 CPU implemented in an FPGA.

This project has been replaced with this:

https://www.mikekohn.net/micro/w65c832_fpga.php

I'll probably delete this from github since it's not complete anyway
and the W65C832 can run the 6502 code as is.

Registers
=========

* A (accumulator)
* X
* Y

There's also
* SP
* PC

Flags
=====
* N negative (set if bit 7 of the result is set)
* V overflow
* ignored
* break
* D decimal
* I interrupt disable
* Z zero     (set if ALU result is 0)
* C carry    (set if ALU result requires bit 8)

Instructions
============

From https://llx.com/Neil/a2/opcodes.html

Bit structure is:

    aaabbbcc

cc = 01
-------

|aaa|opcode|
|---|------|
|000|ora
|001|and
|010|eor
|011|adc
|100|sta
|101|lda
|110|cmp
|111|sbc

|bbb|addressing mode|
|---|---------------|
|000|(zero page, X)
|001|zero page
|010|immediate
|011|absolute
|100|(zero page), Y
|101|zero page, X
|110|absolute, Y
|111|absolute, X

cc = 10
-------

|aaa|opcode|
|---|------|
|000|asl
|001|rol
|010|lsr
|011|ror
|100|stx
|101|ldx
|110|dec
|111|inc

|bbb|addressing mode|
|---|---------------|
|000|immediate
|001|zero page
|010|accumulator
|011|absolute
|100|
|101|zero page, X
|110|
|111|absolute, X

cc = 00
-------

|aaa|opcode|
|---|------|
|000|
|001|bit
|010|jmp
|011|jmp (abs)
|100|sty
|101|ldy
|110|cpy
|111|cpx

|bbb|addressing mode|
|---|---------------|
|000|immediate
|001|zero page
|010|
|011|absolute
|100|
|101|zero page, X
|110|
|111|absolute, X

Branches have the format xxy10000

|xx|flag|
|--|---------------|
|00|negative
|01|overflow
|10|carry
|11|carry

Other Instructions
------------------

brk 0x00
jsr 0x20
rti 0x40
rts 0x60

php 0x08
plp 0x28
pha 0x48
pla 0x68
dey 0x88
tey 0xa8
iny 0xc8
inx 0xe8

clc 0x18
sec 0x38
cli 0x58
sei 0x78
tya 0x98
clv 0xb8
cld 0xd8
sed 0xf8

txa 0x8a
txs 0x9a
tax 0xaa
tsx 0xba
dex 0xca
nop 0xea

Memory Map
----------

This implementation of the Intel 8008 has 4 banks of memory.

* Bank 0: RAM (256 bytes)
* Bank 1: ROM (An LED blink program from blink.asm)
* Bank 2: Peripherals
* Bank 3: Empty

On start-up by default, the chip will load a program from a AT93C86A
2kB EEPROM with a 3-Wire (SPI-like) interface but wll run the code
from the ROM. To start the program loaded to RAM, the program select
button needs to be held down while the chip is resetting.

The peripherals area contain the following:

* 0x8000: input from push button
* 0x8008: ioport0 output (in my test case only 1 pin is connected)
* 0x8009: MIDI note value (60-96) to play a tone on the speaker or 0 to stop

