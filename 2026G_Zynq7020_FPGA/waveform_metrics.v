`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: waveform_metrics
// Function:
//   Measure the total composite waveform peak-to-peak value and true RMS from
//   the unwindowed, low-pass-filtered 4 MSPS stream.
//
// Measurement window: 65536 accepted samples (16.384 ms at 4 MSPS).
// RMS definition: sqrt(mean((x-mean(x))^2)). The input specified by the G
//   question is AC-only; subtracting the measured mean removes ADC midscale
//   error without modifying the FFT signal path. With N=65536, if
//       energy = sum(x^2) - round(sum(x)^2/N),
//   then sqrt(energy) is the RMS value in ADC-code Q8 format.
// Vpp: the largest/minimum sampled extrema are refined with a three-point
//   parabolic vertex correction. This avoids the 7.6 percent worst-case
//   sampled-peak error of a 500 kHz tone at 4 MSPS.
// Calibration: MV_PER_CODE_Q20 is connector-referred millivolts per ADC code.
//   Nominal 2.000 Vpp/4096-code conversion is 0.48828125 mV/code, or 512000
//   in Q20. It remains a parameter because the board VREF/front-end/50-ohm
//   configuration must be calibrated on the actual hardware.
//------------------------------------------------------------------------------
module waveform_metrics #(
    parameter [31:0] MV_PER_CODE_Q20 = 32'd512000
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire signed [15:0]   sample_in,
    input  wire                 sample_valid,
    input  wire                 sample_bad,

    output reg  [24:0]          vpp_codes_q8,
    output reg  [23:0]          rms_codes_q8,
    output reg  [16:0]          vpp_codes,
    output reg  [15:0]          rms_codes,
    output reg  [15:0]          vpp_mv,
    output reg  [15:0]          rms_mv,
    output reg                  measurement_clip,
    output reg                  measurement_valid
);

    reg [15:0] sample_count;
    reg [46:0] sum_squares;
    reg signed [32:0] sum_samples;

    wire signed [31:0] sample_square_signed;
    wire [31:0] sample_square;
    wire [46:0] sum_squares_with_sample;
    wire signed [32:0] sample_extended;
    wire signed [32:0] sum_samples_with_sample;
    wire signed [65:0] sum_samples_square_signed;
    wire [65:0] sum_samples_square;
    wire [49:0] dc_energy_rounded;
    wire [46:0] ac_energy_with_sample;

    assign sample_square_signed = $signed(sample_in) * $signed(sample_in);
    assign sample_square = sample_square_signed[31:0];
    assign sum_squares_with_sample =
        sum_squares + {{15{1'b0}}, sample_square};
    assign sample_extended = {{17{sample_in[15]}}, sample_in};
    assign sum_samples_with_sample = sum_samples + sample_extended;
    assign sum_samples_square_signed =
        $signed(sum_samples_with_sample) * $signed(sum_samples_with_sample);
    assign sum_samples_square = sum_samples_square_signed[65:0];
    assign dc_energy_rounded =
        (sum_samples_square + 66'd32768) >> 16;
    assign ac_energy_with_sample =
        (sum_squares_with_sample >= dc_energy_rounded[46:0]) ?
        (sum_squares_with_sample - dc_energy_rounded[46:0]) : 47'd0;

    reg signed [15:0] previous_sample;
    reg previous_valid;

    reg signed [15:0] max_left;
    reg signed [15:0] max_center;
    reg signed [15:0] max_right;
    reg max_wait_right;
    reg max_left_valid;
    reg max_triplet_valid;

    reg signed [15:0] min_left;
    reg signed [15:0] min_center;
    reg signed [15:0] min_right;
    reg min_wait_right;
    reg min_left_valid;
    reg min_triplet_valid;

    reg signed [15:0] max_left_next;
    reg signed [15:0] max_center_next;
    reg signed [15:0] max_right_next;
    reg max_wait_right_next;
    reg max_left_valid_next;
    reg max_triplet_valid_next;
    reg signed [15:0] min_left_next;
    reg signed [15:0] min_center_next;
    reg signed [15:0] min_right_next;
    reg min_wait_right_next;
    reg min_left_valid_next;
    reg min_triplet_valid_next;

    always @* begin
        max_left_next = max_left;
        max_center_next = max_center;
        max_right_next = max_right;
        max_wait_right_next = max_wait_right;
        max_left_valid_next = max_left_valid;
        max_triplet_valid_next = max_triplet_valid;

        min_left_next = min_left;
        min_center_next = min_center;
        min_right_next = min_right;
        min_wait_right_next = min_wait_right;
        min_left_valid_next = min_left_valid;
        min_triplet_valid_next = min_triplet_valid;

        if (sample_valid) begin
            // Keep the first occurrence of an equal quantized extremum.  A
            // later equal sample must not replace an already complete
            // triplet with an unresolved one at the measurement boundary.
            if ($signed(sample_in) > max_center) begin
                max_left_next = previous_valid ? previous_sample : sample_in;
                max_center_next = sample_in;
                max_right_next = sample_in;
                max_wait_right_next = 1'b1;
                max_left_valid_next = previous_valid;
                max_triplet_valid_next = 1'b0;
            end else if (max_wait_right) begin
                max_right_next = sample_in;
                max_wait_right_next = 1'b0;
                max_triplet_valid_next = max_left_valid;
            end

            if ($signed(sample_in) < min_center) begin
                min_left_next = previous_valid ? previous_sample : sample_in;
                min_center_next = sample_in;
                min_right_next = sample_in;
                min_wait_right_next = 1'b1;
                min_left_valid_next = previous_valid;
                min_triplet_valid_next = 1'b0;
            end else if (min_wait_right) begin
                min_right_next = sample_in;
                min_wait_right_next = 1'b0;
                min_triplet_valid_next = min_left_valid;
            end
        end
    end

    reg signed [15:0] max_left_pending;
    reg signed [15:0] max_center_pending;
    reg signed [15:0] max_right_pending;
    reg max_triplet_pending;
    reg signed [15:0] min_left_pending;
    reg signed [15:0] min_center_pending;
    reg signed [15:0] min_right_pending;
    reg min_triplet_pending;
    reg clip_pending;
    reg clip_accumulator;
    reg process_pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_count       <= 16'd0;
            sum_squares        <= 47'd0;
            sum_samples        <= 33'sd0;
            previous_sample    <= 16'sd0;
            previous_valid     <= 1'b0;
            max_left           <= -16'sd32768;
            max_center         <= -16'sd32768;
            max_right          <= -16'sd32768;
            max_wait_right     <= 1'b0;
            max_left_valid     <= 1'b0;
            max_triplet_valid  <= 1'b0;
            min_left           <= 16'sd32767;
            min_center         <= 16'sd32767;
            min_right          <= 16'sd32767;
            min_wait_right     <= 1'b0;
            min_left_valid     <= 1'b0;
            min_triplet_valid  <= 1'b0;
            max_left_pending   <= 16'sd0;
            max_center_pending <= 16'sd0;
            max_right_pending  <= 16'sd0;
            max_triplet_pending <= 1'b0;
            min_left_pending   <= 16'sd0;
            min_center_pending <= 16'sd0;
            min_right_pending  <= 16'sd0;
            min_triplet_pending <= 1'b0;
            clip_pending       <= 1'b0;
            clip_accumulator   <= 1'b0;
            process_pending    <= 1'b0;
        end else begin
            // A one-clock request pulse is independent of whether another
            // sample arrives.  This prevents a stopped input stream from
            // repeatedly post-processing the same completed window.
            process_pending <= 1'b0;
            if (sample_valid) begin
                previous_sample <= sample_in;
                previous_valid  <= 1'b1;

            max_left          <= max_left_next;
            max_center        <= max_center_next;
            max_right         <= max_right_next;
            max_wait_right    <= max_wait_right_next;
            max_left_valid    <= max_left_valid_next;
            max_triplet_valid <= max_triplet_valid_next;
            min_left          <= min_left_next;
            min_center        <= min_center_next;
            min_right         <= min_right_next;
            min_wait_right    <= min_wait_right_next;
            min_left_valid    <= min_left_valid_next;
            min_triplet_valid <= min_triplet_valid_next;

                if (sample_bad || (sample_in == 16'sh7FFF) ||
                    (sample_in == -16'sd32768))
                    clip_accumulator <= 1'b1;

            if (sample_count == 16'hFFFF) begin
                sample_count <= 16'd0;
                sum_squares  <= 47'd0;
                sum_samples  <= 33'sd0;

                max_left_pending   <= max_left_next;
                max_center_pending <= max_center_next;
                max_right_pending  <= max_right_next;
                max_triplet_pending <= max_triplet_valid_next &&
                                       !max_wait_right_next;
                min_left_pending   <= min_left_next;
                min_center_pending <= min_center_next;
                min_right_pending  <= min_right_next;
                min_triplet_pending <= min_triplet_valid_next &&
                                       !min_wait_right_next;
                clip_pending <= clip_accumulator || sample_bad ||
                    (sample_in == 16'sh7FFF) ||
                    (sample_in == -16'sd32768);
                process_pending <= 1'b1;

                // Start the next measurement window independently while the
                // just-completed window is post-processed.
                previous_valid    <= 1'b0;
                max_left          <= -16'sd32768;
                max_center        <= -16'sd32768;
                max_right         <= -16'sd32768;
                max_wait_right    <= 1'b0;
                max_left_valid    <= 1'b0;
                max_triplet_valid <= 1'b0;
                min_left          <= 16'sd32767;
                min_center        <= 16'sd32767;
                min_right         <= 16'sd32767;
                min_wait_right    <= 1'b0;
                min_left_valid    <= 1'b0;
                min_triplet_valid <= 1'b0;
                clip_accumulator  <= 1'b0;
            end else begin
                sample_count <= sample_count + 16'd1;
                sum_squares  <= sum_squares_with_sample;
                sum_samples  <= sum_samples_with_sample;
            end
            end
        end
    end

    reg [63:0] rms_radicand_pending;
    always @(posedge clk) begin
        if (!rst_n)
            rms_radicand_pending <= 64'd0;
        else if (sample_valid && (sample_count == 16'hFFFF))
            rms_radicand_pending <= {17'd0, ac_energy_with_sample};
    end

    wire signed [16:0] max_side_difference;
    wire signed [17:0] max_curvature_signed;
    wire signed [16:0] min_side_difference;
    wire signed [17:0] min_curvature_signed;
    wire signed [16:0] max_left_extended;
    wire signed [16:0] max_right_extended;
    wire signed [16:0] min_left_extended;
    wire signed [16:0] min_right_extended;
    wire signed [17:0] max_left_curvature;
    wire signed [17:0] max_center_curvature;
    wire signed [17:0] max_right_curvature;
    wire signed [17:0] min_left_curvature;
    wire signed [17:0] min_center_curvature;
    wire signed [17:0] min_right_curvature;
    wire [33:0] max_difference_square;
    wire [33:0] min_difference_square;
    wire [23:0] max_divisor;
    wire [23:0] min_divisor;
    wire max_correction_allowed;
    wire min_correction_allowed;
    wire [47:0] max_dividend;
    wire [47:0] min_dividend;

    // Extend before subtraction/shift.  In Verilog, the result width is the
    // operand width, so shifting the original signed 16-bit value directly
    // would silently wrap at the ADC rails.
    assign max_left_extended  = {max_left_pending[15], max_left_pending};
    assign max_right_extended = {max_right_pending[15], max_right_pending};
    assign min_left_extended  = {min_left_pending[15], min_left_pending};
    assign min_right_extended = {min_right_pending[15], min_right_pending};
    assign max_side_difference = max_left_extended - max_right_extended;
    assign min_side_difference = min_left_extended - min_right_extended;

    assign max_left_curvature =
        {{2{max_left_pending[15]}}, max_left_pending};
    assign max_center_curvature =
        {{2{max_center_pending[15]}}, max_center_pending};
    assign max_right_curvature =
        {{2{max_right_pending[15]}}, max_right_pending};
    assign min_left_curvature =
        {{2{min_left_pending[15]}}, min_left_pending};
    assign min_center_curvature =
        {{2{min_center_pending[15]}}, min_center_pending};
    assign min_right_curvature =
        {{2{min_right_pending[15]}}, min_right_pending};
    assign max_curvature_signed =
        (max_center_curvature <<< 1) -
        max_left_curvature - max_right_curvature;
    assign min_curvature_signed =
        min_left_curvature + min_right_curvature -
        (min_center_curvature <<< 1);
    assign max_difference_square =
        $signed(max_side_difference) * $signed(max_side_difference);
    assign min_difference_square =
        $signed(min_side_difference) * $signed(min_side_difference);
    assign max_divisor = {6'd0, max_curvature_signed[17:0]} << 3;
    assign min_divisor = {6'd0, min_curvature_signed[17:0]} << 3;
    assign max_correction_allowed = max_triplet_pending &&
        !max_curvature_signed[17] && (max_curvature_signed != 18'sd0) &&
        ($signed(max_center_pending) >= $signed(max_left_pending)) &&
        ($signed(max_center_pending) >= $signed(max_right_pending));
    assign min_correction_allowed = min_triplet_pending &&
        !min_curvature_signed[17] && (min_curvature_signed != 18'sd0) &&
        ($signed(min_center_pending) <= $signed(min_left_pending)) &&
        ($signed(min_center_pending) <= $signed(min_right_pending));
    assign max_dividend = max_correction_allowed ?
        ({14'd0, max_difference_square} << 8) +
        {25'd0, max_divisor[23:1]} : 48'd0;
    assign min_dividend = min_correction_allowed ?
        ({14'd0, min_difference_square} << 8) +
        {25'd0, min_divisor[23:1]} : 48'd0;

    reg postprocess_start;
    wire [31:0] rms_root;
    wire rms_root_valid;
    wire rms_root_busy;
    wire [47:0] max_correction_quotient;
    wire [47:0] min_correction_quotient;
    wire [23:0] unused_max_remainder;
    wire [23:0] unused_min_remainder;
    wire max_div_valid;
    wire min_div_valid;
    wire max_div_busy;
    wire min_div_busy;

    integer_sqrt_u64 u_rms_sqrt (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (postprocess_start),
        .radicand (rms_radicand_pending),
        .root     (rms_root),
        .valid    (rms_root_valid),
        .busy     (rms_root_busy)
    );

    unsigned_divider_48_24 u_max_correction_divider (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (postprocess_start),
        .numerator     (max_dividend),
        .denominator   (max_correction_allowed ? max_divisor : 24'd1),
        .quotient      (max_correction_quotient),
        .remainder_out (unused_max_remainder),
        .valid         (max_div_valid),
        .busy          (max_div_busy)
    );

    unsigned_divider_48_24 u_min_correction_divider (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (postprocess_start),
        .numerator     (min_dividend),
        .denominator   (min_correction_allowed ? min_divisor : 24'd1),
        .quotient      (min_correction_quotient),
        .remainder_out (unused_min_remainder),
        .valid         (min_div_valid),
        .busy          (min_div_busy)
    );

    reg [23:0] rms_q8_hold;
    reg rms_done;
    reg [23:0] max_correction_q8_hold;
    reg [23:0] min_correction_q8_hold;
    reg max_div_done;
    reg min_div_done;
    reg result_waiting;

    wire signed [24:0] max_center_q8;
    wire signed [24:0] min_center_q8;
    wire signed [24:0] max_vertex_q8;
    wire signed [24:0] min_vertex_q8;
    wire [24:0] calculated_vpp_q8;
    wire [56:0] calculated_vpp_mv_product;
    wire [55:0] calculated_rms_mv_product;
    wire [28:0] calculated_vpp_mv_wide;
    wire [27:0] calculated_rms_mv_wide;

    assign max_center_q8 =
        $signed({{9{max_center_pending[15]}}, max_center_pending}) <<< 8;
    assign min_center_q8 =
        $signed({{9{min_center_pending[15]}}, min_center_pending}) <<< 8;
    assign max_vertex_q8 = max_center_q8 +
        $signed({1'b0, max_correction_q8_hold});
    assign min_vertex_q8 = min_center_q8 -
        $signed({1'b0, min_correction_q8_hold});
    assign calculated_vpp_q8 = max_vertex_q8 - min_vertex_q8;
    assign calculated_vpp_mv_product =
        calculated_vpp_q8 * MV_PER_CODE_Q20;
    assign calculated_rms_mv_product =
        rms_q8_hold * MV_PER_CODE_Q20;
    assign calculated_vpp_mv_wide =
        (calculated_vpp_mv_product + 57'd134217728) >> 28;
    assign calculated_rms_mv_wide =
        (calculated_rms_mv_product + 56'd134217728) >> 28;

    always @(posedge clk) begin
        if (!rst_n) begin
            postprocess_start        <= 1'b0;
            rms_q8_hold              <= 24'd0;
            rms_done                 <= 1'b0;
            max_correction_q8_hold   <= 24'd0;
            min_correction_q8_hold   <= 24'd0;
            max_div_done             <= 1'b0;
            min_div_done             <= 1'b0;
            result_waiting           <= 1'b0;
            vpp_codes_q8             <= 25'd0;
            rms_codes_q8             <= 24'd0;
            vpp_codes                <= 17'd0;
            rms_codes                <= 16'd0;
            vpp_mv                   <= 16'd0;
            rms_mv                   <= 16'd0;
            measurement_clip         <= 1'b0;
            measurement_valid        <= 1'b0;
        end else begin
            postprocess_start <= 1'b0;
            measurement_valid <= 1'b0;

            if (process_pending && !result_waiting) begin
                postprocess_start      <= 1'b1;
                result_waiting         <= 1'b1;
                rms_done               <= 1'b0;
                max_div_done           <= 1'b0;
                min_div_done           <= 1'b0;
                max_correction_q8_hold <= 24'd0;
                min_correction_q8_hold <= 24'd0;
            end

            if (rms_root_valid) begin
                rms_q8_hold <= rms_root[23:0];
                rms_done    <= 1'b1;
            end
            if (max_div_valid) begin
                max_correction_q8_hold <=
                    (max_correction_quotient > 48'h000000FFFFFF) ?
                    24'hFFFFFF : max_correction_quotient[23:0];
                max_div_done <= 1'b1;
            end
            if (min_div_valid) begin
                min_correction_q8_hold <=
                    (min_correction_quotient > 48'h000000FFFFFF) ?
                    24'hFFFFFF : min_correction_quotient[23:0];
                min_div_done <= 1'b1;
            end

            if (result_waiting && rms_done && max_div_done && min_div_done) begin
                vpp_codes_q8 <= calculated_vpp_q8;
                rms_codes_q8 <= rms_q8_hold;
                vpp_codes <= (calculated_vpp_q8 + 25'd128) >> 8;
                rms_codes <= (rms_q8_hold + 24'd128) >> 8;
                vpp_mv <= (calculated_vpp_mv_wide > 29'd65535) ?
                          16'hFFFF : calculated_vpp_mv_wide[15:0];
                rms_mv <= (calculated_rms_mv_wide > 28'd65535) ?
                          16'hFFFF : calculated_rms_mv_wide[15:0];
                measurement_clip  <= clip_pending;
                measurement_valid <= 1'b1;
                result_waiting    <= 1'b0;
            end
        end
    end

endmodule
