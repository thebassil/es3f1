`timescale 1ns / 1ps

module video_mux #
(
    parameter DATA_WIDTH = 24
)
(
    input  wire                   sel,   // 0 = single-pixel path, 1 = blur path

    input  wire [DATA_WIDTH-1:0]  a_vid_data,
    input  wire                   a_vid_hsync,
    input  wire                   a_vid_vsync,
    input  wire                   a_vid_VDE,

    input  wire [DATA_WIDTH-1:0]  b_vid_data,
    input  wire                   b_vid_hsync,
    input  wire                   b_vid_vsync,
    input  wire                   b_vid_VDE,

    output wire [DATA_WIDTH-1:0]  o_vid_data,
    output wire                   o_vid_hsync,
    output wire                   o_vid_vsync,
    output wire                   o_vid_VDE
);

    assign o_vid_data  = sel ? b_vid_data  : a_vid_data;
    assign o_vid_hsync = sel ? b_vid_hsync : a_vid_hsync;
    assign o_vid_vsync = sel ? b_vid_vsync : a_vid_vsync;
    assign o_vid_VDE   = sel ? b_vid_VDE   : a_vid_VDE;

endmodule