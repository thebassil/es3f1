`timescale 1ns / 1ps
// Focused pixel-level verification of video_compositor

module tb_compositor_check;

    parameter DATA_WIDTH = 24;
    parameter IMG_WIDTH  = 32;
    parameter IMG_HEIGHT = 8;
    parameter CLK_PERIOD = 10;
    parameter H_BLANK = 8;
    parameter V_BLANK = 2;

    reg                   clk;
    reg                   n_rst;
    reg  [DATA_WIDTH-1:0] orig_vid_data;
    reg                   orig_vid_hsync, orig_vid_vsync, orig_vid_VDE;
    reg  [DATA_WIDTH-1:0] a_vid_data;
    reg                   a_vid_hsync, a_vid_vsync, a_vid_VDE;
    reg  [DATA_WIDTH-1:0] b_vid_data;
    reg                   b_vid_hsync, b_vid_vsync, b_vid_VDE;
    reg  [2:0]            comp_mode;
    reg                   branch_sel;
    reg  [10:0]           wipe_pos, roi_x, roi_y, roi_w, roi_h;
    reg  [7:0]            edge_thresh;
    wire [DATA_WIDTH-1:0] o_vid_data;
    wire                  o_vid_hsync, o_vid_vsync, o_vid_VDE;

    video_compositor #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (.*);

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Generate one frame and capture output pixels
    reg [DATA_WIDTH-1:0] captured [0:IMG_WIDTH*IMG_HEIGHT-1];
    integer cap_idx;

    task generate_frame;
        integer row, col;
        begin
            @(posedge clk);
            orig_vid_vsync <= 1'b1;
            orig_vid_VDE <= 1'b0;
            orig_vid_hsync <= 1'b0;
            @(posedge clk);
            orig_vid_vsync <= 1'b0;
            repeat (V_BLANK * (IMG_WIDTH + H_BLANK) - 1) @(posedge clk);

            cap_idx = 0;
            for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                orig_vid_hsync <= 1'b1;
                @(posedge clk);
                orig_vid_hsync <= 1'b0;
                repeat (H_BLANK - 1) @(posedge clk);

                for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                    orig_vid_VDE <= 1'b1;
                    orig_vid_data <= {8'h11, row[7:0], col[7:0]};  // original: red=0x11
                    @(posedge clk);
                end
                orig_vid_VDE <= 1'b0;
                orig_vid_data <= 24'h0;
            end
        end
    endtask

    // Capture output during active video
    always @(posedge clk) begin
        if (o_vid_VDE) begin
            captured[cap_idx] <= o_vid_data;
            cap_idx <= cap_idx + 1;
        end
    end

    // Simulate path A: 1-clk delayed, red channel = 0xAA
    always @(posedge clk) begin
        if (!n_rst) begin
            a_vid_data <= 0; a_vid_hsync <= 0; a_vid_vsync <= 0; a_vid_VDE <= 0;
        end else begin
            a_vid_hsync <= orig_vid_hsync;
            a_vid_vsync <= orig_vid_vsync;
            a_vid_VDE <= orig_vid_VDE;
            a_vid_data <= {8'hAA, orig_vid_data[15:0]};
        end
    end

    // Simulate path B: 1-clk delayed, all channels = col value (grayscale for sobel sim)
    always @(posedge clk) begin
        if (!n_rst) begin
            b_vid_data <= 0; b_vid_hsync <= 0; b_vid_vsync <= 0; b_vid_VDE <= 0;
        end else begin
            b_vid_hsync <= orig_vid_hsync;
            b_vid_vsync <= orig_vid_vsync;
            b_vid_VDE <= orig_vid_VDE;
            b_vid_data <= {3{orig_vid_data[7:0]}};  // grayscale = col
        end
    end

    integer errors;
    integer i, r, c;
    reg [DATA_WIDTH-1:0] expected;
    reg [DATA_WIDTH-1:0] got;

    initial begin
        errors = 0;
        n_rst = 0;
        orig_vid_data = 0; orig_vid_hsync = 0; orig_vid_vsync = 0; orig_vid_VDE = 0;
        comp_mode = 0; branch_sel = 0;
        wipe_pos = 11'd16; roi_x = 11'd8; roi_y = 11'd2; roi_w = 11'd16; roi_h = 11'd4;
        edge_thresh = 8'd20;

        repeat (10) @(posedge clk);
        n_rst = 1;
        repeat (5) @(posedge clk);

        // ============================================================
        // TEST A: Mode 0 (full filtered, branch A) — every pixel should have red=0xAA
        // ============================================================
        $display("TEST A: Mode 0, branch A (full filtered)");
        comp_mode = 3'd0; branch_sel = 0;
        generate_frame; // latch
        generate_frame; // check this one
        // Wait for frame to fully output
        repeat (20) @(posedge clk);

        for (i = 0; i < IMG_WIDTH * IMG_HEIGHT; i = i + 1) begin
            got = captured[i];
            if (got[23:16] !== 8'hAA) begin
                if (errors < 5) $display("  FAIL pixel %0d: red=%h expected AA", i, got[23:16]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("  PASS: all %0d pixels have red=0xAA", IMG_WIDTH*IMG_HEIGHT);
        else $display("  %0d pixel errors", errors);

        // ============================================================
        // TEST B: Mode 2 (split at col 16) — left half red=0x11, right half red=0xAA
        // ============================================================
        errors = 0;
        $display("\nTEST B: Mode 2, split at col 16");
        comp_mode = 3'd2; branch_sel = 0; wipe_pos = 11'd16;
        generate_frame; // latch
        generate_frame; // use
        repeat (20) @(posedge clk);

        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                i = r * IMG_WIDTH + c;
                got = captured[i];
                if (c < 16) begin
                    // Left side: original (red=0x11)
                    // Note: orig_data_d1 has 1-clk delay, so original red=0x11
                    if (got[23:16] !== 8'h11) begin
                        if (errors < 5) $display("  FAIL (%0d,%0d): red=%h expected 11 (original)", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end else begin
                    // Right side: filtered (red=0xAA)
                    if (got[23:16] !== 8'hAA) begin
                        if (errors < 5) $display("  FAIL (%0d,%0d): red=%h expected AA (filtered)", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end
            end
        end
        if (errors == 0) $display("  PASS: split boundary correct at col 16");
        else $display("  %0d pixel errors", errors);

        // ============================================================
        // TEST C: Mode 4 (ROI: x=8,y=2,w=16,h=4) — inside=filtered, outside=original
        // ============================================================
        errors = 0;
        $display("\nTEST C: Mode 4, ROI box (8,2,16,4)");
        comp_mode = 3'd4; branch_sel = 0;
        roi_x = 11'd8; roi_y = 11'd2; roi_w = 11'd16; roi_h = 11'd4;
        generate_frame; // latch
        generate_frame; // use
        repeat (20) @(posedge clk);

        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                i = r * IMG_WIDTH + c;
                got = captured[i];
                if (c >= 8 && c < 24 && r >= 2 && r < 6) begin
                    // Inside ROI: filtered (red=0xAA)
                    if (got[23:16] !== 8'hAA) begin
                        if (errors < 5) $display("  FAIL inside ROI (%0d,%0d): red=%h expected AA", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end else begin
                    // Outside ROI: original (red=0x11)
                    if (got[23:16] !== 8'h11) begin
                        if (errors < 5) $display("  FAIL outside ROI (%0d,%0d): red=%h expected 11", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end
            end
        end
        if (errors == 0) $display("  PASS: ROI box boundary correct");
        else $display("  %0d pixel errors", errors);

        // ============================================================
        // TEST D: Mode 5 (edge overlay, thresh=20)
        //   Path B output = col value as grayscale
        //   Cols >= 20 should produce white overlay, cols < 20 should be path A colour
        //   (Except border: row<2 || col<2 always outputs path A)
        // ============================================================
        errors = 0;
        $display("\nTEST D: Mode 5, edge overlay (thresh=20)");
        comp_mode = 3'd5; edge_thresh = 8'd20;
        generate_frame; // latch
        generate_frame; // use
        repeat (20) @(posedge clk);

        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                i = r * IMG_WIDTH + c;
                got = captured[i];
                if (r < 2 || c < 2) begin
                    // Border: should be path A (red=0xAA)
                    if (got[23:16] !== 8'hAA) begin
                        if (errors < 5) $display("  FAIL border (%0d,%0d): red=%h expected AA", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end else if (c > 20) begin
                    // Edge magnitude (=col) > thresh(20): white
                    if (got !== 24'hFFFFFF) begin
                        if (errors < 5) $display("  FAIL edge (%0d,%0d): %h expected FFFFFF", r, c, got);
                        errors = errors + 1;
                    end
                end else if (c < 20) begin
                    // Edge magnitude < thresh: path A colour (red=0xAA)
                    if (got[23:16] !== 8'hAA) begin
                        if (errors < 5) $display("  FAIL no-edge (%0d,%0d): red=%h expected AA", r, c, got[23:16]);
                        errors = errors + 1;
                    end
                end
                // c==20 is boundary, skip exact boundary check
            end
        end
        if (errors == 0) $display("  PASS: edge overlay correct");
        else $display("  %0d pixel errors", errors);

        // ============================================================
        $display("\n===========================================");
        $display(" Pixel-level verification complete");
        $display("===========================================");
        $finish;
    end

endmodule
