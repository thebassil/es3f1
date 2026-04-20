`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Video Compositor — replaces video_mux
//
// Receives three video feeds (original, path A, path B) and composites them
// based on comp_mode:
//   0 = full-screen filtered (branch_sel picks A or B)
//   1 = full-screen original (unfiltered)
//   2 = split-screen: left=original, right=filtered
//   3 = wipe (same logic as split, semantically distinct for auto-demo)
//   4 = ROI spotlight: filtered inside box, original outside
//   5 = edge-overlay: sobel edges (from B) overlaid on colour (from A)
//
// Position counters derived from orig_vid sync signals.
// All control inputs latched on vsync to prevent mid-frame tearing.
//////////////////////////////////////////////////////////////////////////////

module video_compositor #
(
    parameter DATA_WIDTH = 24,
    parameter IMG_WIDTH  = 1920,
    parameter IMG_HEIGHT = 1080
)
(
    input  wire                   clk,
    input  wire                   n_rst,

    // Original (unfiltered) — 0-cycle latency from v_axi4s_vid_out
    input  wire [DATA_WIDTH-1:0]  orig_vid_data,
    input  wire                   orig_vid_hsync,
    input  wire                   orig_vid_vsync,
    input  wire                   orig_vid_VDE,

    // Path A — colour_change output (1-cycle latency, registered)
    input  wire [DATA_WIDTH-1:0]  a_vid_data,
    input  wire                   a_vid_hsync,
    input  wire                   a_vid_vsync,
    input  wire                   a_vid_VDE,

    // Path B — multi_filter_select output (1-cycle sync latency, ~2-line data warmup)
    input  wire [DATA_WIDTH-1:0]  b_vid_data,
    input  wire                   b_vid_hsync,
    input  wire                   b_vid_vsync,
    input  wire                   b_vid_VDE,

    // Control inputs (directly from btn_ctrl / AXI GPIO)
    input  wire [2:0]             comp_mode,
    input  wire                   branch_sel,    // 0=path A, 1=path B
    input  wire [10:0]            wipe_pos,      // X position of vertical divider
    input  wire [10:0]            roi_x,
    input  wire [10:0]            roi_y,
    input  wire [10:0]            roi_w,
    input  wire [10:0]            roi_h,
    input  wire [7:0]             edge_thresh,   // sobel magnitude threshold for overlay

    // Output to rgb2dvi
    output reg  [DATA_WIDTH-1:0]  o_vid_data,
    output reg                    o_vid_hsync,
    output reg                    o_vid_vsync,
    output reg                    o_vid_VDE
);

    // -------------------------------------------------------------------------
    // Delay original data by 1 clock to align with path A's registered output
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] orig_data_d1;
    reg                  orig_hsync_d1;
    reg                  orig_vsync_d1;
    reg                  orig_VDE_d1;

    always @(posedge clk) begin
        if (!n_rst) begin
            orig_data_d1  <= {DATA_WIDTH{1'b0}};
            orig_hsync_d1 <= 1'b0;
            orig_vsync_d1 <= 1'b0;
            orig_VDE_d1   <= 1'b0;
        end else begin
            orig_data_d1  <= orig_vid_data;
            orig_hsync_d1 <= orig_vid_hsync;
            orig_vsync_d1 <= orig_vid_vsync;
            orig_VDE_d1   <= orig_vid_VDE;
        end
    end

    // -------------------------------------------------------------------------
    // Pixel position counters (derived from delayed original sync — aligned)
    // -------------------------------------------------------------------------
    reg [10:0] col;
    reg [10:0] row;
    reg        prev_VDE;
    reg        prev_vsync;

    always @(posedge clk) begin
        if (!n_rst) begin
            col        <= 11'd0;
            row        <= 11'd0;
            prev_VDE   <= 1'b0;
            prev_vsync <= 1'b0;
        end else begin
            prev_VDE   <= orig_VDE_d1;
            prev_vsync <= orig_vsync_d1;

            // Rising edge of vsync: reset row counter
            if (orig_vsync_d1 && !prev_vsync) begin
                row <= 11'd0;
            end
            // Falling edge of VDE (end of active line): increment row, reset col
            else if (!orig_VDE_d1 && prev_VDE) begin
                row <= row + 11'd1;
                col <= 11'd0;
            end
            // Active video: increment column
            else if (orig_VDE_d1) begin
                col <= col + 11'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Latch control signals on vsync to prevent mid-frame tearing
    // -------------------------------------------------------------------------
    reg [2:0]  mode_lat;
    reg        branch_lat;
    reg [10:0] wipe_lat;
    reg [10:0] roi_x_lat;
    reg [10:0] roi_y_lat;
    reg [10:0] roi_w_lat;
    reg [10:0] roi_h_lat;
    reg [7:0]  edge_thresh_lat;

    always @(posedge clk) begin
        if (!n_rst) begin
            mode_lat       <= 3'd0;
            branch_lat     <= 1'b0;
            wipe_lat       <= 11'd960;  // default: midpoint
            roi_x_lat      <= 11'd640;
            roi_y_lat      <= 11'd270;
            roi_w_lat      <= 11'd640;
            roi_h_lat      <= 11'd540;
            edge_thresh_lat <= 8'd64;
        end else if (orig_vsync_d1 && !prev_vsync) begin
            // Latch on vsync rising edge
            mode_lat       <= comp_mode;
            branch_lat     <= branch_sel;
            // Use sensible defaults when AXI GPIO is zero-initialized
            wipe_lat       <= (wipe_pos == 11'd0) ? 11'd960 : wipe_pos;
            roi_x_lat      <= (roi_x == 11'd0 && roi_w == 11'd0) ? 11'd640 : roi_x;
            roi_y_lat      <= (roi_y == 11'd0 && roi_h == 11'd0) ? 11'd270 : roi_y;
            roi_w_lat      <= (roi_w == 11'd0) ? 11'd640 : roi_w;
            roi_h_lat      <= (roi_h == 11'd0) ? 11'd540 : roi_h;
            edge_thresh_lat <= (edge_thresh == 8'd0) ? 8'd64 : edge_thresh;
        end
    end

    // -------------------------------------------------------------------------
    // Compositor output mux
    // -------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] filtered;
    assign filtered = branch_lat ? b_vid_data : a_vid_data;

    // ROI box boundary test
    wire in_roi;
    assign in_roi = (col >= roi_x_lat) &&
                    (col <  roi_x_lat + roi_w_lat) &&
                    (row >= roi_y_lat) &&
                    (row <  roi_y_lat + roi_h_lat);

    // Edge magnitude (sobel output is grayscale: R=G=B=edge)
    wire [7:0] edge_mag;
    assign edge_mag = b_vid_data[7:0];

    // Border guard for edge-overlay (sobel warmup region)
    wire in_sobel_border;
    assign in_sobel_border = (row < 11'd2) || (col < 11'd2);

    always @(posedge clk) begin
        if (!n_rst) begin
            o_vid_data  <= {DATA_WIDTH{1'b0}};
            o_vid_hsync <= 1'b0;
            o_vid_vsync <= 1'b0;
            o_vid_VDE   <= 1'b0;
        end else begin
            // Sync signals from path A (1-cycle delayed, matches our delayed original)
            o_vid_hsync <= a_vid_hsync;
            o_vid_vsync <= a_vid_vsync;
            o_vid_VDE   <= a_vid_VDE;

            case (mode_lat)
                3'd0: // Full-screen filtered
                    o_vid_data <= filtered;

                3'd1: // Full-screen original
                    o_vid_data <= orig_data_d1;

                3'd2: // Split-screen: left=original, right=filtered
                    o_vid_data <= (col < wipe_lat) ? orig_data_d1 : filtered;

                3'd3: // Wipe mode (same logic, distinct semantics for auto-demo)
                    o_vid_data <= (col < wipe_lat) ? orig_data_d1 : filtered;

                3'd4: // ROI spotlight
                    o_vid_data <= in_roi ? filtered : orig_data_d1;

                3'd5: // Edge-overlay / comic mode
                    begin
                        if (in_sobel_border)
                            o_vid_data <= a_vid_data;
                        else if (edge_mag > edge_thresh_lat)
                            o_vid_data <= {DATA_WIDTH{1'b1}}; // white edge outline
                        else
                            o_vid_data <= a_vid_data; // base colour from path A
                    end

                default:
                    o_vid_data <= filtered;
            endcase
        end
    end

endmodule
