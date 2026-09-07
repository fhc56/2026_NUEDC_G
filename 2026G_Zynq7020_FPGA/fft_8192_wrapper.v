`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: fft_8192_wrapper
// Function:
//   AXI4-Stream wrapper around Vivado 2018.3 xfft_8192. It sends one forward
//   transform configuration after reset, creates TLAST from accepted samples,
//   extracts the verified fixed-point output fields, and numbers natural-order
//   output bins.
//
// Clock domain: clk_60m only.
// Input format:  signed 16-bit real samples; imaginary input is zero.
// IP input bus:  [15:0] real, [31:16] imaginary (verified from xfft_8192.veo).
// IP output bus: two 32-bit lanes (verified from xfft_8192.veo).
// Effective FFT output: signed 29-bit per lane for unscaled 8192-point FFT,
//   because 16 input bits + log2(8192)=13 growth bits.
//------------------------------------------------------------------------------
module fft_8192_wrapper (
    input  wire                    clk_60m,
    input  wire                    rst_n,

    input  wire signed [15:0]      sample_in,
    input  wire                    sample_valid,
    output wire                    sample_ready,

    output wire signed [31:0]      fft_re,
    output wire signed [31:0]      fft_im,
    output wire [12:0]             fft_bin,
    output wire                    fft_valid,
    input  wire                    fft_ready,
    output wire                    fft_last,
    output wire                    frame_done,

    output wire                    event_tlast_unexpected,
    output wire                    event_tlast_missing,
    output wire                    event_status_channel_halt,
    output wire                    event_data_in_channel_halt,
    output wire                    event_data_out_channel_halt
);

    reg         config_valid;
    reg         config_done;
    wire        config_ready;
    wire [7:0]  config_data;

    reg  [12:0] input_count;
    reg  [12:0] output_bin_count;

    wire [31:0] fft_input_data;
    wire        fft_input_valid;
    wire        fft_input_ready;
    wire        fft_input_last;

    wire [63:0] fft_output_data;
    wire        fft_output_valid;
    wire        fft_output_last;
    wire        fft_output_fire;

    wire        event_frame_started;

    assign config_data = 8'b0000_0001; // bit 0: 1 = forward transform

    always @(posedge clk_60m) begin
        if (!rst_n) begin
            config_valid <= 1'b0;
            config_done  <= 1'b0;
        end else if (!config_done) begin
            config_valid <= 1'b1;
            if (config_valid && config_ready) begin
                config_valid <= 1'b0;
                config_done  <= 1'b1;
            end
        end else begin
            config_valid <= 1'b0;
        end
    end

    assign fft_input_data  = {16'sd0, sample_in};
    assign fft_input_valid = sample_valid && config_done;
    assign sample_ready    = fft_input_ready && config_done;
    assign fft_input_last  = (input_count == 13'd8191);

    always @(posedge clk_60m) begin
        if (!rst_n) begin
            input_count <= 13'd0;
        end else if (fft_input_valid && fft_input_ready) begin
            if (input_count == 13'd8191)
                input_count <= 13'd0;
            else
                input_count <= input_count + 13'd1;
        end
    end

    // Verified packing for the generated 64-bit interface:
    //   real effective field = m_axis_data_tdata[28:0]
    //   imag effective field = m_axis_data_tdata[60:32]
    assign fft_re = {{3{fft_output_data[28]}}, fft_output_data[28:0]};
    assign fft_im = {{3{fft_output_data[60]}}, fft_output_data[60:32]};

    assign fft_valid       = fft_output_valid;
    assign fft_last        = fft_output_last;
    assign fft_bin         = output_bin_count;
    assign fft_output_fire = fft_output_valid && fft_ready;
    assign frame_done      = fft_output_fire && fft_output_last;

    always @(posedge clk_60m) begin
        if (!rst_n) begin
            output_bin_count <= 13'd0;
        end else if (fft_output_fire) begin
            if (fft_output_last)
                output_bin_count <= 13'd0;
            else
                output_bin_count <= output_bin_count + 13'd1;
        end
    end

    xfft_8192 u_xfft_8192 (
        .aclk                           (clk_60m),
        .aresetn                        (rst_n),
        .s_axis_config_tdata            (config_data),
        .s_axis_config_tvalid           (config_valid),
        .s_axis_config_tready           (config_ready),
        .s_axis_data_tdata              (fft_input_data),
        .s_axis_data_tvalid             (fft_input_valid),
        .s_axis_data_tready             (fft_input_ready),
        .s_axis_data_tlast              (fft_input_last),
        .m_axis_data_tdata              (fft_output_data),
        .m_axis_data_tvalid             (fft_output_valid),
        .m_axis_data_tready             (fft_ready),
        .m_axis_data_tlast              (fft_output_last),
        .event_frame_started            (event_frame_started),
        .event_tlast_unexpected         (event_tlast_unexpected),
        .event_tlast_missing            (event_tlast_missing),
        .event_status_channel_halt      (event_status_channel_halt),
        .event_data_in_channel_halt     (event_data_in_channel_halt),
        .event_data_out_channel_halt    (event_data_out_channel_halt)
    );

endmodule
