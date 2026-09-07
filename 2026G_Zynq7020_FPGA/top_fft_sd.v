`timescale 1ns / 1ps

module top_fft_sd (

    //==============================
    // Zynq PS DDR
    //==============================

    inout wire [14:0] DDR_addr,
    inout wire [2:0]  DDR_ba,
    inout wire        DDR_cas_n,
    inout wire        DDR_ck_n,
    inout wire        DDR_ck_p,
    inout wire        DDR_cke,
    inout wire        DDR_cs_n,
    inout wire [3:0]  DDR_dm,
    inout wire [31:0] DDR_dq,
    inout wire [3:0]  DDR_dqs_n,
    inout wire [3:0]  DDR_dqs_p,
    inout wire        DDR_odt,
    inout wire        DDR_ras_n,
    inout wire        DDR_reset_n,
    inout wire        DDR_we_n,


    //==============================
    // Zynq FIXED IO
    //==============================

    inout wire        FIXED_IO_ddr_vrn,
    inout wire        FIXED_IO_ddr_vrp,
    inout wire [53:0] FIXED_IO_mio,
    inout wire        FIXED_IO_ps_clk,
    inout wire        FIXED_IO_ps_porb,
    inout wire        FIXED_IO_ps_srstb,


    //==============================
    // PL IO
    //==============================

    input wire        sys_clk_50m,
    input wire        rst_n,

    output wire       ad_clk,
    input wire [11:0] ad_data_in,
    input wire        ad_otr_in,

    output wire       uart_tx
);



//////////////////////////////////////////////////////
// ZYNQ PS
//////////////////////////////////////////////////////

system_wrapper u_system_wrapper (

    .DDR_addr          (DDR_addr),
    .DDR_ba            (DDR_ba),
    .DDR_cas_n         (DDR_cas_n),
    .DDR_ck_n          (DDR_ck_n),
    .DDR_ck_p          (DDR_ck_p),
    .DDR_cke           (DDR_cke),
    .DDR_cs_n          (DDR_cs_n),
    .DDR_dm            (DDR_dm),
    .DDR_dq            (DDR_dq),
    .DDR_dqs_n         (DDR_dqs_n),
    .DDR_dqs_p         (DDR_dqs_p),
    .DDR_odt           (DDR_odt),
    .DDR_ras_n         (DDR_ras_n),
    .DDR_reset_n       (DDR_reset_n),
    .DDR_we_n          (DDR_we_n),

    .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
    .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
    .FIXED_IO_mio      (FIXED_IO_mio),
    .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
    .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb)

);



//////////////////////////////////////////////////////
// FFT PL LOGIC
//////////////////////////////////////////////////////

fft_pl_top u_fft_pl_top (

    .sys_clk_50m(sys_clk_50m),

    .rst_n(rst_n),

    .ad_clk(ad_clk),

    .ad_data_in(ad_data_in),

    .ad_otr_in(ad_otr_in),

    .uart_tx(uart_tx)

);


endmodule
