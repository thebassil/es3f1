`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 3x3 binary erosion for PCam / Zybo video pipeline
//
// Optimised version:
// - Thresholds incoming RGB to binary internally
// - Uses two 1-bit line buffers
// - Output is black/white
// - Border pixels output the thresholded image
//////////////////////////////////////////////////////////////////////////////////

module erosion3x3 #
(
    parameter DATA_WIDTH = 24,
    parameter IMG_WIDTH  = 1920,
    parameter THRESHOLD  = 8'd128
)
(
    input  wire                   clk,
    input  wire                   n_rst,

    input  wire [DATA_WIDTH-1:0]  i_vid_data,
    input  wire                   i_vid_hsync,
    input  wire                   i_vid_vsync,
    input  wire                   i_vid_VDE,

    output reg  [DATA_WIDTH-1:0]  o_vid_data,
    output reg                    o_vid_hsync,
    output reg                    o_vid_vsync,
    output reg                    o_vid_VDE
);

    localparam integer COL_CNT_W = (IMG_WIDTH <= 2) ? 2 : $clog2(IMG_WIDTH);

    //--------------------------------------------------------------------------
    // Threshold current RGB pixel to binary
    //--------------------------------------------------------------------------

    wire [7:0] r_in = i_vid_data[23:16];
    wire [7:0] g_in = i_vid_data[15:8];
    wire [7:0] b_in = i_vid_data[7:0];

    wire [9:0] gray_sum = {2'b00, r_in} + {2'b00, g_in} + {2'b00, b_in};
    wire [7:0] gray_pix = gray_sum / 3;
    wire       curr_bin = (gray_pix >= THRESHOLD);

    //--------------------------------------------------------------------------
    // Two 1-bit line buffers
    //--------------------------------------------------------------------------

    (* ram_style = "distributed" *) reg linebuf0 [0:IMG_WIDTH-1];
    (* ram_style = "distributed" *) reg linebuf1 [0:IMG_WIDTH-1];

    reg [COL_CNT_W-1:0] col_count;
    reg [1:0]           valid_rows;
    reg                 prev_vde;
    reg                 prev_vsync;

    wire prev_row_bin;
    wire prev2_row_bin;

    assign prev_row_bin  = linebuf0[col_count];
    assign prev2_row_bin = linebuf1[col_count];

    //--------------------------------------------------------------------------
    // 3x3 causal binary window
    //--------------------------------------------------------------------------

    reg top_0, top_1, top_2;
    reg mid_0, mid_1, mid_2;
    reg bot_0, bot_1, bot_2;

    // Window:
    // row y-2: top_1 top_2 prev2_row_bin
    // row y-1: mid_1 mid_2 prev_row_bin
    // row y  : bot_1 bot_2 curr_bin

    wire erosion_bit =
        top_1 & top_2 & prev2_row_bin &
        mid_1 & mid_2 & prev_row_bin  &
        bot_1 & bot_2 & curr_bin;

    wire [23:0] thresh_pixel  = curr_bin    ? 24'hFFFFFF : 24'h000000;
    wire [23:0] erosion_pixel = erosion_bit ? 24'hFFFFFF : 24'h000000;

    //--------------------------------------------------------------------------
    // Main streaming logic
    //--------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!n_rst) begin
            o_vid_data  <= {DATA_WIDTH{1'b0}};
            o_vid_hsync <= 1'b0;
            o_vid_vsync <= 1'b0;
            o_vid_VDE   <= 1'b0;

            col_count   <= {COL_CNT_W{1'b0}};
            valid_rows  <= 2'd0;
            prev_vde    <= 1'b0;
            prev_vsync  <= 1'b0;

            top_0 <= 1'b0; top_1 <= 1'b0; top_2 <= 1'b0;
            mid_0 <= 1'b0; mid_1 <= 1'b0; mid_2 <= 1'b0;
            bot_0 <= 1'b0; bot_1 <= 1'b0; bot_2 <= 1'b0;
        end
        else begin
            o_vid_hsync <= i_vid_hsync;
            o_vid_vsync <= i_vid_vsync;
            o_vid_VDE   <= i_vid_VDE;

            o_vid_data <= thresh_pixel;

            if (i_vid_vsync != prev_vsync) begin
                col_count  <= {COL_CNT_W{1'b0}};
                valid_rows <= 2'd0;

                top_0 <= 1'b0; top_1 <= 1'b0; top_2 <= 1'b0;
                mid_0 <= 1'b0; mid_1 <= 1'b0; mid_2 <= 1'b0;
                bot_0 <= 1'b0; bot_1 <= 1'b0; bot_2 <= 1'b0;

                o_vid_data <= thresh_pixel;
            end
            else if (i_vid_VDE) begin
                if ((valid_rows == 2) && (col_count >= 2))
                    o_vid_data <= erosion_pixel;
                else
                    o_vid_data <= thresh_pixel;

                top_0 <= top_1;
                top_1 <= top_2;
                top_2 <= prev2_row_bin;

                mid_0 <= mid_1;
                mid_1 <= mid_2;
                mid_2 <= prev_row_bin;

                bot_0 <= bot_1;
                bot_1 <= bot_2;
                bot_2 <= curr_bin;

                linebuf1[col_count] <= prev_row_bin;
                linebuf0[col_count] <= curr_bin;

                if (col_count == IMG_WIDTH - 1)
                    col_count <= {COL_CNT_W{1'b0}};
                else
                    col_count <= col_count + 1'b1;
            end
            else begin
                o_vid_data <= thresh_pixel;

                if (prev_vde) begin
                    col_count <= {COL_CNT_W{1'b0}};

                    top_0 <= 1'b0; top_1 <= 1'b0; top_2 <= 1'b0;
                    mid_0 <= 1'b0; mid_1 <= 1'b0; mid_2 <= 1'b0;
                    bot_0 <= 1'b0; bot_1 <= 1'b0; bot_2 <= 1'b0;

                    if (valid_rows < 2)
                        valid_rows <= valid_rows + 1'b1;
                end
            end

            prev_vde   <= i_vid_VDE;
            prev_vsync <= i_vid_vsync;
        end
    end

endmodule