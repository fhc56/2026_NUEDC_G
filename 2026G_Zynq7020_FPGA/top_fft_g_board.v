`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: top_fft_g_board
// Function:
//   Physical top level for the photographed xc7z020clg484-2 board.  Only the
//   real ADC, clock/reset and UART signals are package ports.  Measurement
//   buses remain internal MARK_DEBUG nets for ILA verification, while the MCU
//   receives an atomic ASCII result frame on uart_tx.
//
// Voltage calibration:
//   MV_PER_CODE_Q20 is connector-referred millivolts per signed ADC code.
//   512000 is the nominal 2.000 Vpp/4096-code value.  Keep
//   CALIBRATION_VALID=0 until the assembled analog path is calibrated against
//   the function-generator setting used by the judges.
//------------------------------------------------------------------------------
module fft_pl_top #(
    parameter [31:0] MV_PER_CODE_Q20 = 32'd512000,
    parameter        CALIBRATION_VALID = 1'b0
) (
    input  wire        sys_clk_50m,
    input  wire        rst_n,
    output wire        ad_clk,
    input  wire [11:0] ad_data_in,
    input  wire        ad_otr_in,
    output wire        uart_tx
);

    (* mark_debug = "true" *) wire [63:0] spectrum_power;
    (* mark_debug = "true" *) wire [12:0] spectrum_bin;
    (* mark_debug = "true" *) wire spectrum_valid;
    (* mark_debug = "true" *) wire frame_done;
    (* mark_debug = "true" *) wire [12:0] peak1_bin;
    wire [63:0] peak1_power;
    (* mark_debug = "true" *) wire [12:0] peak2_bin;
    wire [63:0] peak2_power;
    (* mark_debug = "true" *) wire [12:0] peak3_bin;
    wire [63:0] peak3_power;
    (* mark_debug = "true" *) wire [1:0] peak_count;
    (* mark_debug = "true" *) wire peak_result_valid;

    (* mark_debug = "true" *) wire [24:0] vpp_codes_q8;
    (* mark_debug = "true" *) wire [23:0] rms_codes_q8;
    wire [16:0] vpp_codes;
    wire [15:0] rms_codes;
    (* mark_debug = "true" *) wire [15:0] vpp_mv;
    (* mark_debug = "true" *) wire [15:0] rms_mv;
    (* mark_debug = "true" *) wire waveform_measurement_clip;
    (* mark_debug = "true" *) wire waveform_measurement_valid;

    (* mark_debug = "true" *) wire [31:0] fundamental_hz;
    (* mark_debug = "true" *) wire [31:0] peak1_frequency_hz;
    (* mark_debug = "true" *) wire [31:0] peak2_frequency_hz;
    (* mark_debug = "true" *) wire [31:0] peak3_frequency_hz;
    wire [23:0] peak1_amplitude_codes;
    wire [23:0] peak2_amplitude_codes;
    wire [23:0] peak3_amplitude_codes;
    (* mark_debug = "true" *) wire [15:0] peak1_amplitude_mv;
    (* mark_debug = "true" *) wire [15:0] peak2_amplitude_mv;
    (* mark_debug = "true" *) wire [15:0] peak3_amplitude_mv;
    wire [1:0] measured_peak_count;
    (* mark_debug = "true" *) wire spectrum_measurement_valid;
    (* mark_debug = "true" *) wire [7:0] measurement_status;
    (* mark_debug = "true" *) wire adc_overrange_frame;
    (* mark_debug = "true" *) wire fifo_overflow;

    top_fft_g #(
        .WINDOW_MODE             (2'b10),
        .MV_PER_CODE_Q20         (MV_PER_CODE_Q20),
        .CALIBRATION_VALID       (CALIBRATION_VALID),
        .UART_CLKS_PER_BIT       (521),
        .UART_UPDATE_INTERVAL_CLKS (6000000)
    ) u_top_fft_g (
        .sys_clk                    (sys_clk_50m),
        .sys_rst_n                  (rst_n),
        .ad_clk                     (ad_clk),
        .ad_data_in                 (ad_data_in),
        .ad_otr_in                  (ad_otr_in),
        .uart_tx                    (uart_tx),
        .spectrum_power             (spectrum_power),
        .spectrum_bin               (spectrum_bin),
        .spectrum_valid             (spectrum_valid),
        .frame_done                 (frame_done),
        .peak1_bin                  (peak1_bin),
        .peak1_power                (peak1_power),
        .peak2_bin                  (peak2_bin),
        .peak2_power                (peak2_power),
        .peak3_bin                  (peak3_bin),
        .peak3_power                (peak3_power),
        .peak_count                 (peak_count),
        .peak_result_valid          (peak_result_valid),
        .vpp_codes_q8               (vpp_codes_q8),
        .rms_codes_q8               (rms_codes_q8),
        .vpp_codes                  (vpp_codes),
        .rms_codes                  (rms_codes),
        .vpp_mv                     (vpp_mv),
        .rms_mv                     (rms_mv),
        .waveform_measurement_clip  (waveform_measurement_clip),
        .waveform_measurement_valid (waveform_measurement_valid),
        .fundamental_hz             (fundamental_hz),
        .peak1_frequency_hz         (peak1_frequency_hz),
        .peak2_frequency_hz         (peak2_frequency_hz),
        .peak3_frequency_hz         (peak3_frequency_hz),
        .peak1_amplitude_codes      (peak1_amplitude_codes),
        .peak2_amplitude_codes      (peak2_amplitude_codes),
        .peak3_amplitude_codes      (peak3_amplitude_codes),
        .peak1_amplitude_mv         (peak1_amplitude_mv),
        .peak2_amplitude_mv         (peak2_amplitude_mv),
        .peak3_amplitude_mv         (peak3_amplitude_mv),
        .measured_peak_count        (measured_peak_count),
        .spectrum_measurement_valid (spectrum_measurement_valid),
        .measurement_status         (measurement_status),
        .adc_overrange_frame        (adc_overrange_frame),
        .fifo_overflow              (fifo_overflow)
    );

endmodule
