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
  input  [10:0] address,
  output [7:0] data_out
);

reg [7:0] data;
assign data_out = data;

reg [7:0] memory [2047:0];

initial begin
  $readmemh("rom.txt", memory);
end

always @(posedge clk) begin
  data_out <= memory[address[7:0]];
end

endmodule

