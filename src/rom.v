// 6502 FPGA Soft Processor
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2024 by Michael Kohn, Joe Davisson

// This is a hardcoded program that blinks an external LED.

module rom
(
  input [9:0] address,
//  output reg [7:0] data_out,
  output reg [7:0] data_out,
  input clk
);

//reg [7:0] data;
//assign data_out = data;

reg [7:0] memory [1023:0];

initial begin
  $readmemh("rom.txt", memory);
end

always @(posedge clk) begin
//  data_out <= memory[address[9:0]];
  data_out <= memory[address[9:0]];
end

endmodule

