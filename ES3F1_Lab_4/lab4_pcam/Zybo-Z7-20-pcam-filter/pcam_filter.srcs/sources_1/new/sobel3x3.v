`timescale 1ns / 1ps

module sobel3x3 #
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

    wire [7:0] r_in = i_vid_data[23:16];
    wire [7:0] g_in = i_vid_data[15:8];
    wire [7:0] b_in = i_vid_data[7:0];

    wire [9:0] gray_sum  = {2'b00, r_in} + {2'b00, g_in} + {2'b00, b_in};
    wire [7:0] curr_gray = gray_sum / 3;

    (* ram_style = "distributed" *) reg [7:0] linebuf0 [0:IMG_WIDTH-1];
    (* ram_style = "distributed" *) reg [7:0] linebuf1 [0:IMG_WIDTH-1];

    reg [COL_CNT_W-1:0] col_count;
    reg [1:0]           valid_rows;
    reg                 prev_vde;
    reg                 prev_vsync;

    wire [7:0] prev_row_gray;
    wire [7:0] prev2_row_gray;

    assign prev_row_gray  = linebuf0[col_count];
    assign prev2_row_gray = linebuf1[col_count];

    reg [7:0] top_0, top_1, top_2;
    reg [7:0] mid_0, mid_1, mid_2;
    reg [7:0] bot_0, bot_1, bot_2;

    wire [7:0] p00 = top_1;
    wire [7:0] p01 = top_2;
    wire [7:0] p02 = prev2_row_gray;

    wire [7:0] p10 = mid_1;
    wire [7:0] p11 = mid_2;
    wire [7:0] p12 = prev_row_gray;

    wire [7:0] p20 = bot_1;
    wire [7:0] p21 = bot_2;
    wire [7:0] p22 = curr_gray;

    wire signed [10:0] gx =
        -$signed({3'b000, p00}) +  $signed({3'b000, p02}) +
        -($signed({3'b000, p10}) <<< 1) + ($signed({3'b000, p12}) <<< 1) +
        -$signed({3'b000, p20}) +  $signed({3'b000, p22});

    wire signed [10:0] gy =
         $signed({3'b000, p00}) + ($signed({3'b000, p01}) <<< 1) + $signed({3'b000, p02}) -
         $signed({3'b000, p20}) - ($signed({3'b000, p21}) <<< 1) - $signed({3'b000, p22});

    wire [10:0] abs_gx = gx[10] ? -gx : gx;
    wire [10:0] abs_gy = gy[10] ? -gy : gy;

    wire [11:0] mag = abs_gx + abs_gy;

    wire [7:0] edge_pix = (mag > 12'd255) ? 8'hFF : mag[7:0];
    wire [23:0] sobel_pixel = {edge_pix, edge_pix, edge_pix};

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

            top_0 <= 8'd0; top_1 <= 8'd0; top_2 <= 8'd0;
            mid_0 <= 8'd0; mid_1 <= 8'd0; mid_2 <= 8'd0;
            bot_0 <= 8'd0; bot_1 <= 8'd0; bot_2 <= 8'd0;
        end
        else begin
            o_vid_hsync <= i_vid_hsync;
            o_vid_vsync <= i_vid_vsync;
            o_vid_VDE   <= i_vid_VDE;

            o_vid_data <= i_vid_data;

            if (i_vid_vsync != prev_vsync) begin
                col_count  <= {COL_CNT_W{1'b0}};
                valid_rows <= 2'd0;

                top_0 <= 8'd0; top_1 <= 8'd0; top_2 <= 8'd0;
                mid_0 <= 8'd0; mid_1 <= 8'd0; mid_2 <= 8'd0;
                bot_0 <= 8'd0; bot_1 <= 8'd0; bot_2 <= 8'd0;

                o_vid_data <= i_vid_data;
            end
            else if (i_vid_VDE) begin
                if ((valid_rows == 2) && (col_count >= 2))
                    o_vid_data <= sobel_pixel;
                else
                    o_vid_data <= i_vid_data;

                top_0 <= top_1;
                top_1 <= top_2;
                top_2 <= prev2_row_gray;

                mid_0 <= mid_1;
                mid_1 <= mid_2;
                mid_2 <= prev_row_gray;

                bot_0 <= bot_1;
                bot_1 <= bot_2;
                bot_2 <= curr_gray;

                linebuf1[col_count] <= prev_row_gray;
                linebuf0[col_count] <= curr_gray;

                if (col_count == IMG_WIDTH - 1)
                    col_count <= {COL_CNT_W{1'b0}};
                else
                    col_count <= col_count + 1'b1;
            end
            else begin
                o_vid_data <= i_vid_data;

                if (prev_vde) begin
                    col_count <= {COL_CNT_W{1'b0}};

                    top_0 <= 8'd0; top_1 <= 8'd0; top_2 <= 8'd0;
                    mid_0 <= 8'd0; mid_1 <= 8'd0; mid_2 <= 8'd0;
                    bot_0 <= 8'd0; bot_1 <= 8'd0; bot_2 <= 8'd0;

                    if (valid_rows < 2)
                        valid_rows <= valid_rows + 1'b1;
                end
            end

            prev_vde   <= i_vid_VDE;
            prev_vsync <= i_vid_vsync;
        end
    end

endmodule