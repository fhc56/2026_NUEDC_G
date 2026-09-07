`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Module: measurement_uart
// Function:
//   Cache the latest completed spectrum result, combine it with a completed
//   waveform measurement, and transmit an atomic ASCII hexadecimal snapshot.
//
// Fixed 105-byte frame (uppercase hexadecimal):
//   $G,VP=hhhh,RM=hhhh,F0=hhhhhhhh,N=h,F1=hhhhhhhh,A1=hhhh,
//   F2=hhhhhhhh,A2=hhhh,F3=hhhhhhhh,A3=hhhh,ST=hh*hh\r\n
//
// Fields:
//   VP/RM/A1/A2/A3 : integer millivolts
//   F0/F1/F2/F3    : integer hertz
//   N               : number of detected components (0 through 3)
//   ST              : status flags
//
// Checksum:
//   XOR of bytes 1 through 99 inclusive, beginning at 'G' and ending at the
//   second ST hexadecimal digit.  '$', '*', checksum digits, CR, and LF are
//   excluded.
//
// Valid semantics:
//   update_valid is a one-clock pulse that refreshes the spectrum cache only.
//   result_valid is a one-clock pulse that freezes VP/RM/ST together with the
//   latest complete spectrum cache and requests a frame.  A simultaneous
//   update_valid/result_valid uses the spectrum values present on that edge.
//
// The first result is sent immediately.  Subsequent results are coalesced to
// the newest complete snapshot and frame starts are limited to 10 Hz by
// default.  Active-frame fields never change while bytes are being sent.
//------------------------------------------------------------------------------
module measurement_uart #(
    parameter integer UART_CLKS_PER_BIT      = 521,
    parameter integer UPDATE_INTERVAL_CLKS  = 6000000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] vpp_mv,
    input  wire [15:0] rms_mv,
    input  wire [31:0] base_hz,
    input  wire [31:0] f1_hz,
    input  wire [15:0] a1_mv,
    input  wire [31:0] f2_hz,
    input  wire [15:0] a2_mv,
    input  wire [31:0] f3_hz,
    input  wire [15:0] a3_mv,
    input  wire [1:0]  peak_count,
    input  wire [7:0]  status,
    input  wire        result_valid,
    input  wire        update_valid,

    output wire        uart_tx
);

    localparam [6:0] LAST_BYTE_INDEX = 7'd104;

    // Latest spectrum values.  They are only replaced by a completed spectrum
    // result, so a waveform result can never capture partially updated fields.
    reg [31:0] cache_base_hz;
    reg [31:0] cache_f1_hz;
    reg [15:0] cache_a1_mv;
    reg [31:0] cache_f2_hz;
    reg [15:0] cache_a2_mv;
    reg [31:0] cache_f3_hz;
    reg [15:0] cache_a3_mv;
    reg [1:0]  cache_peak_count;

    // A rate-limited request is kept here.  A newer complete result replaces
    // an older unsent request, avoiding a stale-frame backlog.
    reg [15:0] pending_vpp_mv;
    reg [15:0] pending_rms_mv;
    reg [31:0] pending_base_hz;
    reg [31:0] pending_f1_hz;
    reg [15:0] pending_a1_mv;
    reg [31:0] pending_f2_hz;
    reg [15:0] pending_a2_mv;
    reg [31:0] pending_f3_hz;
    reg [15:0] pending_a3_mv;
    reg [1:0]  pending_peak_count;
    reg [7:0]  pending_status;
    reg        pending_valid;

    // Immutable snapshot used by frame_data_byte for the active frame.
    reg [15:0] snapshot_vpp_mv;
    reg [15:0] snapshot_rms_mv;
    reg [31:0] snapshot_base_hz;
    reg [31:0] snapshot_f1_hz;
    reg [15:0] snapshot_a1_mv;
    reg [31:0] snapshot_f2_hz;
    reg [15:0] snapshot_a2_mv;
    reg [31:0] snapshot_f3_hz;
    reg [15:0] snapshot_a3_mv;
    reg [1:0]  snapshot_peak_count;
    reg [7:0]  snapshot_status;

    reg [31:0] cooldown_counter;
    reg [6:0]  byte_index;
    reg [7:0]  frame_checksum;
    reg        frame_active;

    wire [7:0] uart_byte_data;
    wire       uart_byte_valid;
    wire       uart_byte_ready;
    wire       uart_byte_busy;
    wire       uart_byte_fire;

    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin
            if (nibble < 4'd10)
                hex_ascii = 8'h30 + nibble;
            else
                hex_ascii = 8'h41 + (nibble - 4'd10);
        end
    endfunction

    // The explicit index map is intentionally kept close to the documented
    // protocol.  Indices 1..99 are exactly the checksum coverage interval.
    function [7:0] frame_data_byte;
        input [6:0] index;
        begin
            case (index)
                7'd0:   frame_data_byte = "$";
                7'd1:   frame_data_byte = "G";
                7'd2:   frame_data_byte = ",";
                7'd3:   frame_data_byte = "V";
                7'd4:   frame_data_byte = "P";
                7'd5:   frame_data_byte = "=";
                7'd6:   frame_data_byte = hex_ascii(snapshot_vpp_mv[15:12]);
                7'd7:   frame_data_byte = hex_ascii(snapshot_vpp_mv[11:8]);
                7'd8:   frame_data_byte = hex_ascii(snapshot_vpp_mv[7:4]);
                7'd9:   frame_data_byte = hex_ascii(snapshot_vpp_mv[3:0]);
                7'd10:  frame_data_byte = ",";
                7'd11:  frame_data_byte = "R";
                7'd12:  frame_data_byte = "M";
                7'd13:  frame_data_byte = "=";
                7'd14:  frame_data_byte = hex_ascii(snapshot_rms_mv[15:12]);
                7'd15:  frame_data_byte = hex_ascii(snapshot_rms_mv[11:8]);
                7'd16:  frame_data_byte = hex_ascii(snapshot_rms_mv[7:4]);
                7'd17:  frame_data_byte = hex_ascii(snapshot_rms_mv[3:0]);
                7'd18:  frame_data_byte = ",";
                7'd19:  frame_data_byte = "F";
                7'd20:  frame_data_byte = "0";
                7'd21:  frame_data_byte = "=";
                7'd22:  frame_data_byte = hex_ascii(snapshot_base_hz[31:28]);
                7'd23:  frame_data_byte = hex_ascii(snapshot_base_hz[27:24]);
                7'd24:  frame_data_byte = hex_ascii(snapshot_base_hz[23:20]);
                7'd25:  frame_data_byte = hex_ascii(snapshot_base_hz[19:16]);
                7'd26:  frame_data_byte = hex_ascii(snapshot_base_hz[15:12]);
                7'd27:  frame_data_byte = hex_ascii(snapshot_base_hz[11:8]);
                7'd28:  frame_data_byte = hex_ascii(snapshot_base_hz[7:4]);
                7'd29:  frame_data_byte = hex_ascii(snapshot_base_hz[3:0]);
                7'd30:  frame_data_byte = ",";
                7'd31:  frame_data_byte = "N";
                7'd32:  frame_data_byte = "=";
                7'd33:  frame_data_byte = hex_ascii({2'b00, snapshot_peak_count});
                7'd34:  frame_data_byte = ",";
                7'd35:  frame_data_byte = "F";
                7'd36:  frame_data_byte = "1";
                7'd37:  frame_data_byte = "=";
                7'd38:  frame_data_byte = hex_ascii(snapshot_f1_hz[31:28]);
                7'd39:  frame_data_byte = hex_ascii(snapshot_f1_hz[27:24]);
                7'd40:  frame_data_byte = hex_ascii(snapshot_f1_hz[23:20]);
                7'd41:  frame_data_byte = hex_ascii(snapshot_f1_hz[19:16]);
                7'd42:  frame_data_byte = hex_ascii(snapshot_f1_hz[15:12]);
                7'd43:  frame_data_byte = hex_ascii(snapshot_f1_hz[11:8]);
                7'd44:  frame_data_byte = hex_ascii(snapshot_f1_hz[7:4]);
                7'd45:  frame_data_byte = hex_ascii(snapshot_f1_hz[3:0]);
                7'd46:  frame_data_byte = ",";
                7'd47:  frame_data_byte = "A";
                7'd48:  frame_data_byte = "1";
                7'd49:  frame_data_byte = "=";
                7'd50:  frame_data_byte = hex_ascii(snapshot_a1_mv[15:12]);
                7'd51:  frame_data_byte = hex_ascii(snapshot_a1_mv[11:8]);
                7'd52:  frame_data_byte = hex_ascii(snapshot_a1_mv[7:4]);
                7'd53:  frame_data_byte = hex_ascii(snapshot_a1_mv[3:0]);
                7'd54:  frame_data_byte = ",";
                7'd55:  frame_data_byte = "F";
                7'd56:  frame_data_byte = "2";
                7'd57:  frame_data_byte = "=";
                7'd58:  frame_data_byte = hex_ascii(snapshot_f2_hz[31:28]);
                7'd59:  frame_data_byte = hex_ascii(snapshot_f2_hz[27:24]);
                7'd60:  frame_data_byte = hex_ascii(snapshot_f2_hz[23:20]);
                7'd61:  frame_data_byte = hex_ascii(snapshot_f2_hz[19:16]);
                7'd62:  frame_data_byte = hex_ascii(snapshot_f2_hz[15:12]);
                7'd63:  frame_data_byte = hex_ascii(snapshot_f2_hz[11:8]);
                7'd64:  frame_data_byte = hex_ascii(snapshot_f2_hz[7:4]);
                7'd65:  frame_data_byte = hex_ascii(snapshot_f2_hz[3:0]);
                7'd66:  frame_data_byte = ",";
                7'd67:  frame_data_byte = "A";
                7'd68:  frame_data_byte = "2";
                7'd69:  frame_data_byte = "=";
                7'd70:  frame_data_byte = hex_ascii(snapshot_a2_mv[15:12]);
                7'd71:  frame_data_byte = hex_ascii(snapshot_a2_mv[11:8]);
                7'd72:  frame_data_byte = hex_ascii(snapshot_a2_mv[7:4]);
                7'd73:  frame_data_byte = hex_ascii(snapshot_a2_mv[3:0]);
                7'd74:  frame_data_byte = ",";
                7'd75:  frame_data_byte = "F";
                7'd76:  frame_data_byte = "3";
                7'd77:  frame_data_byte = "=";
                7'd78:  frame_data_byte = hex_ascii(snapshot_f3_hz[31:28]);
                7'd79:  frame_data_byte = hex_ascii(snapshot_f3_hz[27:24]);
                7'd80:  frame_data_byte = hex_ascii(snapshot_f3_hz[23:20]);
                7'd81:  frame_data_byte = hex_ascii(snapshot_f3_hz[19:16]);
                7'd82:  frame_data_byte = hex_ascii(snapshot_f3_hz[15:12]);
                7'd83:  frame_data_byte = hex_ascii(snapshot_f3_hz[11:8]);
                7'd84:  frame_data_byte = hex_ascii(snapshot_f3_hz[7:4]);
                7'd85:  frame_data_byte = hex_ascii(snapshot_f3_hz[3:0]);
                7'd86:  frame_data_byte = ",";
                7'd87:  frame_data_byte = "A";
                7'd88:  frame_data_byte = "3";
                7'd89:  frame_data_byte = "=";
                7'd90:  frame_data_byte = hex_ascii(snapshot_a3_mv[15:12]);
                7'd91:  frame_data_byte = hex_ascii(snapshot_a3_mv[11:8]);
                7'd92:  frame_data_byte = hex_ascii(snapshot_a3_mv[7:4]);
                7'd93:  frame_data_byte = hex_ascii(snapshot_a3_mv[3:0]);
                7'd94:  frame_data_byte = ",";
                7'd95:  frame_data_byte = "S";
                7'd96:  frame_data_byte = "T";
                7'd97:  frame_data_byte = "=";
                7'd98:  frame_data_byte = hex_ascii(snapshot_status[7:4]);
                7'd99:  frame_data_byte = hex_ascii(snapshot_status[3:0]);
                7'd100: frame_data_byte = "*";
                7'd101: frame_data_byte = hex_ascii(frame_checksum[7:4]);
                7'd102: frame_data_byte = hex_ascii(frame_checksum[3:0]);
                7'd103: frame_data_byte = 8'h0D;
                7'd104: frame_data_byte = 8'h0A;
                default: frame_data_byte = 8'h3F;
            endcase
        end
    endfunction

    assign uart_byte_data  = frame_data_byte(byte_index);
    assign uart_byte_valid = frame_active;
    assign uart_byte_fire  = uart_byte_valid && uart_byte_ready;

    uart_tx_byte #(
        .CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_uart_tx_byte (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_in    (uart_byte_data),
        .data_valid (uart_byte_valid),
        .data_ready (uart_byte_ready),
        .uart_tx    (uart_tx),
        .busy       (uart_byte_busy)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            cache_base_hz        <= 32'd0;
            cache_f1_hz          <= 32'd0;
            cache_a1_mv          <= 16'd0;
            cache_f2_hz          <= 32'd0;
            cache_a2_mv          <= 16'd0;
            cache_f3_hz          <= 32'd0;
            cache_a3_mv          <= 16'd0;
            cache_peak_count     <= 2'd0;

            pending_vpp_mv       <= 16'd0;
            pending_rms_mv       <= 16'd0;
            pending_base_hz      <= 32'd0;
            pending_f1_hz        <= 32'd0;
            pending_a1_mv        <= 16'd0;
            pending_f2_hz        <= 32'd0;
            pending_a2_mv        <= 16'd0;
            pending_f3_hz        <= 32'd0;
            pending_a3_mv        <= 16'd0;
            pending_peak_count   <= 2'd0;
            pending_status       <= 8'd0;
            pending_valid        <= 1'b0;

            snapshot_vpp_mv      <= 16'd0;
            snapshot_rms_mv      <= 16'd0;
            snapshot_base_hz     <= 32'd0;
            snapshot_f1_hz       <= 32'd0;
            snapshot_a1_mv       <= 16'd0;
            snapshot_f2_hz       <= 32'd0;
            snapshot_a2_mv       <= 16'd0;
            snapshot_f3_hz       <= 32'd0;
            snapshot_a3_mv       <= 16'd0;
            snapshot_peak_count  <= 2'd0;
            snapshot_status      <= 8'd0;

            cooldown_counter     <= 32'd0;
            byte_index           <= 7'd0;
            frame_checksum       <= 8'd0;
            frame_active         <= 1'b0;
        end else begin
            if (cooldown_counter != 32'd0)
                cooldown_counter <= cooldown_counter - 1'b1;

            if (update_valid) begin
                cache_base_hz    <= base_hz;
                cache_f1_hz      <= f1_hz;
                cache_a1_mv      <= a1_mv;
                cache_f2_hz      <= f2_hz;
                cache_a2_mv      <= a2_mv;
                cache_f3_hz      <= f3_hz;
                cache_a3_mv      <= a3_mv;
                cache_peak_count <= peak_count;
            end

            // Capture an atomic pending result.  The spectrum cache is used
            // unless a new spectrum result arrives on this same clock edge.
            if (result_valid) begin
                pending_vpp_mv <= vpp_mv;
                pending_rms_mv <= rms_mv;
                pending_status <= status;
                if (update_valid) begin
                    pending_base_hz    <= base_hz;
                    pending_f1_hz      <= f1_hz;
                    pending_a1_mv      <= a1_mv;
                    pending_f2_hz      <= f2_hz;
                    pending_a2_mv      <= a2_mv;
                    pending_f3_hz      <= f3_hz;
                    pending_a3_mv      <= a3_mv;
                    pending_peak_count <= peak_count;
                end else begin
                    pending_base_hz    <= cache_base_hz;
                    pending_f1_hz      <= cache_f1_hz;
                    pending_a1_mv      <= cache_a1_mv;
                    pending_f2_hz      <= cache_f2_hz;
                    pending_a2_mv      <= cache_a2_mv;
                    pending_f3_hz      <= cache_f3_hz;
                    pending_a3_mv      <= cache_a3_mv;
                    pending_peak_count <= cache_peak_count;
                end
                pending_valid <= 1'b1;
            end

            // Start a frame whenever the rate limiter and byte transmitter are
            // both available.  result_valid has priority over an older pending
            // result so the newest complete snapshot is sent.
            if (!frame_active && !uart_byte_busy &&
                (cooldown_counter == 32'd0) &&
                (pending_valid || result_valid)) begin
                if (result_valid) begin
                    snapshot_vpp_mv <= vpp_mv;
                    snapshot_rms_mv <= rms_mv;
                    snapshot_status <= status;
                    if (update_valid) begin
                        snapshot_base_hz    <= base_hz;
                        snapshot_f1_hz      <= f1_hz;
                        snapshot_a1_mv      <= a1_mv;
                        snapshot_f2_hz      <= f2_hz;
                        snapshot_a2_mv      <= a2_mv;
                        snapshot_f3_hz      <= f3_hz;
                        snapshot_a3_mv      <= a3_mv;
                        snapshot_peak_count <= peak_count;
                    end else begin
                        snapshot_base_hz    <= cache_base_hz;
                        snapshot_f1_hz      <= cache_f1_hz;
                        snapshot_a1_mv      <= cache_a1_mv;
                        snapshot_f2_hz      <= cache_f2_hz;
                        snapshot_a2_mv      <= cache_a2_mv;
                        snapshot_f3_hz      <= cache_f3_hz;
                        snapshot_a3_mv      <= cache_a3_mv;
                        snapshot_peak_count <= cache_peak_count;
                    end
                end else begin
                    snapshot_vpp_mv     <= pending_vpp_mv;
                    snapshot_rms_mv     <= pending_rms_mv;
                    snapshot_base_hz    <= pending_base_hz;
                    snapshot_f1_hz      <= pending_f1_hz;
                    snapshot_a1_mv      <= pending_a1_mv;
                    snapshot_f2_hz      <= pending_f2_hz;
                    snapshot_a2_mv      <= pending_a2_mv;
                    snapshot_f3_hz      <= pending_f3_hz;
                    snapshot_a3_mv      <= pending_a3_mv;
                    snapshot_peak_count <= pending_peak_count;
                    snapshot_status     <= pending_status;
                end

                pending_valid    <= 1'b0;
                frame_active     <= 1'b1;
                byte_index       <= 7'd0;
                frame_checksum   <= 8'd0;
                if (UPDATE_INTERVAL_CLKS > 1)
                    cooldown_counter <= UPDATE_INTERVAL_CLKS - 1;
                else
                    cooldown_counter <= 32'd0;
            end

            if (uart_byte_fire) begin
                if ((byte_index >= 7'd1) && (byte_index <= 7'd99))
                    frame_checksum <= frame_checksum ^ uart_byte_data;

                if (byte_index == LAST_BYTE_INDEX) begin
                    frame_active <= 1'b0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end

endmodule
