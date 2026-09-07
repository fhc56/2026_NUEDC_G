`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: unsigned_divider_48_24
// Function: Portable restoring divider used only for the two parabolic
//           extremum corrections in waveform_metrics.
// Clock domain: clk. Quotient/remainder are valid 48 clocks after start.
//------------------------------------------------------------------------------
module unsigned_divider_48_24 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [47:0]  numerator,
    input  wire [23:0]  denominator,
    output reg  [47:0]  quotient,
    output reg  [23:0]  remainder_out,
    output reg          valid,
    output reg          busy
);

    reg [47:0] dividend_shift;
    reg [23:0] divisor_hold;
    reg [24:0] remainder_work;
    reg [47:0] quotient_work;
    reg [5:0]  iteration;

    reg [24:0] shifted_remainder;
    reg [24:0] next_remainder;
    reg [47:0] next_quotient;

    always @* begin
        shifted_remainder = {remainder_work[23:0], dividend_shift[47]};
        if (shifted_remainder >= {1'b0, divisor_hold}) begin
            next_remainder = shifted_remainder - {1'b0, divisor_hold};
            next_quotient = {quotient_work[46:0], 1'b1};
        end else begin
            next_remainder = shifted_remainder;
            next_quotient = {quotient_work[46:0], 1'b0};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dividend_shift <= 48'd0;
            divisor_hold    <= 24'd0;
            remainder_work  <= 25'd0;
            quotient_work   <= 48'd0;
            iteration       <= 6'd0;
            quotient        <= 48'd0;
            remainder_out   <= 24'd0;
            valid           <= 1'b0;
            busy            <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start && !busy) begin
                if (denominator == 24'd0) begin
                    quotient      <= 48'd0;
                    remainder_out <= numerator[23:0];
                    valid         <= 1'b1;
                    busy          <= 1'b0;
                end else begin
                    dividend_shift <= numerator;
                    divisor_hold    <= denominator;
                    remainder_work  <= 25'd0;
                    quotient_work   <= 48'd0;
                    iteration       <= 6'd0;
                    busy            <= 1'b1;
                end
            end else if (busy) begin
                dividend_shift <= {dividend_shift[46:0], 1'b0};
                remainder_work <= next_remainder;
                quotient_work  <= next_quotient;
                if (iteration == 6'd47) begin
                    quotient      <= next_quotient;
                    remainder_out <= next_remainder[23:0];
                    valid         <= 1'b1;
                    busy          <= 1'b0;
                end else begin
                    iteration <= iteration + 6'd1;
                end
            end
        end
    end

endmodule
