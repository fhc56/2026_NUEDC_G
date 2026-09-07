`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: ad9226_clock_capture
// Function:
//   Preserve the existing AD9226 physical clock interface while using a
//   dedicated 0-degree forwarded clock and 180-degree internal sample clock.
// Clock input: 50 MHz sys_clk.
// Clock outputs: 60 MHz ad_clk through ODDR; 60 MHz clk_60m_core at 180 degrees.
// Reset: asynchronous external active-low; downstream reset is qualified by
//        MMCM lock in top_fft_g.
//------------------------------------------------------------------------------
module ad9226_clock_capture (
    input  wire sys_clk,
    input  wire rst_n,
    output wire ad_clk,
    output wire clk_60m_core,
    output wire locked
);

    wire clk_60m_forward;
    wire clk_60m_sample;

    clk_wiz_fft_g u_clk_wiz_fft_g (
        .clk_in1  (sys_clk),
        .resetn   (rst_n),
        .clk_out1 (clk_60m_forward),
        .clk_out2 (clk_60m_sample),
        .locked   (locked)
    );

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_oddr_ad_clk (
        .Q  (ad_clk),
        .C  (clk_60m_forward),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (~locked),
        .S  (1'b0)
    );

    assign clk_60m_core = clk_60m_sample;

endmodule
