// 6502 FPGA Soft Processor
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2023 by Michael Kohn

module m6502
(
  output [7:0] leds,
  output [3:0] column,
  input raw_clk,
  output eeprom_cs,
  output eeprom_clk,
  output eeprom_di,
  input  eeprom_do,
  output speaker_p,
  output speaker_m,
  output ioport_0,
  input  button_reset,
  input  button_halt,
  input  button_program_select,
  input  button_0
);

// iceFUN 8x4 LEDs used for debugging.
reg [7:0] leds_value;
reg [3:0] column_value;

assign leds = leds_value;
assign column = column_value;

// Memory bus (ROM, RAM, peripherals).
reg [15:0] mem_address = 0;
reg [7:0] mem_data_in = 0;
wire [7:0] mem_data_out;
reg mem_write_enable = 0;

// Clock.
reg [21:0] count = 0;
reg [7:0] state = 0;
reg [7:0] next_state;
reg [19:0] clock_div;
reg [14:0] delay_loop;
wire clk;
assign clk = clock_div[7];

// Registers.
reg [7:0] reg_a = 0;
reg [7:0] reg_x = 0;
reg [7:0] reg_y = 0;
//reg [7:0] reg_index [1:0];
// wire [7:0] reg_x;
// wire [7:0] reg_y;
// assign reg_x = { reg_index[0] };
// assign reg_y = { reg_index[1] };

// ALU.
reg [7:0] alu_data_0;
reg [7:0] alu_data_1;
reg [2:0] alu_command;
wire [8:0] alu_result;
reg [7:0] inc_result;
reg [7:0] shift_result;
reg shift_carry;

//  Stack.
reg [7:0] sp = 8'h00;

// Program counter, instruction, effective address.
reg [15:0] pc = 0;
reg [7:0] instruction;
reg [15:0] ea = 0;
reg [2:0] address_mode;
wire [2:0] mode;
wire [2:0] operation;
assign mode = instruction[4:2];
assign operation = instruction[7:5];
reg [15:0] arg = 0;

// Flags.
wire [7:0] flags;
reg flag_negative = 0;
reg flag_overflow = 0;
reg flag_break = 0;
reg flag_decimal = 0;
reg flag_interrupt = 0;
reg flag_carry = 0;
reg flag_zero = 0;
assign flags[7] = flag_negative;
assign flags[6] = flag_overflow;
assign flags[5] = 0;
assign flags[4] = flag_break;
assign flags[3] = flag_decimal;
assign flags[2] = flag_interrupt;
assign flags[1] = flag_zero;
assign flags[0] = flag_carry;

// Eeprom.
reg  [8:0] eeprom_count;
wire [7:0] eeprom_data_out;
reg [10:0] eeprom_address;
reg eeprom_strobe = 0;
wire eeprom_ready;

// Debug.
//reg [7:0] debug_0 = 0;
//reg [7:0] debug_1 = 0;
//reg [7:0] debug_2 = 0;
//reg [7:0] debug_3;

// This block is simply a clock divider for the raw_clk.
always @(posedge raw_clk) begin
  count <= count + 1;
  clock_div <= clock_div + 1;
end

// This block simply drives the 8x4 LEDs.
always @(posedge raw_clk) begin
  case (count[9:7])
    3'b000: begin column_value <= 4'b0111; leds_value <= ~reg_a; end
    //3'b000: begin column_value <= 4'b0111; leds_value <= ~arg[7:0]; end
    //3'b000: begin column_value <= 4'b0111; leds_value <= ~ea[7:0]; end

//    3'b010: begin column_value <= 4'b1011; leds_value <= ~flags[7:0]; end
    3'b010: begin column_value <= 4'b1011; leds_value <= ~reg_x; end
    //3'b010: begin column_value <= 4'b1011; leds_value <= ~instruction; end

    3'b100: begin column_value <= 4'b1101; leds_value <= ~pc[7:0]; end
    3'b110: begin column_value <= 4'b1110; leds_value <= ~pc[15:8]; end
//    3'b110: begin column_value <= 4'b1110; leds_value <= ~state; end
    default: begin column_value <= 4'b1111; leds_value <= 8'hff; end
  endcase
end

