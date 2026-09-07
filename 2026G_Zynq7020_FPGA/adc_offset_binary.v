`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: adc_offset_binary
// Function: Convert AD9226 12-bit offset-binary samples to signed two's
//           complement without DC tracking/removal.
// Clock domain: clk_sample.
// Mapping: 0 -> -2048, 2048 -> 0, 4095 -> 2047.
//------------------------------------------------------------------------------
module adc_offset_binary (
    input  wire                    clk_sample,
    input  wire                    rst_n,
    input  wire [11:0]             adc_raw,
    input  wire                    adc_otr,
    output reg  signed [11:0]      adc_signed,
    output reg                     adc_valid,
    output reg                     adc_otr_sync
);

    wire signed [12:0] adc_temp;
    assign adc_temp = $signed({1'b0, adc_raw}) - 13'sd2048;

    always @(posedge clk_sample) begin
        if (!rst_n) begin
            adc_signed   <= 12'sd0;
            adc_valid    <= 1'b0;
            adc_otr_sync <= 1'b0;
        end else begin
            adc_signed   <= adc_temp[11:0];
            adc_valid    <= 1'b1;
            adc_otr_sync <= adc_otr;
        end
    end

endmodule
