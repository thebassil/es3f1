`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 3x3 sharpen / edge-enhance filter
//
// Kernel:
//   0 -1  0
//  -1  5 -1
//   0 -1  0
//
// Visual effect:
// - Keeps the normal image
// - Makes edges and detail look crisper
//////////////////////////////////////////////////////////////////////////////////

module sharpen3x3 #
(
    parameter DATA_WIDTH = 24,
    parameter IMG_WIDTH  = 1920
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

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] linebuf0 [0:IMG_WIDTH-1];
    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] linebuf1 [0:IMG_WIDTH-1];

    reg [COL_CNT_W-1:0] col_count;
    reg [1:0]           valid_rows;
    reg                 prev_vde;
    reg                 prev_vsync;

    wire [DATA_WIDTH-1:0] prev_row_pixel;
    wire [DATA_WIDTH-1:0] prev2_row_pixel;

    assign prev_row_pixel  = linebuf0[col_count];
    assign prev2_row_pixel = linebuf1[col_count];

    reg [DATA_WIDTH-1:0] top_0, top_1, top_2;
    reg [DATA_WIDTH-1:0] mid_0, mid_1, mid_2;
    reg [DATA_WIDTH-1:0] bot_0, bot_1, bot_2;

    // Window:
    // row y-2: top_1 top_2 prev2_row_pixel
    // row y-1: mid_1 mid_2 prev_row_pixel
    // row y  : bot_1 bot_2 i_vid_data
    //
    // centre = mid_2
    // north  = top_2
    // south  = bot_2
    // west   = mid_1
    // east   = prev_row_pixel

    wire [7:0] north_r  = top_2[23:16];
    wire [7:0] west_r   = mid_1[23:16];
    wire [7:0] center_r = mid_2[23:16];
    wire [7:0] east_r   = prev_row_pixel[23:16];
    wire [7:0] south_r  = bot_2[23:16];

    wire [7:0] north_g  = top_2[15:8];
    wire [7:0] west_g   = mid_1[15:8];
    wire [7:0] center_g = mid_2[15:8];
    wire [7:0] east_g   = prev_row_pixel[15:8];
    wire [7:0] south_g  = bot_2[15:8];

    wire [7:0] north_b  = top_2[7:0];
    wire [7:0] west_b   = mid_1[7:0];
    wire [7:0] center_b = mid_2[7:0];
    wire [7:0] east_b   = prev_row_pixel[7:0];
    wire [7:0] south_b  = bot_2[7:0];

    wire signed [11:0] sharp_r =
        ($signed({4'b0, center_r}) <<< 2) + $signed({4'b0, center_r}) -
        $signed({4'b0, north_r}) - $signed({4'b0, south_r}) -
        $signed({4'b0, west_r})  - $signed({4'b0, east_r});

    wire signed [11:0] sharp_g =
        ($signed({4'b0, center_g}) <<< 2) + $signed({4'b0, center_g}) -
        $signed({4'b0, north_g}) - $signed({4'b0, south_g}) -
        $signed({4'b0, west_g})  - $signed({4'b0, east_g});

    wire signed [11:0] sharp_b =
        ($signed({4'b0, center_b}) <<< 2) + $signed({4'b0, center_b}) -
        $signed({4'b0, north_b}) - $signed({4'b0, south_b}) -
        $signed({4'b0, west_b})  - $signed({4'b0, east_b});

    function [7:0] clamp8_signed;
        input signed [11:0] x;
        begin
            if (x < 0)
                clamp8_signed = 8'd0;
            else if (x > 12'd255)
                clamp8_signed = 8'd255;
            else
                clamp8_signed = x[7:0];
        end
    endfunction

    wire [23:0] sharpen_pixel = {
        clamp8_signed(sharp_r),
        clamp8_signed(sharp_g),
        clamp8_signed(sharp_b)
    };

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

            top_0 <= {DATA_WIDTH{1'b0}};
            top_1 <= {DATA_WIDTH{1'b0}};
            top_2 <= {DATA_WIDTH{1'b0}};
            mid_0 <= {DATA_WIDTH{1'b0}};
            mid_1 <= {DATA_WIDTH{1'b0}};
            mid_2 <= {DATA_WIDTH{1'b0}};
            bot_0 <= {DATA_WIDTH{1'b0}};
            bot_1 <= {DATA_WIDTH{1'b0}};
            bot_2 <= {DATA_WIDTH{1'b0}};
        end
        else begin
            o_vid_hsync <= i_vid_hsync;
            o_vid_vsync <= i_vid_vsync;
            o_vid_VDE   <= i_vid_VDE;
            o_vid_data  <= i_vid_data;

            if (i_vid_vsync != prev_vsync) begin
                col_count  <= {COL_CNT_W{1'b0}};
                valid_rows <= 2'd0;

                top_0 <= {DATA_WIDTH{1'b0}};
                top_1 <= {DATA_WIDTH{1'b0}};
                top_2 <= {DATA_WIDTH{1'b0}};
                mid_0 <= {DATA_WIDTH{1'b0}};
                mid_1 <= {DATA_WIDTH{1'b0}};
                mid_2 <= {DATA_WIDTH{1'b0}};
                bot_0 <= {DATA_WIDTH{1'b0}};
                bot_1 <= {DATA_WIDTH{1'b0}};
                bot_2 <= {DATA_WIDTH{1'b0}};

                o_vid_data <= i_vid_data;
            end
            else if (i_vid_VDE) begin
                if ((valid_rows == 2) && (col_count >= 2))
                    o_vid_data <= sharpen_pixel;
                else
                    o_vid_data <= i_vid_data;

                top_0 <= top_1;
                top_1 <= top_2;
                top_2 <= prev2_row_pixel;

                mid_0 <= mid_1;
                mid_1 <= mid_2;
                mid_2 <= prev_row_pixel;

                bot_0 <= bot_1;
                bot_1 <= bot_2;
                bot_2 <= i_vid_data;

                linebuf1[col_count] <= prev_row_pixel;
                linebuf0[col_count] <= i_vid_data;

                if (col_count == IMG_WIDTH - 1)
                    col_count <= {COL_CNT_W{1'b0}};
                else
                    col_count <= col_count + 1'b1;
            end
            else begin
                o_vid_data <= i_vid_data;

                if (prev_vde) begin
                    col_count <= {COL_CNT_W{1'b0}};

                    top_0 <= {DATA_WIDTH{1'b0}};
                    top_1 <= {DATA_WIDTH{1'b0}};
                    top_2 <= {DATA_WIDTH{1'b0}};
                    mid_0 <= {DATA_WIDTH{1'b0}};
                    mid_1 <= {DATA_WIDTH{1'b0}};
                    mid_2 <= {DATA_WIDTH{1'b0}};
                    bot_0 <= {DATA_WIDTH{1'b0}};
                    bot_1 <= {DATA_WIDTH{1'b0}};
                    bot_2 <= {DATA_WIDTH{1'b0}};

                    if (valid_rows < 2)
                        valid_rows <= valid_rows + 1'b1;
                end
            end

            prev_vde   <= i_vid_VDE;
            prev_vsync <= i_vid_vsync;
        end
    end

endmodule