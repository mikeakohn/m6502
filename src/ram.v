// Intel 8008 FPGA Soft Processor 
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2022 by Michael Kohn

// This creates 2048 bytes of RAM on the FPGA itself.

module ram
(
  input  [8:0] address,
  input  [7:0] data_in,
  output reg [7:0] data_out,
  input write_enable,
  input clk
);

reg [7:0] memory [63:0];

always @(posedge clk) begin
  if (write_enable) begin
    memory[address] <= data_in;
  end else
    data_out <= memory[address];
end

endmodule