parameter STATE_RESET =          0;
parameter STATE_DELAY_LOOP =     1;
parameter STATE_FETCH_OP_0 =     2;
parameter STATE_FETCH_OP_1 =     3;
parameter STATE_START =          4;
parameter STATE_FETCH_LO_0 =     5;
parameter STATE_FETCH_LO_1 =     6;
parameter STATE_FETCH_HI_0 =     7;
parameter STATE_FETCH_HI_1 =     8;
parameter STATE_FETCH_IM_0 =     9;
parameter STATE_FETCH_IM_1 =     10;
parameter STATE_FETCH_IND_LO_0 = 11;
parameter STATE_FETCH_IND_LO_1 = 12;
parameter STATE_FETCH_IND_HI_0 = 13;
parameter STATE_FETCH_IND_HI_1 = 14;
parameter STATE_FETCH_ABS_0 =    15;
parameter STATE_FETCH_ABS_1 =    16;
parameter STATE_EXECUTE =        17;
parameter STATE_WRITEBACK_A =    18;
parameter STATE_WRITEBACK_X =    19;
parameter STATE_WRITEBACK_Y =    20;
parameter STATE_STORE_ARG_0 =    21;
parameter STATE_STORE_ARG_1 =    22;
parameter STATE_FINISH_CALL =    23;
parameter STATE_FINISH_PUSH =    24;
parameter STATE_FINISH_POP  =    25;
parameter STATE_POP_SR_0 =       26;
parameter STATE_POP_SR_1 =       27;
parameter STATE_POP_PC_LO_0 =    28;
parameter STATE_POP_PC_LO_1 =    29;
parameter STATE_POP_PC_HI_0 =    30;
parameter STATE_POP_PC_HI_1 =    31;
parameter STATE_PUSH_PC_LO_0 =   32;
parameter STATE_PUSH_PC_LO_1 =   33;
parameter STATE_PUSH_PC_HI_0 =   34;
parameter STATE_PUSH_PC_HI_1 =   35;
parameter STATE_HALTED =       8'h80;
parameter STATE_ERROR =        8'h81;
parameter STATE_EEPROM_START = 8'h82;
parameter STATE_EEPROM_READ =  8'h83;
parameter STATE_EEPROM_WAIT =  8'h84;
parameter STATE_EEPROM_WRITE = 8'h85;
parameter STATE_EEPROM_DONE =  8'h86;

// Instruction format: aaabbbcc

// c = 01 aaa = op, bbb = mode
parameter OP_ORA = 3'b000;
parameter OP_AND = 3'b001;
parameter OP_EOR = 3'b010;
parameter OP_ADC = 3'b011;
parameter OP_STA = 3'b100;
parameter OP_LDA = 3'b101;
parameter OP_CMP = 3'b110;
parameter OP_SBC = 3'b111;

parameter MODE_C01_INDIRECT_ZP_X = 3'b000; // (ZP, X)
parameter MODE_C01_ZP            = 3'b001; // ZP
parameter MODE_C01_IMMEDIATE     = 3'b010; // #IMMEDIATE
parameter MODE_C01_ABSOLUTE      = 3'b011; // ABSOLUTE
parameter MODE_C01_INDIRECT_ZP_Y = 3'b100; // (ZP), Y
parameter MODE_C01_ZP_X          = 3'b101; // ZP, X
parameter MODE_C01_ABSOLUTE_Y    = 3'b110; // ABSOLUTE, Y
parameter MODE_C01_ABSOLUTE_X    = 3'b111; // ABSOLUTE, X

// c = 10 aaa = op, bbb = mode

parameter OP_ASL = 3'b000;
parameter OP_ROL = 3'b001;
parameter OP_LSR = 3'b010;
parameter OP_ROR = 3'b011;
parameter OP_STX = 3'b100;
parameter OP_LDX = 3'b101;
parameter OP_DEC = 3'b110;
parameter OP_INC = 3'b111;

parameter MODE_C10_IMMEDIATE  = 3'b000; // #IMMEDIATE
parameter MODE_C10_ZP         = 3'b001; // ZP
parameter MODE_C10_A          = 3'b010; // A
parameter MODE_C10_ABSOLUTE   = 3'b011; // ABSOLUTE
parameter MODE_C10_ZP_X       = 3'b101; // ZP, X
parameter MODE_C10_ABSOLUTE_X = 3'b111; // ABSOLUTE, X

// c = 00 aaa = op, bbb = mode

parameter OP_BIT     = 3'b001;
parameter OP_JMP     = 3'b010; // jmp ADDRESS
parameter OP_JMP_IND = 3'b011; // jmp (ADDRESS)
parameter OP_STY     = 3'b100;
parameter OP_LDY     = 3'b101;
parameter OP_CPY     = 3'b110;
parameter OP_CPX     = 3'b111;

