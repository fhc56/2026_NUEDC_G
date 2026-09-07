`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: fir_output_scale
// Function: Scale FIR Compiler Full Precision output with symmetric rounding
//           and signed 16-bit saturation.
// Clock domain: clk.
// Input format: signed FIR_WIDTH-bit integer. For fir_decim15 the generated XCI
//               reports 30 effective bits in m_axis_data_tdata[29:0].
// SHIFT_BITS: coefficient fractional bits; default 17 for Q1.17 coefficients.
//------------------------------------------------------------------------------
module fir_output_scale #(
    parameter integer FIR_WIDTH  = 30,
    parameter integer SHIFT_BITS = 17
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [FIR_WIDTH-1:0]  fir_data,
    input  wire                         fir_valid,
    output reg  signed [15:0]           scaled_data,
    output reg                          scaled_valid
);

    reg signed [FIR_WIDTH:0] extended_value;
    reg        [FIR_WIDTH:0] magnitude;
    reg        [FIR_WIDTH:0] rounded_magnitude;
    reg signed [FIR_WIDTH:0] shifted_value;

    always @* begin
        extended_value = {fir_data[FIR_WIDTH-1], fir_data};
        if (extended_value < 0)
            magnitude = -extended_value;
        else
            magnitude = extended_value;

        if (SHIFT_BITS > 0)
            rounded_magnitude = magnitude +
                                ({{FIR_WIDTH{1'b0}}, 1'b1} << (SHIFT_BITS-1));
        else
            rounded_magnitude = magnitude;

        if (SHIFT_BITS > 0) begin
            if (extended_value < 0)
                shifted_value = -$signed(rounded_magnitude >> SHIFT_BITS);
            else
                shifted_value = $signed(rounded_magnitude >> SHIFT_BITS);
        end else begin
            shifted_value = extended_value;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            scaled_data  <= 16'sd0;
            scaled_valid <= 1'b0;
        end else begin
            scaled_valid <= fir_valid;
            if (fir_valid) begin
                if (shifted_value > 31'sd32767)
                    scaled_data <= 16'sd32767;
                else if (shifted_value < -31'sd32768)
                    scaled_data <= -16'sd32768;
                else
                    scaled_data <= shifted_value[15:0];
            end
        end
    end

endmodule
