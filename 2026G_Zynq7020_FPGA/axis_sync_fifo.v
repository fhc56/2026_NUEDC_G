`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: axis_sync_fifo
// Function: Portable single-clock AXI-stream-compatible FIFO.
// Clock domain: clk.
// Data format: opaque DATA_WIDTH bits.
// Notes:
//   - Count changes only on valid/ready handshakes.
//   - overflow is sticky when a producer presents data while full.
//   - AXI ready while empty is legal and is not an underflow. The underflow
//     output is retained for interface/debug compatibility and remains low.
//   - The asynchronous memory read favors portability and simple verification;
//     replace this module with AXI4-Stream Data FIFO if BRAM-only storage is
//     required without changing surrounding interfaces.
//------------------------------------------------------------------------------
module axis_sync_fifo #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 10
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [DATA_WIDTH-1:0]     s_data,
    input  wire                      s_valid,
    output wire                      s_ready,
    output wire [DATA_WIDTH-1:0]     m_data,
    output wire                      m_valid,
    input  wire                      m_ready,
    output reg  [ADDR_WIDTH:0]       level,
    output reg                       overflow,
    output reg                       underflow
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_pointer;
    reg [ADDR_WIDTH-1:0] read_pointer;

    wire write_fire;
    wire read_fire;

    assign s_ready = (level != DEPTH);
    assign m_valid = (level != 0);
    assign m_data = memory[read_pointer];
    assign write_fire = s_valid && s_ready;
    assign read_fire = m_valid && m_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            write_pointer <= {ADDR_WIDTH{1'b0}};
            read_pointer  <= {ADDR_WIDTH{1'b0}};
            level         <= {(ADDR_WIDTH+1){1'b0}};
            overflow      <= 1'b0;
            underflow     <= 1'b0;
        end else begin
            if (write_fire) begin
                memory[write_pointer] <= s_data;
                write_pointer <= write_pointer + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            end
            if (read_fire)
                read_pointer <= read_pointer + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};

            case ({write_fire, read_fire})
                2'b10: level <= level + {{ADDR_WIDTH{1'b0}}, 1'b1};
                2'b01: level <= level - {{ADDR_WIDTH{1'b0}}, 1'b1};
                default: level <= level;
            endcase

            if (s_valid && !s_ready)
                overflow <= 1'b1;
            underflow <= 1'b0;
        end
    end

endmodule
