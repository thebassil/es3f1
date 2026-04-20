
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Simple single-pixel filter block for PCam/Zybo video pipeline
//
// Button mapping:
//   btn[0] = brightness + contrast boost
//   btn[1] = gamma correction (gamma ~= 2.0, darker)
//   btn[2] = binary threshold
//   btn[3] = invert colours (optional extra)
//
// Priority if multiple buttons are pressed at once:
//   btn[0] > btn[1] > btn[2] > btn[3]
//////////////////////////////////////////////////////////////////////////////////

module colour_change #
(
    parameter DATA_WIDTH = 24
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
    output reg                    o_vid_VDE,

    input  wire [3:0]             btn
);

    // Treat input as 8 bits per colour channel.
    // Kept generic so the same channel order is preserved on output.
    wire [7:0] ch2_in;
    wire [7:0] ch1_in;
    wire [7:0] ch0_in;

    assign ch2_in = i_vid_data[23:16];
    assign ch1_in = i_vid_data[15:8];
    assign ch0_in = i_vid_data[7:0];

    //--------------------------------------------------------------------------
    // Helper functions
    //--------------------------------------------------------------------------

    // Brightness + contrast boost:
    // out = saturate(1.5*x + 16)
    function [7:0] bright_contrast;
        input [7:0] x;
        reg   [9:0] tmp;
        begin
            tmp = ((x * 10'd3) >> 1) + 10'd16;
            if (tmp > 10'd255)
                bright_contrast = 8'hFF;
            else
                bright_contrast = tmp[7:0];
        end
    endfunction

    // Gamma correction with gamma ~= 2.0:
    // out ≈ x^2 / 255
    function [7:0] gamma2;
        input [7:0] x;
        reg   [15:0] tmp;
        begin
            tmp = (x * x) + 16'd255;   // small rounding bias
            gamma2 = tmp[15:8];
        end
    endfunction

    // Binary threshold using average intensity:
    // white if average >= 128, else black
    function [7:0] threshold_bin;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        reg   [9:0] sum;
        begin
            sum = {2'b00, a} + {2'b00, b} + {2'b00, c};
            if (sum >= 10'd384)        // 3 * 128
                threshold_bin = 8'hFF;
            else
                threshold_bin = 8'h00;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Precompute all filtered values
    //--------------------------------------------------------------------------

    wire [7:0] bc_ch2, bc_ch1, bc_ch0;
    wire [7:0] gm_ch2, gm_ch1, gm_ch0;
    wire [7:0] th_pix;

    assign bc_ch2 = bright_contrast(ch2_in);
    assign bc_ch1 = bright_contrast(ch1_in);
    assign bc_ch0 = bright_contrast(ch0_in);

    assign gm_ch2 = gamma2(ch2_in);
    assign gm_ch1 = gamma2(ch1_in);
    assign gm_ch0 = gamma2(ch0_in);

    assign th_pix = threshold_bin(ch2_in, ch1_in, ch0_in);

    //--------------------------------------------------------------------------
    // Registered video path
    //--------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!n_rst) begin
            o_vid_hsync <= 1'b0;
            o_vid_vsync <= 1'b0;
            o_vid_VDE   <= 1'b0;
            o_vid_data  <= {DATA_WIDTH{1'b0}};
        end
        else begin
            o_vid_hsync <= i_vid_hsync;
            o_vid_vsync <= i_vid_vsync;
            o_vid_VDE   <= i_vid_VDE;

            if (btn[0]) begin
                o_vid_data <= {bc_ch2, bc_ch1, bc_ch0};
            end
            else if (btn[1]) begin
                o_vid_data <= {gm_ch2, gm_ch1, gm_ch0};
            end
            else if (btn[2]) begin
                o_vid_data <= {th_pix, th_pix, th_pix};
            end
            else if (btn[3]) begin
                o_vid_data <= ~i_vid_data;
            end
            else begin
                o_vid_data <= i_vid_data;
            end
        end
    end

endmodule