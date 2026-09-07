`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: adc_overrange_frame
// Function: Sticky OTR capture for the current FFT frame. At frame_done the
//           completed-frame value is published for one full following frame.
// Clock domain: clk.
//------------------------------------------------------------------------------
module adc_overrange_frame (
    input  wire clk,
    input  wire rst_n,
    input  wire adc_otr,
    input  wire frame_done,
    output reg  overrange_frame
);

    reg overrange_accumulator;

    always @(posedge clk) begin
        if (!rst_n) begin
            overrange_accumulator <= 1'b0;
            overrange_frame <= 1'b0;
        end else if (frame_done) begin
            overrange_frame <= overrange_accumulator | adc_otr;
            overrange_accumulator <= 1'b0;
        end else if (adc_otr) begin
            overrange_accumulator <= 1'b1;
        end
    end

endmodule
