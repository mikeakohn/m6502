// Intel 8008 FPGA Soft Processor 
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2022 by Michael Kohn

// This is a hardcoded program that blinks an external LED.

module rom
(
  input  [5:0] address,
  output [7:0] data_out
);

reg [7:0] data;
assign data_out = data;

always @(address) begin
  case (address)
/*
     // ad 03 40 00
     // lda 0x4004
     0: data <= 8'had;
     1: data <= 8'h04;
     2: data <= 8'h40;
     //0: data <= 8'ha9;
     //1: data <= 8'ha5;
     // brk
     3: data <= 8'h00;
     // .db 0x81
     4: data <= 8'h81;
*/
     // ldx #0xe0
     0: data <= 8'ha2;
     1: data <= 8'he0;
     // stx 0x00   100 001 10
     2: data <= 8'h86;
     3: data <= 8'h00;
     // lda 0x00
     4: data <= 8'ha5;
     5: data <= 8'h00;
     // sec
     6: data <= 8'h38;
     // php
     7: data <= 8'h08;
     // pla
     8: data <= 8'h68;
     // brk
     9: data <= 8'h00;

    default: data <= 0;
  endcase
end

endmodule

