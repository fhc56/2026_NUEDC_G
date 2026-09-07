`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: spectrum_metrics
// Function:
//   Convert the three FFT peak-detector results into display-oriented values.
//
//   * Inputs are defensively sorted into ascending frequency/bin order.
//   * The lowest-frequency component is reported as the fundamental.
//   * Frequencies are quantized to the official 500 Hz stimulus grid:
//         step = round(bin * 125 / 128)
//         frequency_hz = step * 500
//     This is equivalent to rounding the 4 MSPS / 8192 FFT-bin frequency to
//     the nearest 500 Hz point.
//   * For the unamplified five-term flat-top window used by this project:
//         amplitude_codes = round(sqrt(power) * 19003 / 2^24)
//   * ADC-code peak amplitude is converted to integer millivolts using a
//     board-calibratable Q20 millivolts-per-code coefficient.
//
// Clock domain: clk. peak_result_valid may be a one-clock pulse. The public
// result registers change atomically when result_valid is asserted.
//------------------------------------------------------------------------------
module spectrum_metrics #(
    parameter [31:0] K_FLAT_Q24 = 32'd19003,
    parameter [31:0] MV_PER_CODE_Q20 = 32'd512000
) (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          peak_result_valid,
    input  wire [12:0]   peak1_bin,
    input  wire [63:0]   peak1_power,
    input  wire [12:0]   peak2_bin,
    input  wire [63:0]   peak2_power,
    input  wire [12:0]   peak3_bin,
    input  wire [63:0]   peak3_power,
    input  wire [1:0]    peak_count_in,

    output reg  [31:0]   fundamental_hz,
    output reg  [31:0]   peak1_frequency_hz,
    output reg  [31:0]   peak2_frequency_hz,
    output reg  [31:0]   peak3_frequency_hz,
    output reg  [23:0]   peak1_amplitude_codes,
    output reg  [23:0]   peak2_amplitude_codes,
    output reg  [23:0]   peak3_amplitude_codes,
    output reg  [15:0]   peak1_amplitude_mv,
    output reg  [15:0]   peak2_amplitude_mv,
    output reg  [15:0]   peak3_amplitude_mv,
    output reg  [1:0]    peak_count_out,
    output reg           result_valid
);

    // Defensive sort network. peak_detector_3 already supplies ascending-bin
    // results, but keeping the association between bin and power here makes
    // this module safe to reuse with another peak source.
    reg [12:0] sorted_bin1;
    reg [12:0] sorted_bin2;
    reg [12:0] sorted_bin3;
    reg [63:0] sorted_power1;
    reg [63:0] sorted_power2;
    reg [63:0] sorted_power3;
    reg [12:0] swap_bin;
    reg [63:0] swap_power;

    always @* begin
        sorted_bin1   = (peak_count_in >= 2'd1) ? peak1_bin   : 13'd0;
        sorted_power1 = (peak_count_in >= 2'd1) ? peak1_power : 64'd0;
        sorted_bin2   = (peak_count_in >= 2'd2) ? peak2_bin   : 13'd0;
        sorted_power2 = (peak_count_in >= 2'd2) ? peak2_power : 64'd0;
        sorted_bin3   = (peak_count_in >= 2'd3) ? peak3_bin   : 13'd0;
        sorted_power3 = (peak_count_in >= 2'd3) ? peak3_power : 64'd0;
        swap_bin      = 13'd0;
        swap_power    = 64'd0;

        if ((peak_count_in >= 2'd2) && (sorted_bin2 < sorted_bin1)) begin
            swap_bin      = sorted_bin1;
            swap_power    = sorted_power1;
            sorted_bin1   = sorted_bin2;
            sorted_power1 = sorted_power2;
            sorted_bin2   = swap_bin;
            sorted_power2 = swap_power;
        end
        if ((peak_count_in >= 2'd3) && (sorted_bin3 < sorted_bin2)) begin
            swap_bin      = sorted_bin2;
            swap_power    = sorted_power2;
            sorted_bin2   = sorted_bin3;
            sorted_power2 = sorted_power3;
            sorted_bin3   = swap_bin;
            sorted_power3 = swap_power;
        end
        if ((peak_count_in >= 2'd3) && (sorted_bin2 < sorted_bin1)) begin
            swap_bin      = sorted_bin1;
            swap_power    = sorted_power1;
            sorted_bin1   = sorted_bin2;
            sorted_power1 = sorted_power2;
            sorted_bin2   = swap_bin;
            sorted_power2 = swap_power;
        end
    end

    reg [12:0] bin1_pending;
    reg [12:0] bin2_pending;
    reg [12:0] bin3_pending;
    reg [63:0] power1_pending;
    reg [63:0] power2_pending;
    reg [63:0] power3_pending;
    reg [1:0]  count_pending;
    reg        launch_pending;
    reg        transaction_active;

    wire [31:0] sqrt_root1;
    wire [31:0] sqrt_root2;
    wire [31:0] sqrt_root3;
    wire sqrt_valid1;
    wire sqrt_valid2;
    wire sqrt_valid3;
    wire sqrt_busy1;
    wire sqrt_busy2;
    wire sqrt_busy3;

    // launch_pending is asserted only after all pending operands have been
    // registered, so the square-root blocks cannot sample stale powers.
    wire sqrt_start;
    wire sqrt_all_valid;
    assign sqrt_start = launch_pending;
    assign sqrt_all_valid = sqrt_valid1 && sqrt_valid2 && sqrt_valid3;

    integer_sqrt_u64 u_sqrt_peak1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(sqrt_start),
        .radicand(power1_pending),
        .root(sqrt_root1),
        .valid(sqrt_valid1),
        .busy(sqrt_busy1)
    );

    integer_sqrt_u64 u_sqrt_peak2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(sqrt_start),
        .radicand(power2_pending),
        .root(sqrt_root2),
        .valid(sqrt_valid2),
        .busy(sqrt_busy2)
    );

    integer_sqrt_u64 u_sqrt_peak3 (
        .clk(clk),
        .rst_n(rst_n),
        .start(sqrt_start),
        .radicand(power3_pending),
        .root(sqrt_root3),
        .valid(sqrt_valid3),
        .busy(sqrt_busy3)
    );

    // Use explicitly widened operands. This avoids Verilog expression-width
    // truncation in constant multiplies and is accepted by Vivado 2018.3.
    wire [20:0] bin1_extended;
    wire [20:0] bin2_extended;
    wire [20:0] bin3_extended;
    wire [20:0] bin1_times_125;
    wire [20:0] bin2_times_125;
    wire [20:0] bin3_times_125;
    wire [31:0] frequency_step1;
    wire [31:0] frequency_step2;
    wire [31:0] frequency_step3;
    wire [31:0] frequency_calc1;
    wire [31:0] frequency_calc2;
    wire [31:0] frequency_calc3;

    assign bin1_extended = {8'd0, bin1_pending};
    assign bin2_extended = {8'd0, bin2_pending};
    assign bin3_extended = {8'd0, bin3_pending};
    assign bin1_times_125 = bin1_extended * 21'd125;
    assign bin2_times_125 = bin2_extended * 21'd125;
    assign bin3_times_125 = bin3_extended * 21'd125;
    assign frequency_step1 = (bin1_times_125 + 21'd64) >> 7;
    assign frequency_step2 = (bin2_times_125 + 21'd64) >> 7;
    assign frequency_step3 = (bin3_times_125 + 21'd64) >> 7;
    assign frequency_calc1 = frequency_step1 * 32'd500;
    assign frequency_calc2 = frequency_step2 * 32'd500;
    assign frequency_calc3 = frequency_step3 * 32'd500;

    wire [63:0] root1_extended;
    wire [63:0] root2_extended;
    wire [63:0] root3_extended;
    wire [63:0] scale_extended;
    wire [63:0] amplitude_product1;
    wire [63:0] amplitude_product2;
    wire [63:0] amplitude_product3;
    wire [63:0] amplitude_rounded1;
    wire [63:0] amplitude_rounded2;
    wire [63:0] amplitude_rounded3;
    wire [39:0] amplitude_code_full1;
    wire [39:0] amplitude_code_full2;
    wire [39:0] amplitude_code_full3;
    wire [23:0] amplitude_code_calc1;
    wire [23:0] amplitude_code_calc2;
    wire [23:0] amplitude_code_calc3;

    assign root1_extended = {32'd0, sqrt_root1};
    assign root2_extended = {32'd0, sqrt_root2};
    assign root3_extended = {32'd0, sqrt_root3};
    assign scale_extended = {32'd0, K_FLAT_Q24};
    assign amplitude_product1 = root1_extended * scale_extended;
    assign amplitude_product2 = root2_extended * scale_extended;
    assign amplitude_product3 = root3_extended * scale_extended;
    assign amplitude_rounded1 = amplitude_product1 + 64'd8388608;
    assign amplitude_rounded2 = amplitude_product2 + 64'd8388608;
    assign amplitude_rounded3 = amplitude_product3 + 64'd8388608;
    assign amplitude_code_full1 = amplitude_rounded1[63:24];
    assign amplitude_code_full2 = amplitude_rounded2[63:24];
    assign amplitude_code_full3 = amplitude_rounded3[63:24];
    assign amplitude_code_calc1 = (|amplitude_code_full1[39:24]) ?
                                  24'hFFFFFF : amplitude_code_full1[23:0];
    assign amplitude_code_calc2 = (|amplitude_code_full2[39:24]) ?
                                  24'hFFFFFF : amplitude_code_full2[23:0];
    assign amplitude_code_calc3 = (|amplitude_code_full3[39:24]) ?
                                  24'hFFFFFF : amplitude_code_full3[23:0];

    // Register the first scaling stage.  This deliberately breaks the path
    // between the FFT-magnitude multiplier and the following mV multiplier;
    // two unregistered multipliers in series are needlessly risky at 60 MHz.
    reg [31:0] frequency_hold1;
    reg [31:0] frequency_hold2;
    reg [31:0] frequency_hold3;
    reg [23:0] amplitude_code_hold1;
    reg [23:0] amplitude_code_hold2;
    reg [23:0] amplitude_code_hold3;
    reg [1:0]  count_hold;
    reg        conversion_pending;

    wire [55:0] amplitude_code1_extended;
    wire [55:0] amplitude_code2_extended;
    wire [55:0] amplitude_code3_extended;
    wire [55:0] mv_scale_extended;
    wire [55:0] mv_product1;
    wire [55:0] mv_product2;
    wire [55:0] mv_product3;
    wire [55:0] mv_rounded1;
    wire [55:0] mv_rounded2;
    wire [55:0] mv_rounded3;
    wire [35:0] mv_full1;
    wire [35:0] mv_full2;
    wire [35:0] mv_full3;
    wire [15:0] mv_calc1;
    wire [15:0] mv_calc2;
    wire [15:0] mv_calc3;

    assign amplitude_code1_extended = {32'd0, amplitude_code_hold1};
    assign amplitude_code2_extended = {32'd0, amplitude_code_hold2};
    assign amplitude_code3_extended = {32'd0, amplitude_code_hold3};
    assign mv_scale_extended = {24'd0, MV_PER_CODE_Q20};
    assign mv_product1 = amplitude_code1_extended * mv_scale_extended;
    assign mv_product2 = amplitude_code2_extended * mv_scale_extended;
    assign mv_product3 = amplitude_code3_extended * mv_scale_extended;
    assign mv_rounded1 = mv_product1 + 56'd524288;
    assign mv_rounded2 = mv_product2 + 56'd524288;
    assign mv_rounded3 = mv_product3 + 56'd524288;
    assign mv_full1 = mv_rounded1[55:20];
    assign mv_full2 = mv_rounded2[55:20];
    assign mv_full3 = mv_rounded3[55:20];
    assign mv_calc1 = (|mv_full1[35:16]) ? 16'hFFFF : mv_full1[15:0];
    assign mv_calc2 = (|mv_full2[35:16]) ? 16'hFFFF : mv_full2[15:0];
    assign mv_calc3 = (|mv_full3[35:16]) ? 16'hFFFF : mv_full3[15:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            bin1_pending          <= 13'd0;
            bin2_pending          <= 13'd0;
            bin3_pending          <= 13'd0;
            power1_pending        <= 64'd0;
            power2_pending        <= 64'd0;
            power3_pending        <= 64'd0;
            count_pending         <= 2'd0;
            launch_pending        <= 1'b0;
            transaction_active    <= 1'b0;
            frequency_hold1       <= 32'd0;
            frequency_hold2       <= 32'd0;
            frequency_hold3       <= 32'd0;
            amplitude_code_hold1  <= 24'd0;
            amplitude_code_hold2  <= 24'd0;
            amplitude_code_hold3  <= 24'd0;
            count_hold            <= 2'd0;
            conversion_pending    <= 1'b0;

            fundamental_hz        <= 32'd0;
            peak1_frequency_hz    <= 32'd0;
            peak2_frequency_hz    <= 32'd0;
            peak3_frequency_hz    <= 32'd0;
            peak1_amplitude_codes <= 24'd0;
            peak2_amplitude_codes <= 24'd0;
            peak3_amplitude_codes <= 24'd0;
            peak1_amplitude_mv    <= 16'd0;
            peak2_amplitude_mv    <= 16'd0;
            peak3_amplitude_mv    <= 16'd0;
            peak_count_out        <= 2'd0;
            result_valid          <= 1'b0;
        end else begin
            result_valid <= 1'b0;

            if (launch_pending)
                launch_pending <= 1'b0;

            if (conversion_pending) begin
                peak_count_out        <= count_hold;
                fundamental_hz        <= frequency_hold1;
                peak1_frequency_hz    <= frequency_hold1;
                peak2_frequency_hz    <= frequency_hold2;
                peak3_frequency_hz    <= frequency_hold3;
                peak1_amplitude_codes <= amplitude_code_hold1;
                peak2_amplitude_codes <= amplitude_code_hold2;
                peak3_amplitude_codes <= amplitude_code_hold3;
                peak1_amplitude_mv    <= mv_calc1;
                peak2_amplitude_mv    <= mv_calc2;
                peak3_amplitude_mv    <= mv_calc3;
                result_valid          <= 1'b1;
                conversion_pending    <= 1'b0;
            end

            if (sqrt_all_valid) begin
                count_hold <= count_pending;
                if (count_pending >= 2'd1) begin
                    frequency_hold1      <= frequency_calc1;
                    amplitude_code_hold1 <= amplitude_code_calc1;
                end else begin
                    frequency_hold1      <= 32'd0;
                    amplitude_code_hold1 <= 24'd0;
                end

                if (count_pending >= 2'd2) begin
                    frequency_hold2      <= frequency_calc2;
                    amplitude_code_hold2 <= amplitude_code_calc2;
                end else begin
                    frequency_hold2      <= 32'd0;
                    amplitude_code_hold2 <= 24'd0;
                end

                if (count_pending >= 2'd3) begin
                    frequency_hold3      <= frequency_calc3;
                    amplitude_code_hold3 <= amplitude_code_calc3;
                end else begin
                    frequency_hold3      <= 32'd0;
                    amplitude_code_hold3 <= 24'd0;
                end

                conversion_pending <= 1'b1;
                transaction_active <= 1'b0;
            end

            // Accept a new result when idle. Also permit a back-to-back input
            // on the same clock that the previous square roots complete.
            if (peak_result_valid &&
                ((!transaction_active) || sqrt_all_valid)) begin
                bin1_pending       <= sorted_bin1;
                bin2_pending       <= sorted_bin2;
                bin3_pending       <= sorted_bin3;
                power1_pending     <= sorted_power1;
                power2_pending     <= sorted_power2;
                power3_pending     <= sorted_power3;
                count_pending      <= peak_count_in;
                launch_pending     <= 1'b1;
                transaction_active <= 1'b1;
            end
        end
    end

endmodule