parameter MODE_C00_IMMEDIATE  = 3'b000; // #IMMEDIATE
parameter MODE_C00_ZP         = 3'b001; // ZP
parameter MODE_C00_ABSOLUTE   = 3'b011; // ABSOLUTE
parameter MODE_C00_ZP_X       = 3'b101; // ZP, X
parameter MODE_C00_ABSOLUTE_X = 3'b101; // ABSOLUTE, X

// c = 0, b = 4
parameter OP_BPL = 3'b000; // _100_00
parameter OP_BMI = 3'b001; // _100_00
parameter OP_BVC = 3'b010; // _100_00
parameter OP_BVS = 3'b011; // _100_00
parameter OP_BCC = 3'b100; // _100_00
parameter OP_BCS = 3'b101; // _100_00
parameter OP_BNE = 3'b110; // _100_00
parameter OP_BEQ = 3'b111; // _100_00

// c = 0, b = 0.
parameter OP_BRK = 3'b000; // _000_00;
parameter OP_JSR = 3'b001; // _000_00;
parameter OP_RTI = 3'b010; // _000_00;
parameter OP_RTS = 3'b011; // _000_00;

// c = 0, b = 2.
parameter OP_PHP = 3'b000; // _010_00;
parameter OP_PLP = 3'b001; // _010_00;
parameter OP_PHA = 3'b010; // _010_00;
parameter OP_PLA = 3'b011; // _010_00;
parameter OP_DEY = 3'b100; // _010_00;
parameter OP_TAY = 3'b101; // _010_00;
parameter OP_INY = 3'b110; // _010_00;
parameter OP_INX = 3'b111; // _010_00;

// c = 0, b = 3.
parameter OP_CLC = 3'b000; // _110_00;
parameter OP_SEC = 3'b001; // _110_00;
parameter OP_CLI = 3'b010; // _110_00;
parameter OP_SEI = 3'b011; // _110_00;
parameter OP_TYA = 3'b100; // _110_00;
parameter OP_CLV = 3'b101; // _110_00;
parameter OP_CLD = 3'b110; // _110_00;
parameter OP_SED = 3'b111; // _110_00;

// c = 2, b = 3.
parameter OP_TXS = 3'b100; // _110_10;
parameter OP_TSX = 3'b101; // _110_10;

// c = 2, b = 2.
parameter OP_TXA = 3'b100; // _010_10;
parameter OP_TAX = 3'b101; // _010_10;
parameter OP_DEX = 3'b110; // _010_10;
parameter OP_NOP = 3'b111; // _010_10;

parameter OPCODE_PHP = 8'h08 >> 2; // 000_010_00
parameter OPCODE_PLP = 8'h28 >> 2; // 001_010_00
parameter OPCODE_PHA = 8'h48 >> 2; // 010_010_00
parameter OPCODE_PLA = 8'h68 >> 2; // 011_010_00
parameter OPCODE_DEY = 8'h88 >> 2; // 100_010_00
parameter OPCODE_TAY = 8'ha8 >> 2; // 101_010_00
parameter OPCODE_INY = 8'hc8 >> 2; // 110_010_00
parameter OPCODE_INX = 8'he8 >> 2; // 111_010_00

parameter OPCODE_CLC = 8'h18 >> 2; // 000_110_00
parameter OPCODE_SEC = 8'h38 >> 2; // 001_110_00
parameter OPCODE_CLI = 8'h58 >> 2; // 010_110_00
parameter OPCODE_SEI = 8'h78 >> 2; // 011_110_00
parameter OPCODE_TYA = 8'h98 >> 2; // 100_110_00
parameter OPCODE_CLV = 8'hb8 >> 2; // 101_110_00
parameter OPCODE_CLD = 8'hd8 >> 2; // 110_110_00
parameter OPCODE_SED = 8'hf8 >> 2; // 111_110_00

parameter OPCODE_TXA = 8'h8a >> 2; // 100_010_10
parameter OPCODE_TXS = 8'h9a >> 2; // 100_110_10
parameter OPCODE_TAX = 8'haa >> 2; // 101_010_10
parameter OPCODE_TSX = 8'hba >> 2; // 101_110_10
parameter OPCODE_DEX = 8'hca >> 2; // 110_010_10
parameter OPCODE_NOP = 8'hea >> 2; // 111_010_10

