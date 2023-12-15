// Intel 8008 FPGA Soft Processor 
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2022 by Michael Kohn

// This creates 16 bytes of RAM on the FPGA itself.

module ram
(
  input  [10:0] address,
  input  [7:0] data_in,
  output [7:0] data_out,
  input write_enable,
  input clk
);

reg [7:0] storage [2047:0];

always @(posedge clk) begin
  if (write_enable) begin
    storage[address[2047:0]] <= data_in;
  end else
    data_out <= storage[address];
end

endmodule

