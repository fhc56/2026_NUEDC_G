`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: top_fft_g
// Function: Board-facing wrapper preserving the existing AD9226 physical port
//           names. Spectrum/peak outputs remain available for simulation, ILA,
//           or later PS/register integration.
// Board clock: sys_clk=50 MHz. Internal processing: 60 MHz.
//------------------------------------------------------------------------------
module top_fft_g #(
    // Flat-top is the measurement default because the official frequencies
    // are on a 500 Hz grid while the FFT bins are 488.28125 Hz apart.
    parameter [1:0]  WINDOW_MODE = 2'b10,
    parameter [31:0] MV_PER_CODE_Q20 = 32'd512000,
    parameter        CALIBRATION_VALID = 1'b0,
    parameter integer UART_CLKS_PER_BIT = 521,
    parameter integer UART_UPDATE_INTERVAL_CLKS = 6000000
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output wire        ad_clk,
    input  wire [11:0] ad_data_in,
    input  wire        ad_otr_in,
    output wire        uart_tx,

    output wire [63:0] spectrum_power,
    output wire [12:0] spectrum_bin,
    output wire        spectrum_valid,
    output wire        frame_done,
    output wire [12:0] peak1_bin,
    output wire [63:0] peak1_power,
    output wire [12:0] peak2_bin,
    output wire [63:0] peak2_power,
    output wire [12:0] peak3_bin,
    output wire [63:0] peak3_power,
    output wire [1:0]  peak_count,
    output wire        peak_result_valid,
    output wire [24:0] vpp_codes_q8,
    output wire [23:0] rms_codes_q8,
    output wire [16:0] vpp_codes,
    output wire [15:0] rms_codes,
    output wire [15:0] vpp_mv,
    output wire [15:0] rms_mv,
    output wire        waveform_measurement_clip,
    output wire        waveform_measurement_valid,
    output wire [31:0] fundamental_hz,
    output wire [31:0] peak1_frequency_hz,
    output wire [31:0] peak2_frequency_hz,
    output wire [31:0] peak3_frequency_hz,
    output wire [23:0] peak1_amplitude_codes,
    output wire [23:0] peak2_amplitude_codes,
    output wire [23:0] peak3_amplitude_codes,
    output wire [15:0] peak1_amplitude_mv,
    output wire [15:0] peak2_amplitude_mv,
    output wire [15:0] peak3_amplitude_mv,
    output wire [1:0]  measured_peak_count,
    output wire        spectrum_measurement_valid,
    output wire [7:0]  measurement_status,
    output wire        adc_overrange_frame,
    output wire        fifo_overflow
);

    wire clk_60m_core;
    wire clock_locked;
    wire core_rst_n;
    (* ASYNC_REG = "TRUE" *) reg [1:0] core_reset_sync;
    wire fifo_underflow;
    wire [10:0] fifo_level;
    wire fir_input_overflow;
    wire event_tlast_unexpected;
    wire event_tlast_missing;
    reg event_tlast_unexpected_sticky;
    reg event_tlast_missing_sticky;

    ad9226_clock_capture u_ad9226_clock_capture (
        .sys_clk      (sys_clk),
        .rst_n        (sys_rst_n),
        .ad_clk       (ad_clk),
        .clk_60m_core (clk_60m_core),
        .locked       (clock_locked)
    );

    // Assert reset immediately if the external reset or MMCM lock is lost,
    // then release it only after two clean 60 MHz edges.  This avoids an
    // asynchronous reset release metastability window across the whole core.
    always @(posedge clk_60m_core or negedge sys_rst_n or
             negedge clock_locked) begin
        if (!sys_rst_n || !clock_locked)
            core_reset_sync <= 2'b00;
        else
            core_reset_sync <= {core_reset_sync[0], 1'b1};
    end
    assign core_rst_n = core_reset_sync[1];

    g_fft_8192_core #(
        .MV_PER_CODE_Q20 (MV_PER_CODE_Q20)
    ) u_g_fft_8192_core (
        .clk_60m                 (clk_60m_core),
        .rst_n                   (core_rst_n),
        .ad_data                 (ad_data_in),
        .ad_otr                  (ad_otr_in),
        .window_select           (WINDOW_MODE),
        .spectrum_power          (spectrum_power),
        .spectrum_bin            (spectrum_bin),
        .spectrum_valid          (spectrum_valid),
        .frame_done              (frame_done),
        .peak1_bin               (peak1_bin),
        .peak1_power             (peak1_power),
        .peak2_bin               (peak2_bin),
        .peak2_power             (peak2_power),
        .peak3_bin               (peak3_bin),
        .peak3_power             (peak3_power),
        .peak_count              (peak_count),
        .peak_result_valid       (peak_result_valid),
        .vpp_codes_q8            (vpp_codes_q8),
        .rms_codes_q8            (rms_codes_q8),
        .vpp_codes               (vpp_codes),
        .rms_codes               (rms_codes),
        .vpp_mv                  (vpp_mv),
        .rms_mv                  (rms_mv),
        .waveform_measurement_clip  (waveform_measurement_clip),
        .waveform_measurement_valid (waveform_measurement_valid),
        .fundamental_hz          (fundamental_hz),
        .peak1_frequency_hz      (peak1_frequency_hz),
        .peak2_frequency_hz      (peak2_frequency_hz),
        .peak3_frequency_hz      (peak3_frequency_hz),
        .peak1_amplitude_codes   (peak1_amplitude_codes),
        .peak2_amplitude_codes   (peak2_amplitude_codes),
        .peak3_amplitude_codes   (peak3_amplitude_codes),
        .peak1_amplitude_mv      (peak1_amplitude_mv),
        .peak2_amplitude_mv      (peak2_amplitude_mv),
        .peak3_amplitude_mv      (peak3_amplitude_mv),
        .measured_peak_count     (measured_peak_count),
        .spectrum_measurement_valid (spectrum_measurement_valid),
        .adc_overrange_frame     (adc_overrange_frame),
        .fifo_overflow           (fifo_overflow),
        .fifo_underflow          (fifo_underflow),
        .fifo_level              (fifo_level),
        .fir_input_overflow      (fir_input_overflow),
        .event_tlast_unexpected  (event_tlast_unexpected),
        .event_tlast_missing     (event_tlast_missing)
    );

    // AXI-event outputs can be pulses, so keep them until external reset.
    always @(posedge clk_60m_core) begin
        if (!core_rst_n) begin
            event_tlast_unexpected_sticky <= 1'b0;
            event_tlast_missing_sticky    <= 1'b0;
        end else begin
            if (event_tlast_unexpected)
                event_tlast_unexpected_sticky <= 1'b1;
            if (event_tlast_missing)
                event_tlast_missing_sticky <= 1'b1;
        end
    end

    // Status byte sent to the MCU:
    // bit0 ADC OTR in the latest FFT frame
    // bit1 sample FIFO overflow (sticky)
    // bit2 FIR input backpressure/overflow (sticky)
    // bit3 FFT TLAST unexpected (sticky)
    // bit4 FFT TLAST missing (sticky)
    // bit5 waveform path clipped (latest 65536-sample window)
    // bit6 voltage calibration still nominal/not confirmed
    // bit7 reserved
    assign measurement_status = {
        1'b0,
        ~CALIBRATION_VALID,
        waveform_measurement_clip,
        event_tlast_missing_sticky,
        event_tlast_unexpected_sticky,
        fir_input_overflow,
        fifo_overflow,
        adc_overrange_frame
    };

    measurement_uart #(
        .UART_CLKS_PER_BIT     (UART_CLKS_PER_BIT),
        .UPDATE_INTERVAL_CLKS  (UART_UPDATE_INTERVAL_CLKS)
    ) u_measurement_uart (
        .clk          (clk_60m_core),
        .rst_n        (core_rst_n),
        .vpp_mv       (vpp_mv),
        .rms_mv       (rms_mv),
        .base_hz      (fundamental_hz),
        .f1_hz        (peak1_frequency_hz),
        .a1_mv        (peak1_amplitude_mv),
        .f2_hz        (peak2_frequency_hz),
        .a2_mv        (peak2_amplitude_mv),
        .f3_hz        (peak3_frequency_hz),
        .a3_mv        (peak3_amplitude_mv),
        .peak_count   (measured_peak_count),
        .status       (measurement_status),
        .result_valid (waveform_measurement_valid),
        .update_valid (spectrum_measurement_valid),
        .uart_tx      (uart_tx)
    );

endmodule
