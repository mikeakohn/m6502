
PROGRAM=m6502
SOURCE= \
  src/$(PROGRAM).v \
  src/eeprom.v \
  src/memory_bus.v \
  src/peripherals.v \
  src/ram.v \
  src/rom.v

default:
	yosys -q -p "synth_ice40 -top $(PROGRAM) -json $(PROGRAM).json" $(SOURCE)
	nextpnr-ice40 -r --hx8k --json $(PROGRAM).json --package cb132 --asc $(PROGRAM).asc --opt-timing --pcf icefun.pcf
	icepack $(PROGRAM).asc $(PROGRAM).bin

program:
	iceFUNprog $(PROGRAM).bin

.PHONY: test
test:
	naken_asm -l -type bin -o simple.bin test/simple.asm
	#naken_asm -l -type bin -o blink.bin test/blink.asm

clean:
	@rm -f $(PROGRAM).bin $(PROGRAM).json $(PROGRAM).asc *.lst
	@rm -f blink.bin test_alu.bin test_shift.bin test_subroutine.bin
	@rm -f button.bin
	@echo "Clean!"

