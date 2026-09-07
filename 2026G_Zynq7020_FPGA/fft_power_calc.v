`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: fft_power_calc
// Function: Compute Re^2 + Im^2 with a ready/valid output register.
// Clock domain: clk.
// FFT inputs: sign-extended 29-bit values in signed 32-bit containers.
// Width proof: |Re|,|Im| <= 2^28; each square <= 2^56 and the sum <= 2^57,
//              safely below the 64-bit saturated output range.
//------------------------------------------------------------------------------
module fft_power_calc (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [31:0]      fft_re,
    input  wire signed [31:0]      fft_im,
    input  wire [12:0]             fft_bin,
    input  wire                    fft_last,
    input  wire                    s_valid,
    output wire                    s_ready,
    output reg  [63:0]             spectrum_power,
    output reg  [12:0]             spectrum_bin,
    output reg                     spectrum_last,
    output reg                     m_valid,
    input  wire                    m_ready
);

    wire signed [63:0] re_square_signed;
    wire signed [63:0] im_square_signed;
    wire [64:0] power_sum;

    assign re_square_signed = $signed(fft_re) * $signed(fft_re);
    assign im_square_signed = $signed(fft_im) * $signed(fft_im);
    assign power_sum = {1'b0, re_square_signed} +
                       {1'b0, im_square_signed};
    assign s_ready = !m_valid || m_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            spectrum_power <= 64'd0;
            spectrum_bin   <= 13'd0;
            spectrum_last  <= 1'b0;
            m_valid        <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                if (power_sum[64])
                    spectrum_power <= 64'hFFFF_FFFF_FFFF_FFFF;
                else
                    spectrum_power <= power_sum[63:0];
                spectrum_bin  <= fft_bin;
                spectrum_last <= fft_last;
            end
        end
    end

endmodule
