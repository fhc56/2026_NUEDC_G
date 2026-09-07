`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: uart_tx_byte
// Function: One-byte, 8-N-1 UART transmitter.
//
// The default integer divider is 521 clocks/bit.  At 60 MHz this produces
// 115163.15 baud (-0.032 percent from 115200), which is substantially closer
// than truncating the divider to 520 clocks/bit.
//
// Handshake:
//   data_in is accepted on a rising edge when data_valid && data_ready.
//   data_ready remains low until the complete stop bit has been transmitted.
//------------------------------------------------------------------------------
module uart_tx_byte #(
    parameter integer CLKS_PER_BIT = 521
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       data_valid,
    output wire       data_ready,
    output reg        uart_tx,
    output reg        busy
);

    reg [15:0] baud_counter;
    reg [3:0]  bit_index;
    reg [7:0]  data_latched;

    assign data_ready = ~busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            uart_tx       <= 1'b1;
            busy          <= 1'b0;
            baud_counter  <= 16'd0;
            bit_index     <= 4'd0;
            data_latched  <= 8'd0;
        end else if (!busy) begin
            uart_tx      <= 1'b1;
            baud_counter <= 16'd0;
            bit_index    <= 4'd0;

            if (data_valid) begin
                data_latched <= data_in;
                uart_tx      <= 1'b0; // start bit
                busy         <= 1'b1;
            end
        end else if (baud_counter == (CLKS_PER_BIT - 1)) begin
            baud_counter <= 16'd0;

            if (bit_index < 4'd8) begin
                // UART data bits are transmitted least-significant bit first.
                uart_tx  <= data_latched[bit_index];
                bit_index <= bit_index + 1'b1;
            end else if (bit_index == 4'd8) begin
                uart_tx   <= 1'b1; // stop bit
                bit_index <= 4'd9;
            end else begin
                // The stop bit has occupied one complete bit interval.
                uart_tx <= 1'b1;
                busy    <= 1'b0;
            end
        end else begin
            baud_counter <= baud_counter + 1'b1;
        end
    end

endmodule
