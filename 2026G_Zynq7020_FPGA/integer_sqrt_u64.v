`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: integer_sqrt_u64
// Function: Unsigned floor(sqrt(radicand)) without vendor IP.
// Clock domain: clk. One result is produced 32 clocks after start is accepted.
// Data format: 64-bit unsigned radicand, 32-bit unsigned integer root.
//------------------------------------------------------------------------------
module integer_sqrt_u64 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [63:0]  radicand,
    output reg  [31:0]  root,
    output reg          valid,
    output reg          busy
);

    reg [63:0] radicand_shift;
    reg [33:0] remainder;
    reg [31:0] root_work;
    reg [5:0]  iteration;

    reg [33:0] shifted_remainder;
    reg [33:0] trial_divisor;
    reg [33:0] next_remainder;
    reg [31:0] next_root;

    always @* begin
        // Before every iteration the useful remainder fits in 32 bits. Bring
        // down the next radicand bit pair and try the restoring subtraction.
        shifted_remainder = {remainder[31:0], radicand_shift[63:62]};
        trial_divisor = {root_work, 2'b01};
        if (shifted_remainder >= trial_divisor) begin
            next_remainder = shifted_remainder - trial_divisor;
            next_root = {root_work[30:0], 1'b1};
        end else begin
            next_remainder = shifted_remainder;
            next_root = {root_work[30:0], 1'b0};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            radicand_shift <= 64'd0;
            remainder      <= 34'd0;
            root_work      <= 32'd0;
            iteration      <= 6'd0;
            root           <= 32'd0;
            valid          <= 1'b0;
            busy           <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start && !busy) begin
                radicand_shift <= radicand;
                remainder      <= 34'd0;
                root_work      <= 32'd0;
                iteration      <= 6'd0;
                busy           <= 1'b1;
            end else if (busy) begin
                radicand_shift <= {radicand_shift[61:0], 2'b00};
                remainder      <= next_remainder;
                root_work      <= next_root;
                if (iteration == 6'd31) begin
                    root  <= next_root;
                    valid <= 1'b1;
                    busy  <= 1'b0;
                end else begin
                    iteration <= iteration + 6'd1;
                end
            end
        end
    end

endmodule
