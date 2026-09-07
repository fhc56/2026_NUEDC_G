`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: peak_detector_3
// Function:
//   Detect local maxima in bins BIN_START..BIN_END, merge candidates within
//   MIN_DISTANCE bins, retain the three strongest distinct peaks, and report
//   them in ascending frequency/bin order at end of frame.
// Clock domain: clk.
// Input power: unsigned 64-bit Re^2+Im^2.
// Input advances only on spectrum_valid && spectrum_ready.
//------------------------------------------------------------------------------
module peak_detector_3 #(
    // A 10 kHz tone lies at fractional bin 20.48. Include bin 20 so the
    // nearest-bin local maximum is not discarded at the lower band edge.
    parameter [12:0] BIN_START = 13'd20,
    parameter [12:0] BIN_END = 13'd1024,
    // The five-term flat-top main lobe spans roughly +/-5 bins.  Merging
    // local maxima within eight bins prevents one component from being
    // reported more than once.  The closest legal fundamental/harmonic pair
    // is 10 kHz apart (about 20.48 bins), so real components stay distinct.
    parameter [12:0] MIN_DISTANCE = 13'd8,
    // A candidate must exceed both thresholds at frame end. With the default
    // relative shift, accepted power is at least 1/8192 of the strongest
    // peak (about -39.1 dB in power). The absolute threshold is deliberately
    // parameterized for later board-specific noise-floor calibration.
    parameter [63:0] MIN_ABSOLUTE_POWER = 64'd100000,
    parameter integer RELATIVE_POWER_SHIFT = 13
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [63:0]   spectrum_power,
    input  wire [12:0]   spectrum_bin,
    input  wire          spectrum_valid,
    input  wire          spectrum_last,
    output wire          spectrum_ready,

    output reg  [12:0]   peak1_bin,
    output reg  [63:0]   peak1_power,
    output reg  [12:0]   peak2_bin,
    output reg  [63:0]   peak2_power,
    output reg  [12:0]   peak3_bin,
    output reg  [63:0]   peak3_power,
    output reg  [1:0]    peak_count,
    output reg           peak_result_valid
);

    reg [63:0] previous2_power;
    reg [63:0] previous_power;
    reg [12:0] previous_bin;
    reg previous2_valid;
    reg previous_valid;

    reg [12:0] candidate1_bin;
    reg [63:0] candidate1_power;
    reg [12:0] candidate2_bin;
    reg [63:0] candidate2_power;
    reg [12:0] candidate3_bin;
    reg [63:0] candidate3_power;
    reg [1:0]  candidate_count;

    wire input_fire;
    wire local_maximum;
    wire candidate_in_range;
    wire close_to_1;
    wire close_to_2;
    wire close_to_3;
    wire [63:0] relative_power_threshold;
    wire [63:0] effective_power_threshold;
    wire significant_candidate_1;
    wire significant_candidate_2;
    wire significant_candidate_3;
    wire [1:0] significant_count;

    assign spectrum_ready = 1'b1;
    assign input_fire = spectrum_valid && spectrum_ready;
    assign local_maximum = previous2_valid && previous_valid &&
                           (previous_power > previous2_power) &&
                           (previous_power >= spectrum_power);
    assign candidate_in_range = (previous_bin >= BIN_START) &&
                                (previous_bin <= BIN_END);

    assign close_to_1 = (previous_bin + MIN_DISTANCE >= candidate1_bin) &&
                        (candidate1_bin + MIN_DISTANCE >= previous_bin);
    assign close_to_2 = (previous_bin + MIN_DISTANCE >= candidate2_bin) &&
                        (candidate2_bin + MIN_DISTANCE >= previous_bin);
    assign close_to_3 = (previous_bin + MIN_DISTANCE >= candidate3_bin) &&
                        (candidate3_bin + MIN_DISTANCE >= previous_bin);

    assign relative_power_threshold =
        candidate1_power >> RELATIVE_POWER_SHIFT;
    assign effective_power_threshold =
        (relative_power_threshold > MIN_ABSOLUTE_POWER) ?
        relative_power_threshold : MIN_ABSOLUTE_POWER;
    assign significant_candidate_1 =
        (candidate_count >= 1) &&
        (candidate1_power >= effective_power_threshold);
    assign significant_candidate_2 =
        (candidate_count >= 2) &&
        (candidate2_power >= effective_power_threshold);
    assign significant_candidate_3 =
        (candidate_count >= 3) &&
        (candidate3_power >= effective_power_threshold);
    assign significant_count = significant_candidate_3 ? 2'd3 :
                               significant_candidate_2 ? 2'd2 :
                               significant_candidate_1 ? 2'd1 : 2'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            previous2_power <= 64'd0;
            previous_power <= 64'd0;
            previous_bin <= 13'd0;
            previous2_valid <= 1'b0;
            previous_valid <= 1'b0;

            candidate1_bin <= 13'd0;
            candidate1_power <= 64'd0;
            candidate2_bin <= 13'd0;
            candidate2_power <= 64'd0;
            candidate3_bin <= 13'd0;
            candidate3_power <= 64'd0;
            candidate_count <= 2'd0;

            peak1_bin <= 13'd0;
            peak1_power <= 64'd0;
            peak2_bin <= 13'd0;
            peak2_power <= 64'd0;
            peak3_bin <= 13'd0;
            peak3_power <= 64'd0;
            peak_count <= 2'd0;
            peak_result_valid <= 1'b0;
        end else begin
            peak_result_valid <= 1'b0;

            if (input_fire) begin
                if (spectrum_bin == 13'd0) begin
                    previous2_valid <= 1'b0;
                    previous_valid <= 1'b0;
                end

                if (local_maximum && candidate_in_range) begin
                    if ((candidate_count >= 1) && close_to_1) begin
                        if (previous_power > candidate1_power) begin
                            candidate1_bin <= previous_bin;
                            candidate1_power <= previous_power;
                        end
                    end else if ((candidate_count >= 2) && close_to_2) begin
                        if (previous_power > candidate2_power) begin
                            // Keep the candidate registers amplitude-ranked
                            // even when a later bin within candidate2's main
                            // lobe becomes stronger than candidate1.
                            if (previous_power > candidate1_power) begin
                                candidate2_bin <= candidate1_bin;
                                candidate2_power <= candidate1_power;
                                candidate1_bin <= previous_bin;
                                candidate1_power <= previous_power;
                            end else begin
                                candidate2_bin <= previous_bin;
                                candidate2_power <= previous_power;
                            end
                        end
                    end else if ((candidate_count >= 3) && close_to_3) begin
                        if (previous_power > candidate3_power) begin
                            if (previous_power > candidate1_power) begin
                                candidate3_bin <= candidate2_bin;
                                candidate3_power <= candidate2_power;
                                candidate2_bin <= candidate1_bin;
                                candidate2_power <= candidate1_power;
                                candidate1_bin <= previous_bin;
                                candidate1_power <= previous_power;
                            end else if (previous_power > candidate2_power) begin
                                candidate3_bin <= candidate2_bin;
                                candidate3_power <= candidate2_power;
                                candidate2_bin <= previous_bin;
                                candidate2_power <= previous_power;
                            end else begin
                                candidate3_bin <= previous_bin;
                                candidate3_power <= previous_power;
                            end
                        end
                    end else if (previous_power > candidate1_power) begin
                        candidate3_bin <= candidate2_bin;
                        candidate3_power <= candidate2_power;
                        candidate2_bin <= candidate1_bin;
                        candidate2_power <= candidate1_power;
                        candidate1_bin <= previous_bin;
                        candidate1_power <= previous_power;
                        if (candidate_count < 3)
                            candidate_count <= candidate_count + 2'd1;
                    end else if (previous_power > candidate2_power) begin
                        candidate3_bin <= candidate2_bin;
                        candidate3_power <= candidate2_power;
                        candidate2_bin <= previous_bin;
                        candidate2_power <= previous_power;
                        if (candidate_count < 3)
                            candidate_count <= candidate_count + 2'd1;
                    end else if (previous_power > candidate3_power) begin
                        candidate3_bin <= previous_bin;
                        candidate3_power <= previous_power;
                        if (candidate_count < 3)
                            candidate_count <= candidate_count + 2'd1;
                    end
                end

                previous2_power <= previous_power;
                previous_power <= spectrum_power;
                previous_bin <= spectrum_bin;
                previous2_valid <= previous_valid;
                previous_valid <= 1'b1;

                if (spectrum_last) begin
                    peak_count <= significant_count;
                    peak_result_valid <= 1'b1;

                    // Candidate registers are amplitude-ranked. Convert them
                    // to ascending-bin order for the public result interface.
                    if (significant_count == 0) begin
                        peak1_bin <= 13'd0;
                        peak1_power <= 64'd0;
                        peak2_bin <= 13'd0;
                        peak2_power <= 64'd0;
                        peak3_bin <= 13'd0;
                        peak3_power <= 64'd0;
                    end else if (significant_count == 1) begin
                        peak1_bin <= candidate1_bin;
                        peak1_power <= candidate1_power;
                        peak2_bin <= 13'd0;
                        peak2_power <= 64'd0;
                        peak3_bin <= 13'd0;
                        peak3_power <= 64'd0;
                    end else if (significant_count == 2) begin
                        if (candidate1_bin <= candidate2_bin) begin
                            peak1_bin <= candidate1_bin;
                            peak1_power <= candidate1_power;
                            peak2_bin <= candidate2_bin;
                            peak2_power <= candidate2_power;
                        end else begin
                            peak1_bin <= candidate2_bin;
                            peak1_power <= candidate2_power;
                            peak2_bin <= candidate1_bin;
                            peak2_power <= candidate1_power;
                        end
                        peak3_bin <= 13'd0;
                        peak3_power <= 64'd0;
                    end else begin
                        if ((candidate1_bin <= candidate2_bin) &&
                            (candidate2_bin <= candidate3_bin)) begin
                            peak1_bin <= candidate1_bin;
                            peak1_power <= candidate1_power;
                            peak2_bin <= candidate2_bin;
                            peak2_power <= candidate2_power;
                            peak3_bin <= candidate3_bin;
                            peak3_power <= candidate3_power;
                        end else if ((candidate1_bin <= candidate3_bin) &&
                                     (candidate3_bin <= candidate2_bin)) begin
                            peak1_bin <= candidate1_bin;
                            peak1_power <= candidate1_power;
                            peak2_bin <= candidate3_bin;
                            peak2_power <= candidate3_power;
                            peak3_bin <= candidate2_bin;
                            peak3_power <= candidate2_power;
                        end else if ((candidate2_bin <= candidate1_bin) &&
                                     (candidate1_bin <= candidate3_bin)) begin
                            peak1_bin <= candidate2_bin;
                            peak1_power <= candidate2_power;
                            peak2_bin <= candidate1_bin;
                            peak2_power <= candidate1_power;
                            peak3_bin <= candidate3_bin;
                            peak3_power <= candidate3_power;
                        end else if ((candidate2_bin <= candidate3_bin) &&
                                     (candidate3_bin <= candidate1_bin)) begin
                            peak1_bin <= candidate2_bin;
                            peak1_power <= candidate2_power;
                            peak2_bin <= candidate3_bin;
                            peak2_power <= candidate3_power;
                            peak3_bin <= candidate1_bin;
                            peak3_power <= candidate1_power;
                        end else if ((candidate3_bin <= candidate1_bin) &&
                                     (candidate1_bin <= candidate2_bin)) begin
                            peak1_bin <= candidate3_bin;
                            peak1_power <= candidate3_power;
                            peak2_bin <= candidate1_bin;
                            peak2_power <= candidate1_power;
                            peak3_bin <= candidate2_bin;
                            peak3_power <= candidate2_power;
                        end else begin
                            peak1_bin <= candidate3_bin;
                            peak1_power <= candidate3_power;
                            peak2_bin <= candidate2_bin;
                            peak2_power <= candidate2_power;
                            peak3_bin <= candidate1_bin;
                            peak3_power <= candidate1_power;
                        end
                    end

                    candidate1_bin <= 13'd0;
                    candidate1_power <= 64'd0;
                    candidate2_bin <= 13'd0;
                    candidate2_power <= 64'd0;
                    candidate3_bin <= 13'd0;
                    candidate3_power <= 64'd0;
                    candidate_count <= 2'd0;
                end
            end
        end
    end

endmodule
