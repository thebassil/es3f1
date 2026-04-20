`timescale 1ns / 1ps

module multi_filter_select #
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

    input  wire [3:0]             btn,

    output reg  [DATA_WIDTH-1:0]  o_vid_data,
    output reg                    o_vid_hsync,
    output reg                    o_vid_vsync,
    output reg                    o_vid_VDE
);

    // ------------------------------------------------------------------------
    // ADD SECOND: optimized sobel3x3
    // Uncomment once blur-only version is verified
    // ------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] sobel_data;
    wire                  sobel_hsync;
    wire                  sobel_vsync;
    wire                  sobel_VDE;

    sobel3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH)
    ) u_sobel (
        .clk(clk),
        .n_rst(n_rst),
        .i_vid_data(i_vid_data),
        .i_vid_hsync(i_vid_hsync),
        .i_vid_vsync(i_vid_vsync),
        .i_vid_VDE(i_vid_VDE),
        .o_vid_data(sobel_data),
        .o_vid_hsync(sobel_hsync),
        .o_vid_vsync(sobel_vsync),
        .o_vid_VDE(sobel_VDE)
    );

    // ------------------------------------------------------------------------
    // ADD THIRD: erosion3x3
    // Uncomment once Sobel version is verified
    // ------------------------------------------------------------------------

    wire [DATA_WIDTH-1:0] erode_data;
    wire                  erode_hsync;
    wire                  erode_vsync;
    wire                  erode_VDE;

    erosion3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .THRESHOLD(8'd128)
    ) u_erode (
        .clk(clk),
        .n_rst(n_rst),
        .i_vid_data(i_vid_data),
        .i_vid_hsync(i_vid_hsync),
        .i_vid_vsync(i_vid_vsync),
        .i_vid_VDE(i_vid_VDE),
        .o_vid_data(erode_data),
        .o_vid_hsync(erode_hsync),
        .o_vid_vsync(erode_vsync),
        .o_vid_VDE(erode_VDE)
    );

    // ------------------------------------------------------------------------
    // Optional fourth: sharpen3x3
    // Leave out unless everything else is stable
    // ------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] sharp_data;
    wire                  sharp_hsync;
    wire                  sharp_vsync;
    wire                  sharp_VDE;

    // ------------------------------------------------------------------------
    // Optional fourth: dilation3x3
    // Cheap and very visible
    // ------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] dilate_data;
    wire                  dilate_hsync;
    wire                  dilate_vsync;
    wire                  dilate_VDE;

    dilation3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .THRESHOLD(8'd128)
    ) u_dilate (
        .clk(clk),
        .n_rst(n_rst),
        .i_vid_data(i_vid_data),
        .i_vid_hsync(i_vid_hsync),
        .i_vid_vsync(i_vid_vsync),
        .i_vid_VDE(i_vid_VDE),
        .o_vid_data(dilate_data),
        .o_vid_hsync(dilate_hsync),
        .o_vid_vsync(dilate_vsync),
        .o_vid_VDE(dilate_VDE)
    );

    // ------------------------------------------------------------------------
    // Output select
    // btn[0] = blur
    // btn[1] = sobel   (later)
    // btn[2] = erosion (later)
    // btn[3] = spare
    // ------------------------------------------------------------------------

    always @(*) begin
        o_vid_data  = i_vid_data;
        o_vid_hsync = i_vid_hsync;
        o_vid_vsync = i_vid_vsync;
        o_vid_VDE   = i_vid_VDE;
    
        if (btn[0]) begin
            o_vid_data  = sobel_data;
            o_vid_hsync = sobel_hsync;
            o_vid_vsync = sobel_vsync;
            o_vid_VDE   = sobel_VDE;
        end
        else if (btn[1]) begin
            o_vid_data  = erode_data;
            o_vid_hsync = erode_hsync;
            o_vid_vsync = erode_vsync;
            o_vid_VDE   = erode_VDE;
        end
        else if (btn[2]) begin
            o_vid_data  = dilate_data;
            o_vid_hsync = dilate_hsync;
            o_vid_vsync = dilate_vsync;
            o_vid_VDE   = dilate_VDE;
        end
    end

endmodule