`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 3x3 box blur filter for PCam / Zybo video pipeline
//
// Notes:
// - 24-bit RGB input assumed: [23:16], [15:8], [7:0]
// - Designed for streamed video
// - Uses two internal line buffers (previous row and row before that)
// - Intentionally uses distributed RAM style so reads behave combinationally,
//   avoiding the likely same-cycle BRAM read bug from the previous version
// - Border pixels (first 2 rows / first 2 columns) pass through unchanged
// - Set IMG_WIDTH to your active horizontal resolution
//
// Current startup mode from your Vitis code is 1920x1080, so use IMG_WIDTH=1920.
//
//////////////////////////////////////////////////////////////////////////////////

module blur3x3 #
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

    //--------------------------------------------------------------------------
    // Two line buffers
    //--------------------------------------------------------------------------
    // IMPORTANT:
    // We intentionally avoid forcing block RAM here. The previous version's most
    // likely issue was assuming same-cycle BRAM reads. This version wants
    // combinational read behavior from inferred distributed RAM/LUTRAM.
    //--------------------------------------------------------------------------

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] linebuf0 [0:IMG_WIDTH-1];
    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] linebuf1 [0:IMG_WIDTH-1];

    // Current column index within active video
    reg [COL_CNT_W-1:0] col_count;

    // How many complete rows have we already filled into the line buffers?
    // 0 -> still on first row
    // 1 -> second row available
    // 2 -> full 3x3 filtering possible
    reg [1:0] valid_rows;

    reg prev_vde;
    reg prev_vsync;

    //--------------------------------------------------------------------------
    // Asynchronous reads from the two previous rows at the current column
    //--------------------------------------------------------------------------

    wire [DATA_WIDTH-1:0] prev_row_pixel;
    wire [DATA_WIDTH-1:0] prev2_row_pixel;

    assign prev_row_pixel  = linebuf0[col_count]; // row y-1 at current x
    assign prev2_row_pixel = linebuf1[col_count]; // row y-2 at current x

    //--------------------------------------------------------------------------
    // 3x3 causal window registers
    //
    // After shifting, the effective window is:
    //
    //   row y-2: top_1 top_2 prev2_row_pixel
    //   row y-1: mid_1 mid_2 prev_row_pixel
    //   row y  : bot_1 bot_2 i_vid_data
    //
    // This corresponds to columns x-2, x-1, x.
    //--------------------------------------------------------------------------

    reg [DATA_WIDTH-1:0] top_0, top_1, top_2;
    reg [DATA_WIDTH-1:0] mid_0, mid_1, mid_2;
    reg [DATA_WIDTH-1:0] bot_0, bot_1, bot_2;

    //--------------------------------------------------------------------------
    // Channel extraction for the "next" window
    //--------------------------------------------------------------------------

    wire [7:0] t0_r = top_1[23:16];
    wire [7:0] t1_r = top_2[23:16];
    wire [7:0] t2_r = prev2_row_pixel[23:16];

    wire [7:0] m0_r = mid_1[23:16];
    wire [7:0] m1_r = mid_2[23:16];
    wire [7:0] m2_r = prev_row_pixel[23:16];

    wire [7:0] b0_r = bot_1[23:16];
    wire [7:0] b1_r = bot_2[23:16];
    wire [7:0] b2_r = i_vid_data[23:16];

    wire [7:0] t0_g = top_1[15:8];
    wire [7:0] t1_g = top_2[15:8];
    wire [7:0] t2_g = prev2_row_pixel[15:8];

    wire [7:0] m0_g = mid_1[15:8];
    wire [7:0] m1_g = mid_2[15:8];
    wire [7:0] m2_g = prev_row_pixel[15:8];

    wire [7:0] b0_g = bot_1[15:8];
    wire [7:0] b1_g = bot_2[15:8];
    wire [7:0] b2_g = i_vid_data[15:8];

    wire [7:0] t0_b = top_1[7:0];
    wire [7:0] t1_b = top_2[7:0];
    wire [7:0] t2_b = prev2_row_pixel[7:0];

    wire [7:0] m0_b = mid_1[7:0];
    wire [7:0] m1_b = mid_2[7:0];
    wire [7:0] m2_b = prev_row_pixel[7:0];

    wire [7:0] b0_b = bot_1[7:0];
    wire [7:0] b1_b = bot_2[7:0];
    wire [7:0] b2_b = i_vid_data[7:0];

    // 9-pixel sums (max 9*255 = 2295, fits in 12 bits)
    wire [11:0] sum_r =
        {4'd0, t0_r} + {4'd0, t1_r} + {4'd0, t2_r} +
        {4'd0, m0_r} + {4'd0, m1_r} + {4'd0, m2_r} +
        {4'd0, b0_r} + {4'd0, b1_r} + {4'd0, b2_r};

    wire [11:0] sum_g =
        {4'd0, t0_g} + {4'd0, t1_g} + {4'd0, t2_g} +
        {4'd0, m0_g} + {4'd0, m1_g} + {4'd0, m2_g} +
        {4'd0, b0_g} + {4'd0, b1_g} + {4'd0, b2_g};

    wire [11:0] sum_b =
        {4'd0, t0_b} + {4'd0, t1_b} + {4'd0, t2_b} +
        {4'd0, m0_b} + {4'd0, m1_b} + {4'd0, m2_b} +
        {4'd0, b0_b} + {4'd0, b1_b} + {4'd0, b2_b};

    // Divide by 9 with small rounding bias
    function [7:0] div9_round;
        input [11:0] x;
        begin
            div9_round = (x + 12'd4) / 12'd9;
        end
    endfunction

    wire [23:0] blur_pixel = {
        div9_round(sum_r),
        div9_round(sum_g),
        div9_round(sum_b)
    };

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
            // Pass control signals through one register stage
            o_vid_hsync <= i_vid_hsync;
            o_vid_vsync <= i_vid_vsync;
            o_vid_VDE   <= i_vid_VDE;

            // Default output: pass-through
            o_vid_data <= i_vid_data;

            // Reset row/window state on any frame sync transition
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

            // Active video pixel
            else if (i_vid_VDE) begin
                // Once 2 prior rows and 2 prior columns exist, output blur
                if ((valid_rows == 2) && (col_count >= 2)) begin
                    o_vid_data <= blur_pixel;
                end
                else begin
                    o_vid_data <= i_vid_data;
                end

                // Shift the causal 3-wide window horizontally
                top_0 <= top_1;
                top_1 <= top_2;
                top_2 <= prev2_row_pixel;

                mid_0 <= mid_1;
                mid_1 <= mid_2;
                mid_2 <= prev_row_pixel;

                bot_0 <= bot_1;
                bot_1 <= bot_2;
                bot_2 <= i_vid_data;

                // Update the row buffers
                // linebuf0 stores previous row
                // linebuf1 stores row before that
                linebuf1[col_count] <= prev_row_pixel;
                linebuf0[col_count] <= i_vid_data;

                // Advance within active row
                if (col_count == IMG_WIDTH - 1)
                    col_count <= {COL_CNT_W{1'b0}};
                else
                    col_count <= col_count + 1'b1;
            end

            // Horizontal blanking / inactive video
            else begin
                o_vid_data <= i_vid_data;

                // Only act once at the end of an active row
                if (prev_vde) begin
                    col_count <= {COL_CNT_W{1'b0}};

                    // Clear horizontal window state for next row
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