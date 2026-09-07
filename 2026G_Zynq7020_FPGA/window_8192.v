`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: window_8192
// Function: 8192-point selectable BYPASS/HANN/FLAT-TOP window with
//           handshake-controlled address progression and signed 16-bit
//           rounded/saturated output.
// Clock domain: clk.
// Input/output format: signed 16-bit integer samples.
// Coefficients: Q1.15, read from hann_8192.mem. The four-cycle transaction
//               permits synchronous ROM/BRAM inference and is faster than the
//               4 MSPS input cadence on a 60 MHz clock.
// window_select: 2'b00=BYPASS, 2'b01=HANN, 2'b10=FLAT-TOP.
//------------------------------------------------------------------------------
module window_8192 #(
    parameter HANN_MEM_FILE = "hann_8192.mem",
    parameter FLATTOP_MEM_FILE = "flattop_8192.mem"
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [1:0]              window_select,
    input  wire signed [15:0]      s_data,
    input  wire                    s_valid,
    output wire                    s_ready,
    output reg  signed [15:0]      m_data,
    output reg                     m_valid,
    input  wire                    m_ready,
    output reg  [12:0]             window_index
);

    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_ROM    = 3'd1;
    localparam [2:0] STATE_MULT   = 3'd2;
    localparam [2:0] STATE_OUTPUT = 3'd3;

    reg [2:0] state;
    reg signed [15:0] sample_hold;
    reg signed [15:0] coefficient_hold;
    reg [1:0] mode_hold;
    reg signed [31:0] product_hold;
    reg        [32:0] product_magnitude;
    reg        [32:0] rounded_magnitude;
    reg signed [32:0] scaled_product;

    (* rom_style = "block" *) reg signed [15:0] hann_rom [0:8191];
    (* rom_style = "block" *) reg signed [15:0] flattop_rom [0:8191];

    initial begin
        $readmemh(HANN_MEM_FILE, hann_rom);
        $readmemh(FLATTOP_MEM_FILE, flattop_rom);
    end

    assign s_ready = (state == STATE_IDLE);

    always @* begin
        if (product_hold < 0)
            product_magnitude = -$signed({product_hold[31], product_hold});
        else
            product_magnitude = $signed({product_hold[31], product_hold});
        rounded_magnitude = product_magnitude + 33'd16384;
        if (product_hold < 0)
            scaled_product = -$signed(rounded_magnitude >> 15);
        else
            scaled_product = $signed(rounded_magnitude >> 15);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            sample_hold      <= 16'sd0;
            coefficient_hold <= 16'sd0;
            mode_hold        <= 2'b00;
            product_hold     <= 32'sd0;
            m_data           <= 16'sd0;
            m_valid          <= 1'b0;
            window_index     <= 13'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    m_valid <= 1'b0;
                    if (s_valid && s_ready) begin
                        sample_hold <= s_data;
                        mode_hold <= window_select;
                        if (window_select == 2'b01)
                            coefficient_hold <= hann_rom[window_index];
                        else if (window_select == 2'b10)
                            coefficient_hold <= flattop_rom[window_index];
                        else
                            coefficient_hold <= 16'sh7FFF;

                        if (window_index == 13'd8191)
                            window_index <= 13'd0;
                        else
                            window_index <= window_index + 13'd1;
                        state <= STATE_ROM;
                    end
                end

                STATE_ROM: begin
                    if (mode_hold == 2'b00)
                        product_hold <= $signed(sample_hold) * 16'sd32768;
                    else
                        product_hold <= $signed(sample_hold) *
                                        $signed(coefficient_hold);
                    state <= STATE_MULT;
                end

                STATE_MULT: begin
                    if (mode_hold == 2'b00)
                        m_data <= sample_hold;
                    else if (scaled_product > 33'sd32767)
                        m_data <= 16'sd32767;
                    else if (scaled_product < -33'sd32768)
                        m_data <= -16'sd32768;
                    else
                        m_data <= scaled_product[15:0];
                    m_valid <= 1'b1;
                    state <= STATE_OUTPUT;
                end

                STATE_OUTPUT: begin
                    if (m_valid && m_ready) begin
                        m_valid <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