parameter ADDRESS_MODE_NONE =       0;
parameter ADDRESS_MODE_ABSOLUTE =   1;
parameter ADDRESS_MODE_ABSOLUTE_X = 2;
parameter ADDRESS_MODE_ABSOLUTE_Y = 3;
parameter ADDRESS_MODE_INDIRECT_X = 4;
parameter ADDRESS_MODE_INDIRECT_Y = 5;
parameter ADDRESS_MODE_ABSOLUTE16 = 6;
parameter ADDRESS_MODE_JSR =        7;

// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin
  case (state)
    STATE_RESET:
      begin
        // FIXME: Set to appropriate value later and add 0x100.
        sp <= 8'h0f;
        flag_negative <= 0;
        flag_overflow <= 0;
        flag_break <= 0;
        flag_decimal <= 0;
        flag_interrupt <= 0;
        flag_carry <= 0;
        flag_zero <= 0;
        mem_address <= 0;
        mem_write_enable <= 0;
        mem_data_in <= 0;
        instruction <= 0;
        delay_loop = 12000;
        eeprom_strobe <= 0;
        reg_a <= 0;
        reg_x <= 0;
        reg_y <= 0;
        next_state <= STATE_DELAY_LOOP;
        //next_state <= STATE_FETCH_OP_0;
      end
    STATE_DELAY_LOOP:
      begin
        // This is probably not needed. The chip starts up fine without it.
        if (delay_loop == 0) begin

          // If button is not pushed, start rom.v code otherwise use EEPROM.
          //if (button_program_select)
            pc <= 16'h4000;
          //else
          //  pc <= 0;

          //next_state <= STATE_EEPROM_START;
          next_state <= STATE_FETCH_OP_0;
        end else begin
          delay_loop <= delay_loop - 1;
        end
      end
    STATE_FETCH_OP_0:
      begin
        mem_address <= pc;
        mem_write_enable <= 1'b0;
        next_state <= STATE_FETCH_OP_1;
      end
    STATE_FETCH_OP_1:
      begin
        instruction <= mem_data_out;
        next_state <= STATE_START;
        pc <= pc + 1;
      end
    STATE_START:
      begin
        case (instruction[1:0])
          2'b00:
            begin
              case (mode)
                3'b000:
                  begin
                    case (operation)
                      OP_BRK:
                        begin
                          next_state <= STATE_HALTED;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                      OP_RTI:
                        begin
                          next_state <= STATE_POP_SR_0;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                      OP_RTS:
                        begin
                          next_state <= STATE_FETCH_LO_0;
                          address_mode <= ADDRESS_MODE_JSR;
                        end
                      OP_JSR:
                        begin
                          next_state <= STATE_FETCH_LO_0;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                      OP_JMP:
                        begin
                          next_state <= STATE_FETCH_LO_0;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                      OP_JMP_IND:
                        begin
                          next_state <= STATE_FETCH_LO_0;
                          address_mode <= ADDRESS_MODE_ABSOLUTE16;
                        end
                      default:
                        begin
                          next_state <= STATE_EXECUTE;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                    endcase
                  end
                3'b010:
                  begin
                    address_mode <= ADDRESS_MODE_NONE;
                    next_state <= STATE_EXECUTE;
                  end
                3'b110:
                  begin
                    address_mode <= ADDRESS_MODE_NONE;
                    next_state <= STATE_EXECUTE;
                  end
                3'b100:
                  begin
                    case (operation)
                      OP_BNE:
                        begin
                          next_state <= STATE_EXECUTE;
                          address_mode <= ADDRESS_MODE_NONE;
                        end
                    endcase
                  end
                MODE_C00_IMMEDIATE:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                    address_mode <= ADDRESS_MODE_NONE;
                  end
                MODE_C00_ZP:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                    address_mode <= ADDRESS_MODE_ABSOLUTE;
                  end
                MODE_C00_ABSOLUTE:
                  begin
                    next_state <= STATE_FETCH_LO_0;
                    address_mode <= ADDRESS_MODE_ABSOLUTE;
                  end
                MODE_C00_ZP_X:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                    address_mode <= ADDRESS_MODE_ABSOLUTE_X;
                  end
                MODE_C00_ABSOLUTE_X:
                  begin
                    next_state <= STATE_FETCH_LO_0;
                    address_mode <= ADDRESS_MODE_ABSOLUTE_X;
                  end
              endcase
            end
          2'b01:
            begin
              if (operation == OP_STA) begin
                next_state <= STATE_EXECUTE;
              end else begin
                case (mode)
                  MODE_C01_INDIRECT_ZP_X:
                    begin
                      next_state <= STATE_FETCH_IM_0;
                      address_mode <= ADDRESS_MODE_INDIRECT_X;
                    end
                  MODE_C01_ZP:
                    begin
                      next_state <= STATE_FETCH_IM_0;
                      address_mode <= ADDRESS_MODE_ABSOLUTE;
                    end
                  MODE_C01_IMMEDIATE:
                    begin
                      next_state <= STATE_FETCH_IM_0;
                      address_mode <= ADDRESS_MODE_NONE;
                    end
                  MODE_C01_ABSOLUTE:
                    begin
                      next_state <= STATE_FETCH_LO_0;
                      address_mode <= ADDRESS_MODE_ABSOLUTE;
                    end
                  MODE_C01_INDIRECT_ZP_Y:
                    begin
                      next_state <= STATE_FETCH_IM_0;
                      address_mode <= ADDRESS_MODE_INDIRECT_Y;
                    end
                  MODE_C01_ZP_X:
                    begin
                      next_state <= STATE_FETCH_IM_0;
                      address_mode <= ADDRESS_MODE_ABSOLUTE_X;
                    end
                  MODE_C01_ABSOLUTE_Y:
                    begin
                      next_state <= STATE_FETCH_LO_0;
                      address_mode <= ADDRESS_MODE_ABSOLUTE_Y;
                    end
                  MODE_C01_ABSOLUTE_X:
                    begin
                      next_state <= STATE_FETCH_LO_0;
                      address_mode <= ADDRESS_MODE_ABSOLUTE_X;
                    end
                  default:
                    begin
                      next_state <= STATE_EXECUTE;
                    end
                endcase
              end
            end
          2'b10:
            begin
              case (mode)
                MODE_C10_IMMEDIATE:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                  end
                MODE_C10_ZP:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                  end
                MODE_C10_A:
                  begin
                    next_state <= STATE_EXECUTE;
                  end
                MODE_C10_ABSOLUTE:
                  begin
                    next_state <= STATE_FETCH_LO_0;
                  end
                MODE_C10_ZP_X:
                  begin
                    next_state <= STATE_FETCH_IM_0;
                  end
                MODE_C10_ABSOLUTE_X:
                  begin
                    next_state <= STATE_FETCH_LO_0;
                  end
                default:
                  begin
                    next_state <= STATE_EXECUTE;
                  end
              endcase
            end
          2'b11:
            begin
              next_state <= STATE_ERROR;
            end
        endcase
      end
    STATE_FETCH_LO_0:
      begin
        mem_address <= pc;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_LO_1;
      end
    STATE_FETCH_LO_1:
      begin
        arg[7:0] <= mem_data_out;
        next_state <= STATE_FETCH_HI_0;
        pc <= pc + 1;
      end
    STATE_FETCH_HI_0:
      begin
        mem_address <= pc;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_HI_1;
      end
    STATE_FETCH_HI_1:
      begin
        case (address_mode)
          ADDRESS_MODE_ABSOLUTE:
            begin
              ea[15:0] <= { mem_data_out, arg[7:0] };
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_ABSOLUTE_X:
            begin
              ea[15:0] <= { mem_data_out, arg[7:0] } + reg_x;
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_ABSOLUTE_Y:
            begin
              ea[15:0] <= { mem_data_out, arg[7:0] } + reg_y;
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_ABSOLUTE16:
            begin
              ea[15:0] <= { mem_data_out, arg[7:0] };
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_JSR:
            begin
              arg[15:8] <= mem_data_out;
              next_state <= STATE_PUSH_PC_LO_0;
            end
          default:
            begin
              arg[15:8] <= mem_data_out;
              next_state <= STATE_EXECUTE;
            end
        endcase

        pc <= pc + 1;
      end
    STATE_FETCH_IM_0:
      begin
        mem_address <= pc;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_IM_1;
      end
    STATE_FETCH_IM_1:
      begin
        arg[15:8] <= 0;
        arg[7:0] <= mem_data_out;
        ea[15:8] <= 0;

        case (address_mode)
          ADDRESS_MODE_ABSOLUTE:
            begin
              ea[7:0] <= mem_data_out;
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_ABSOLUTE_X:
            begin
              ea[7:0] <= mem_data_out + reg_x;
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_ABSOLUTE_Y:
            begin
              ea[7:0] <= mem_data_out + reg_y;
              next_state <= STATE_FETCH_ABS_0;
            end
          ADDRESS_MODE_INDIRECT_X:
            begin
              ea[7:0] <= mem_data_out + reg_x;
              next_state <= STATE_FETCH_IND_LO_0;
            end
          ADDRESS_MODE_INDIRECT_Y:
            begin
              ea[7:0] <= mem_data_out;
              next_state <= STATE_FETCH_IND_LO_0;
            end
          default:
            begin
              next_state <= STATE_EXECUTE;
            end
        endcase

        pc <= pc + 1;
      end
    STATE_FETCH_IND_LO_0:
      begin
        mem_address <= ea;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_IND_LO_1;
      end
    STATE_FETCH_IND_LO_1:
      begin
        arg[15:8] <= 0;
        arg[7:0] <= mem_data_out;
        next_state <= STATE_FETCH_IND_HI_0;
      end
    STATE_FETCH_IND_HI_0:
      begin
        mem_address <= ea + 1;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_IND_HI_1;
      end
    STATE_FETCH_IND_HI_1:
      begin
        if (address_mode == ADDRESS_MODE_INDIRECT_Y)
          ea[7:0] <= { mem_data_out, arg[0:7] } + reg_y;
        else
          ea[15:8] <= mem_data_out;
          ea[7:0] <= arg[0:7];

        next_state <= STATE_FETCH_ABS_0;
      end
    STATE_FETCH_ABS_0:
      begin
        mem_address <= ea;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_ABS_1;
      end
    STATE_FETCH_ABS_1:
      begin
        arg[15:8] <= 0;
        arg[7:0] <= mem_data_out;
        next_state <= STATE_EXECUTE;
      end
    STATE_EXECUTE:
      begin
        case (instruction[1:0])
          2'b00:
            begin
              case (instruction[7:2])
                OPCODE_CLC: flag_carry <= 0;
                OPCODE_SEC: flag_carry <= 1;
                OPCODE_CLI: flag_interrupt <= 0;
                OPCODE_SEI: flag_interrupt <= 1;
                OPCODE_TYA: reg_a <= reg_y;
                OPCODE_CLV: flag_overflow <= 0;
                OPCODE_CLD: flag_decimal <= 0;
                OPCODE_SED: flag_decimal <= 1;
                OPCODE_PHP:
                  begin
                    mem_address <= sp;
                    mem_data_in <= flags;
                    mem_write_enable <= 1;
                    sp <= sp - 1;
                  end
                OPCODE_PLP:
                  begin
                    mem_address <= sp + 1;
                    mem_write_enable <= 0;
                    sp <= sp + 1;
                  end
                OPCODE_PHA:
                  begin
                    mem_address <= sp;
                    mem_data_in <= reg_a;
                    mem_write_enable <= 1;
                    sp <= sp - 1;
                  end
                OPCODE_PLA:
                  begin
                    mem_address <= sp + 1;
                    mem_write_enable <= 0;
                    sp <= sp + 1;
                  end
                OPCODE_DEY: reg_y <= reg_y - 1;
                OPCODE_TAY: reg_y <= reg_a;
                OPCODE_INY: reg_y <= reg_y + 1;
                OPCODE_INX: reg_x <= reg_x + 1;
                default:
                  begin
                    case (operation)
                      OP_JMP:
                        begin
                          pc <= mem_address;
                          next_state <= STATE_FETCH_OP_0;
                        end
                      OP_JMP_IND: pc <= arg;
                      OP_STY:     arg <= reg_y;
                      OP_LDY:     reg_y <= arg[7:0];
                      OP_CPY:     arg <= { flag_carry, reg_y } - arg;
                      OP_CPX:     arg <= { flag_carry, reg_x } - arg;
                    endcase
                  end
              endcase

              if (mode == 3'b110 || mode == 3'b010)
                if (instruction[7:2] == OPCODE_PHP ||
                    instruction[7:2] == OPCODE_PHA)
                  next_state <= STATE_FINISH_PUSH;
                else if (instruction[7:2] == OPCODE_PLP ||
                         instruction[7:2] == OPCODE_PLA)
                  next_state <= STATE_FINISH_POP;
                else
                  next_state <= STATE_FETCH_OP_0;
              else if (operation == OP_STY)
                next_state <= STATE_STORE_ARG_0;
              else if (operation == OP_CPY || operation == OP_INY ||
                       operation == OP_DEY)
                next_state <= STATE_WRITEBACK_Y;
              else if (operation == OP_CPX || operation == OP_INX)
                next_state <= STATE_WRITEBACK_X;
            end
          2'b01:
            begin
              case (operation)
                OP_ORA: arg <= reg_a | arg;
                OP_AND: arg <= reg_a & arg;
                OP_EOR: arg <= reg_a ^ arg;
                OP_ADC: arg <= reg_a + arg + flag_carry;
                OP_STA: arg <= reg_a;
                OP_LDA: reg_a <= arg;
                OP_CMP: arg <= { flag_carry, reg_a } - arg;
                OP_SBC: arg <= { flag_carry, reg_a } - arg;
              endcase

              if (operation == OP_STA)
                next_state <= STATE_STORE_ARG_0;
              else
                next_state <= STATE_WRITEBACK_A;
            end
          2'b10:
            begin
              if (mode == 3'b010 || mode == 3'b110) begin
                case (instruction[7:2])
                  OPCODE_TXA:
                    begin
                      reg_a <= reg_x;
                      next_state <= STATE_WRITEBACK_A;
                    end
                  OPCODE_TXS:
                    begin
                      sp <= reg_x;
                      next_state <= STATE_FETCH_OP_0;
                    end
                  OPCODE_TAX:
                    begin
                      reg_x <= reg_a;
                      next_state <= STATE_WRITEBACK_A;
                    end
                  OPCODE_TSX:
                    begin
                      reg_x <= sp;
                      next_state <= STATE_WRITEBACK_X;
                    end
                  OPCODE_DEX:
                    begin
                      reg_x <= reg_x - 1;
                      next_state <= STATE_WRITEBACK_X;
                    end
                  OPCODE_NOP: next_state <= STATE_FETCH_OP_0;
                  default: next_state <= STATE_FETCH_OP_0;
                endcase
              end else begin
                case (operation)
                  OP_ASL: begin arg[7:1] <= arg[6:0]; arg[0] <= 0; flag_carry <= arg[7]; end
                  OP_ROL: begin arg[7:1] <= arg[6:0]; arg[0] <= flag_carry; flag_carry <= arg[7]; end
                  OP_LSR: begin arg[6:0] <= arg[7:1]; arg[7] <= 0; flag_carry <= arg[0]; end
                  OP_ROR: begin arg[6:0] <= arg[7:1]; arg[7] <= flag_carry; flag_carry <= arg[0]; end
                  OP_STX: arg[7:0] <= reg_x;
                  OP_LDX: reg_x <= arg[7:0];
                  OP_DEC: arg[7:0] <= arg[7:0] - 1;
                  OP_INC: arg[7:0] <= arg[7:0] + 1;
                endcase

                if (operation == OP_LDX)
                  next_state <= STATE_WRITEBACK_X;
                else if (operation == OP_STX)
                  next_state <= STATE_STORE_ARG_0;
                else
                  next_state <= STATE_FETCH_OP_0;
              end
            end
          2'b11:
            begin
              next_state <= STATE_ERROR;
            end
        endcase
      end
    STATE_WRITEBACK_A:
      begin
        flag_carry <= arg[8];
        flag_negative <= arg[7];
        flag_zero <= arg[7:0] == 0;
        if (operation != OP_CMP) reg_a <= arg[7:0];
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_WRITEBACK_X:
      begin
        if (operation != OP_DEX) flag_carry <= arg[8];
        flag_negative <= arg[7];
        flag_zero <= arg[7:0] == 0;
        if (operation != OP_CPX) reg_x <= arg[7:0];
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_WRITEBACK_Y:
      begin
        if (operation != OP_DEY) flag_carry <= arg[8];
        flag_negative <= arg[7];
        flag_zero <= arg[7:0] == 0;
        if (operation != OP_CPY) reg_y <= arg[7:0];
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_STORE_ARG_0:
      begin
        mem_address <= ea;
        mem_data_in <= arg;
        mem_write_enable <= 1;
        next_state <= STATE_STORE_ARG_1;
      end
    STATE_STORE_ARG_1:
      begin
        // Finish writeback of result to memory.
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_FINISH_PUSH:
      begin
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_FINISH_POP:
      begin
        if (instruction[7:2] == OPCODE_PLP)
          begin
            flag_negative <= mem_data_out[7];
            flag_overflow <= mem_data_out[6];
            flag_break <= mem_data_out[4];
            flag_decimal <= mem_data_out[3];
            flag_interrupt <= mem_data_out[2];
            flag_zero <= mem_data_out[1];
            flag_carry <= mem_data_out[0];
          end
        else
          reg_a <= mem_data_out;

        next_state <= STATE_FETCH_OP_0;
      end
    STATE_POP_SR_0:
      begin
        mem_address <= sp + 1;
        mem_write_enable <= 0;
        sp <= sp + 1;
      end
    STATE_POP_SR_1:
      begin
        flag_negative <= mem_data_out[7];
        flag_overflow <= mem_data_out[6];
        flag_break <= mem_data_out[4];
        flag_decimal <= mem_data_out[3];
        flag_interrupt <= mem_data_out[2];
        flag_zero <= mem_data_out[1];
        flag_carry <= mem_data_out[0];

        next_state <= STATE_POP_PC_LO_0;
      end
    STATE_POP_PC_LO_0:
      begin
        mem_address <= sp + 1;
        mem_write_enable <= 0;
        sp <= sp + 1;
      end
    STATE_POP_PC_LO_1:
      begin
        pc[7:0] <= mem_data_out;
      end
    STATE_POP_PC_HI_0:
      begin
        mem_address <= sp + 1;
        mem_write_enable <= 0;
        sp <= sp + 1;
      end
    STATE_POP_PC_HI_1:
      begin
        pc[15:8] <= mem_data_out;
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_PUSH_PC_LO_0:
      begin
        mem_address <= sp;
        mem_data_in <= pc[7:0];
        mem_write_enable <= 1;
        sp <= sp - 1;
      end
    STATE_PUSH_PC_LO_1:
      begin
        mem_write_enable <= 0;
      end
    STATE_PUSH_PC_HI_0:
      begin
        mem_address <= sp;
        mem_data_in <= pc[15:8];
        mem_write_enable <= 1;
        sp <= sp - 1;
      end
    STATE_PUSH_PC_HI_1:
      begin
        pc <= arg;
        mem_write_enable <= 0;
        next_state <= STATE_FETCH_OP_0;
      end
    STATE_HALTED:
      begin
        if (!button_halt) begin
          next_state <= STATE_FETCH_OP_0;
          flag_break <= 0;
        end else begin
          next_state <= STATE_HALTED;
          flag_break <= 1;
        end

        mem_write_enable <= 0;
      end
    STATE_ERROR:
      begin
        next_state <= STATE_ERROR;
        mem_write_enable <= 0;
      end
    STATE_EEPROM_START:
      begin
        // Initialize values for reading from SPI-like EEPROM.
        if (eeprom_ready) begin
          eeprom_count <= 0;
          next_state <= STATE_EEPROM_READ;
        end
      end
    STATE_EEPROM_READ:
      begin
        // Set the next EEPROM address to read from and strobe.
        eeprom_address <= eeprom_count;
        mem_address <= eeprom_count;
        eeprom_strobe <= 1;
        next_state <= STATE_EEPROM_WAIT;
      end
    STATE_EEPROM_WAIT:
      begin
        // Wait until 8 bits are clocked in.
        eeprom_strobe <= 0;

        if (eeprom_ready) begin
          mem_data_in <= eeprom_data_out;
          eeprom_count <= eeprom_count + 1;
          next_state <= STATE_EEPROM_WRITE;
        end
      end
    STATE_EEPROM_WRITE:
      begin
        // Write value read from EEPROM into memory.
        mem_write_enable <= 1;
        next_state <= STATE_EEPROM_DONE;
      end
    STATE_EEPROM_DONE:
      begin
        // Finish writing and read next byte if needed.
        mem_write_enable <= 0;

        if (eeprom_count == 256)
          next_state <= STATE_FETCH_OP_0;
        else
          next_state <= STATE_EEPROM_READ;
      end
  endcase
end

// On negative edge of clock, check reset and halt buttons and
// change to next state of the CPU execution state machine.
always @(negedge clk) begin
  if (!button_reset)
    state <= STATE_RESET;
  else if (!button_halt)
    state <= STATE_HALTED;
  else
    state <= next_state;
end

memory_bus memory_bus_0(
  .address      (mem_address),
  .data_in      (mem_data_in),
  .data_out     (mem_data_out),
  .write_enable (mem_write_enable),
  .clk          (clk),
  .raw_clk      (raw_clk),
  .speaker_p    (speaker_p),
  .speaker_m    (speaker_m),
  .ioport_0     (ioport_0),
  .button_0     (button_0),
  .reset        (~button_reset)
);

eeprom eeprom_0
(
  .address    (eeprom_address),
  .strobe     (eeprom_strobe),
  .raw_clk    (raw_clk),
  .eeprom_cs  (eeprom_cs),
  .eeprom_clk (eeprom_clk),
  .eeprom_di  (eeprom_di),
  .eeprom_do  (eeprom_do),
  .ready      (eeprom_ready),
  .data_out   (eeprom_data_out)
);

endmodule

