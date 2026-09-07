`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: g_fft_8192_core
// Function: Complete 60 MSPS AD9226-to-spectrum PL chain for the first two
//           questions: offset-binary conversion, anti-alias FIR/15, FIFO,
//           selectable window, 8192-point FFT, power, and three peaks.
// Clock domain: clk_60m only. All internal IP and RTL share this clock.
// ADC input: 12-bit offset binary, one sample every clock.
// Spectrum output: 8192 natural-order bins/frame; 64-bit unsigned power.
//------------------------------------------------------------------------------
module g_fft_8192_core #(
    // Connector-referred calibration.  Default assumes 2.000 Vpp spans all
    // 4096 ADC codes: 0.48828125 mV/code = 512000 in Q20.
    parameter [31:0] MV_PER_CODE_Q20 = 32'd512000
) (
    input  wire          clk_60m,
    input  wire          rst_n,
    input  wire [11:0]   ad_data,
    input  wire          ad_otr,
    input  wire [1:0]    window_select,

    output wire [63:0]   spectrum_power,
    output wire [12:0]   spectrum_bin,
    output wire          spectrum_valid,
    output wire          frame_done,

    output wire [12:0]   peak1_bin,
    output wire [63:0]   peak1_power,
    output wire [12:0]   peak2_bin,
    output wire [63:0]   peak2_power,
    output wire [12:0]   peak3_bin,
    output wire [63:0]   peak3_power,
    output wire [1:0]    peak_count,
    output wire          peak_result_valid,

    // Display-oriented waveform measurements.  Voltage values are integer
    // millivolts; the Q8/raw-code outputs are retained for board calibration.
    output wire [24:0]   vpp_codes_q8,
    output wire [23:0]   rms_codes_q8,
    output wire [16:0]   vpp_codes,
    output wire [15:0]   rms_codes,
    output wire [15:0]   vpp_mv,
    output wire [15:0]   rms_mv,
    output wire          waveform_measurement_clip,
    output wire          waveform_measurement_valid,

    // Display-oriented spectral measurements.  Frequencies are snapped to
    // the official 500 Hz stimulus grid; amplitudes are sinusoidal peak mV.
    output wire [31:0]   fundamental_hz,
    output wire [31:0]   peak1_frequency_hz,
    output wire [31:0]   peak2_frequency_hz,
    output wire [31:0]   peak3_frequency_hz,
    output wire [23:0]   peak1_amplitude_codes,
    output wire [23:0]   peak2_amplitude_codes,
    output wire [23:0]   peak3_amplitude_codes,
    output wire [15:0]   peak1_amplitude_mv,
    output wire [15:0]   peak2_amplitude_mv,
    output wire [15:0]   peak3_amplitude_mv,
    output wire [1:0]    measured_peak_count,
    output wire          spectrum_measurement_valid,

    output wire          adc_overrange_frame,
    output wire          fifo_overflow,
    output wire          fifo_underflow,
    output wire [10:0]   fifo_level,
    output wire          fir_input_overflow,
    output wire          event_tlast_unexpected,
    output wire          event_tlast_missing
);

    wire signed [11:0] adc_signed;
    wire adc_valid;
    wire adc_otr_sync;
    wire adc_raw_bad;
    reg  adc_bad_since_metric_sample;
    wire metric_sample_bad;

    wire [15:0] fir_input_data;
    wire fir_input_ready;
    wire fir_output_valid;
    wire [31:0] fir_output_bus;
    wire signed [29:0] fir_full_precision;
    reg fir_input_overflow_reg;

    wire signed [15:0] fir_scaled;
    wire fir_scaled_valid;

    wire [15:0] fifo_output_data;
    wire fifo_output_valid;
    wire fifo_output_ready;

    wire signed [15:0] windowed_sample;
    wire windowed_valid;
    wire windowed_ready;
    wire [12:0] window_index;

    wire signed [31:0] fft_re;
    wire signed [31:0] fft_im;
    wire [12:0] fft_bin;
    wire fft_valid;
    wire fft_ready;
    wire fft_last;
    wire fft_frame_done;
    wire event_status_channel_halt;
    wire event_data_in_channel_halt;
    wire event_data_out_channel_halt;

    wire spectrum_last;
    wire spectrum_ready;

    adc_offset_binary u_adc_offset_binary (
        .clk_sample   (clk_60m),
        .rst_n        (rst_n),
        .adc_raw      (ad_data),
        .adc_otr      (ad_otr),
        .adc_signed   (adc_signed),
        .adc_valid    (adc_valid),
        .adc_otr_sync (adc_otr_sync)
    );

    assign fir_input_data = {{4{adc_signed[11]}}, adc_signed};
    assign adc_raw_bad = adc_valid &&
        (adc_otr_sync || (ad_data == 12'd0) || (ad_data == 12'd4095));
    assign metric_sample_bad = adc_bad_since_metric_sample || adc_raw_bad;

    // Preserve any raw ADC rail/OTR event between two 4 MSPS FIR outputs.
    // waveform_metrics consumes and clears the accumulated flag with the next
    // valid decimated sample.
    always @(posedge clk_60m) begin
        if (!rst_n) begin
            adc_bad_since_metric_sample <= 1'b0;
        end else begin
            if (adc_raw_bad)
                adc_bad_since_metric_sample <= 1'b1;
            if (fir_scaled_valid)
                adc_bad_since_metric_sample <= 1'b0;
        end
    end

    fir_decim15 u_fir_decim15 (
        .aresetn                (rst_n),
        .aclk                   (clk_60m),
        .s_axis_data_tvalid     (adc_valid),
        .s_axis_data_tready     (fir_input_ready),
        .s_axis_data_tdata      (fir_input_data),
        .m_axis_data_tvalid     (fir_output_valid),
        .m_axis_data_tdata      (fir_output_bus)
    );

    assign fir_full_precision = fir_output_bus[29:0];

    always @(posedge clk_60m) begin
        if (!rst_n)
            fir_input_overflow_reg <= 1'b0;
        else if (adc_valid && !fir_input_ready)
            fir_input_overflow_reg <= 1'b1;
    end
    assign fir_input_overflow = fir_input_overflow_reg;

    fir_output_scale #(
        .FIR_WIDTH  (30),
        .SHIFT_BITS (17)
    ) u_fir_output_scale (
        .clk          (clk_60m),
        .rst_n        (rst_n),
        .fir_data     (fir_full_precision),
        .fir_valid    (fir_output_valid),
        .scaled_data  (fir_scaled),
        .scaled_valid (fir_scaled_valid)
    );

    // Vpp/RMS must be measured before the spectral window is applied.  The
    // FIR output is still in signed ADC-code units because its coefficient
    // sum is exactly 2^17 and fir_output_scale removes those fractional bits.
    waveform_metrics #(
        .MV_PER_CODE_Q20 (MV_PER_CODE_Q20)
    ) u_waveform_metrics (
        .clk               (clk_60m),
        .rst_n             (rst_n),
        .sample_in         (fir_scaled),
        .sample_valid      (fir_scaled_valid),
        .sample_bad        (metric_sample_bad),
        .vpp_codes_q8      (vpp_codes_q8),
        .rms_codes_q8      (rms_codes_q8),
        .vpp_codes         (vpp_codes),
        .rms_codes         (rms_codes),
        .vpp_mv            (vpp_mv),
        .rms_mv            (rms_mv),
        .measurement_clip  (waveform_measurement_clip),
        .measurement_valid (waveform_measurement_valid)
    );

    axis_sync_fifo #(
        .DATA_WIDTH (16),
        .ADDR_WIDTH (10)
    ) u_sample_fifo (
        .clk       (clk_60m),
        .rst_n     (rst_n),
        .s_data    (fir_scaled),
        .s_valid   (fir_scaled_valid),
        .s_ready   (),
        .m_data    (fifo_output_data),
        .m_valid   (fifo_output_valid),
        .m_ready   (fifo_output_ready),
        .level     (fifo_level),
        .overflow  (fifo_overflow),
        .underflow (fifo_underflow)
    );

    window_8192 u_window_8192 (
        .clk           (clk_60m),
        .rst_n         (rst_n),
        .window_select (window_select),
        .s_data        (fifo_output_data),
        .s_valid       (fifo_output_valid),
        .s_ready       (fifo_output_ready),
        .m_data        (windowed_sample),
        .m_valid       (windowed_valid),
        .m_ready       (windowed_ready),
        .window_index  (window_index)
    );

    fft_8192_wrapper u_fft_8192_wrapper (
        .clk_60m                       (clk_60m),
        .rst_n                         (rst_n),
        .sample_in                     (windowed_sample),
        .sample_valid                  (windowed_valid),
        .sample_ready                  (windowed_ready),
        .fft_re                        (fft_re),
        .fft_im                        (fft_im),
        .fft_bin                       (fft_bin),
        .fft_valid                     (fft_valid),
        .fft_ready                     (fft_ready),
        .fft_last                      (fft_last),
        .frame_done                    (fft_frame_done),
        .event_tlast_unexpected        (event_tlast_unexpected),
        .event_tlast_missing           (event_tlast_missing),
        .event_status_channel_halt     (event_status_channel_halt),
        .event_data_in_channel_halt    (event_data_in_channel_halt),
        .event_data_out_channel_halt   (event_data_out_channel_halt)
    );

    fft_power_calc u_fft_power_calc (
        .clk             (clk_60m),
        .rst_n           (rst_n),
        .fft_re          (fft_re),
        .fft_im          (fft_im),
        .fft_bin         (fft_bin),
        .fft_last        (fft_last),
        .s_valid         (fft_valid),
        .s_ready         (fft_ready),
        .spectrum_power  (spectrum_power),
        .spectrum_bin    (spectrum_bin),
        .spectrum_last   (spectrum_last),
        .m_valid         (spectrum_valid),
        .m_ready         (spectrum_ready)
    );

    assign frame_done = spectrum_valid && spectrum_ready && spectrum_last;

    peak_detector_3 u_peak_detector_3 (
        .clk                (clk_60m),
        .rst_n              (rst_n),
        .spectrum_power     (spectrum_power),
        .spectrum_bin       (spectrum_bin),
        .spectrum_valid     (spectrum_valid),
        .spectrum_last      (spectrum_last),
        .spectrum_ready     (spectrum_ready),
        .peak1_bin          (peak1_bin),
        .peak1_power        (peak1_power),
        .peak2_bin          (peak2_bin),
        .peak2_power        (peak2_power),
        .peak3_bin          (peak3_bin),
        .peak3_power        (peak3_power),
        .peak_count         (peak_count),
        .peak_result_valid  (peak_result_valid)
    );

    spectrum_metrics #(
        .K_FLAT_Q24       (32'd19003),
        .MV_PER_CODE_Q20  (MV_PER_CODE_Q20)
    ) u_spectrum_metrics (
        .clk                   (clk_60m),
        .rst_n                 (rst_n),
        .peak_result_valid     (peak_result_valid),
        .peak1_bin             (peak1_bin),
        .peak1_power           (peak1_power),
        .peak2_bin             (peak2_bin),
        .peak2_power           (peak2_power),
        .peak3_bin             (peak3_bin),
        .peak3_power           (peak3_power),
        .peak_count_in         (peak_count),
        .fundamental_hz        (fundamental_hz),
        .peak1_frequency_hz    (peak1_frequency_hz),
        .peak2_frequency_hz    (peak2_frequency_hz),
        .peak3_frequency_hz    (peak3_frequency_hz),
        .peak1_amplitude_codes (peak1_amplitude_codes),
        .peak2_amplitude_codes (peak2_amplitude_codes),
        .peak3_amplitude_codes (peak3_amplitude_codes),
        .peak1_amplitude_mv    (peak1_amplitude_mv),
        .peak2_amplitude_mv    (peak2_amplitude_mv),
        .peak3_amplitude_mv    (peak3_amplitude_mv),
        .peak_count_out        (measured_peak_count),
        .result_valid          (spectrum_measurement_valid)
    );

    adc_overrange_frame u_adc_overrange_frame (
        .clk             (clk_60m),
        .rst_n           (rst_n),
        .adc_otr         (adc_otr_sync),
        .frame_done      (frame_done),
        .overrange_frame (adc_overrange_frame)
    );

endmodule
