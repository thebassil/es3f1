`timescale 1ns / 1ps

module tb_video_compositor;

    parameter DATA_WIDTH = 24;
    parameter IMG_WIDTH  = 64;   // small frame for fast sim
    parameter IMG_HEIGHT = 16;
    parameter CLK_PERIOD = 6.7;  // ~148.5 MHz

    reg                   clk;
    reg                   n_rst;

    // Original feed
    reg  [DATA_WIDTH-1:0] orig_vid_data;
    reg                   orig_vid_hsync;
    reg                   orig_vid_vsync;
    reg                   orig_vid_VDE;

    // Path A (single-pixel filtered)
    reg  [DATA_WIDTH-1:0] a_vid_data;
    reg                   a_vid_hsync;
    reg                   a_vid_vsync;
    reg                   a_vid_VDE;

    // Path B (multi-pixel filtered)
    reg  [DATA_WIDTH-1:0] b_vid_data;
    reg                   b_vid_hsync;
    reg                   b_vid_vsync;
    reg                   b_vid_VDE;

    // Control
    reg  [2:0]            comp_mode;
    reg                   branch_sel;
    reg  [10:0]           wipe_pos;
    reg  [10:0]           roi_x, roi_y, roi_w, roi_h;
    reg  [7:0]            edge_thresh;

    // Output
    wire [DATA_WIDTH-1:0] o_vid_data;
    wire                  o_vid_hsync;
    wire                  o_vid_vsync;
    wire                  o_vid_VDE;

    // Instantiate DUT
    video_compositor #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .orig_vid_data(orig_vid_data),
        .orig_vid_hsync(orig_vid_hsync),
        .orig_vid_vsync(orig_vid_vsync),
        .orig_vid_VDE(orig_vid_VDE),
        .a_vid_data(a_vid_data),
        .a_vid_hsync(a_vid_hsync),
        .a_vid_vsync(a_vid_vsync),
        .a_vid_VDE(a_vid_VDE),
        .b_vid_data(b_vid_data),
        .b_vid_hsync(b_vid_hsync),
        .b_vid_vsync(b_vid_vsync),
        .b_vid_VDE(b_vid_VDE),
        .comp_mode(comp_mode),
        .branch_sel(branch_sel),
        .wipe_pos(wipe_pos),
        .roi_x(roi_x),
        .roi_y(roi_y),
        .roi_w(roi_w),
        .roi_h(roi_h),
        .edge_thresh(edge_thresh),
        .o_vid_data(o_vid_data),
        .o_vid_hsync(o_vid_hsync),
        .o_vid_vsync(o_vid_vsync),
        .o_vid_VDE(o_vid_VDE)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Track internal counters for verification
    integer pixel_count;
    integer line_count;
    integer frame_count;
    integer errors;

    // Generate video timing
    // Simple: H_BLANK=16, V_BLANK=4
    parameter H_BLANK = 16;
    parameter V_BLANK = 4;
    parameter H_TOTAL = IMG_WIDTH + H_BLANK;
    parameter V_TOTAL = IMG_HEIGHT + V_BLANK;

    task generate_frame;
        integer row, col;
        begin
            // Vsync pulse (1 clock)
            @(posedge clk);
            orig_vid_vsync <= 1'b1;
            orig_vid_VDE <= 1'b0;
            orig_vid_hsync <= 1'b0;
            orig_vid_data <= 24'h000000;
            @(posedge clk);
            orig_vid_vsync <= 1'b0;

            // V blanking lines
            repeat (V_BLANK - 1) begin
                repeat (H_TOTAL) @(posedge clk);
            end

            // Active lines
            for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                // Hsync pulse
                orig_vid_hsync <= 1'b1;
                @(posedge clk);
                orig_vid_hsync <= 1'b0;

                // H blanking
                repeat (H_BLANK - 1) @(posedge clk);

                // Active pixels
                for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                    orig_vid_VDE <= 1'b1;
                    // Original: encode position in pixel value
                    orig_vid_data <= {8'd0, row[7:0], col[7:0]};
                    @(posedge clk);
                end
                orig_vid_VDE <= 1'b0;
                orig_vid_data <= 24'h000000;
            end
        end
    endtask

    // Simulate path A with 1-clock delay (like colour_change)
    always @(posedge clk) begin
        if (!n_rst) begin
            a_vid_data  <= 24'h000000;
            a_vid_hsync <= 1'b0;
            a_vid_vsync <= 1'b0;
            a_vid_VDE   <= 1'b0;
        end else begin
            a_vid_hsync <= orig_vid_hsync;
            a_vid_vsync <= orig_vid_vsync;
            a_vid_VDE   <= orig_vid_VDE;
            // Path A: mark with 0xAA in red channel
            a_vid_data  <= {8'hAA, orig_vid_data[15:0]};
        end
    end

    // Simulate path B with 1-clock delay for sync (like multi_filter_select)
    always @(posedge clk) begin
        if (!n_rst) begin
            b_vid_data  <= 24'h000000;
            b_vid_hsync <= 1'b0;
            b_vid_vsync <= 1'b0;
            b_vid_VDE   <= 1'b0;
        end else begin
            b_vid_hsync <= orig_vid_hsync;
            b_vid_vsync <= orig_vid_vsync;
            b_vid_VDE   <= orig_vid_VDE;
            // Path B: simulate edge output (grayscale), vary magnitude by column
            b_vid_data  <= {3{orig_vid_data[7:0]}};  // col value in all channels
        end
    end

    // =========================================================================
    // Test sequence
    // =========================================================================
    initial begin
        $dumpfile("tb_compositor.vcd");
        $dumpvars(0, tb_video_compositor);

        errors = 0;
        frame_count = 0;

        // Init
        n_rst = 0;
        orig_vid_data = 0;
        orig_vid_hsync = 0;
        orig_vid_vsync = 0;
        orig_vid_VDE = 0;
        comp_mode = 3'd0;
        branch_sel = 0;
        wipe_pos = 11'd32;  // midpoint of 64-wide frame
        roi_x = 11'd16;
        roi_y = 11'd4;
        roi_w = 11'd32;
        roi_h = 11'd8;
        edge_thresh = 8'd30;

        // Reset
        repeat (10) @(posedge clk);
        n_rst = 1;
        repeat (5) @(posedge clk);

        // -----------------------------------------------------------------
        // TEST 1: Full-screen filtered mode (mode 0, branch A)
        // -----------------------------------------------------------------
        $display("TEST 1: Full-screen filtered (mode 0, branch A)");
        comp_mode = 3'd0;
        branch_sel = 0;
        generate_frame;  // First frame latches control on vsync
        generate_frame;  // Second frame uses latched values
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // TEST 2: Full-screen original (mode 1)
        // -----------------------------------------------------------------
        $display("TEST 2: Full-screen original (mode 1)");
        comp_mode = 3'd1;
        generate_frame;
        generate_frame;
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // TEST 3: Split-screen (mode 2, wipe at col 32)
        // -----------------------------------------------------------------
        $display("TEST 3: Split-screen (mode 2, wipe_pos=32)");
        comp_mode = 3'd2;
        wipe_pos = 11'd32;
        generate_frame;
        generate_frame;
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // TEST 4: ROI mode (mode 4)
        // -----------------------------------------------------------------
        $display("TEST 4: ROI spotlight (mode 4)");
        comp_mode = 3'd4;
        roi_x = 11'd16;
        roi_y = 11'd4;
        roi_w = 11'd32;
        roi_h = 11'd8;
        branch_sel = 1;  // use path B inside ROI
        generate_frame;
        generate_frame;
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // TEST 5: Edge overlay (mode 5)
        // -----------------------------------------------------------------
        $display("TEST 5: Edge overlay (mode 5, thresh=30)");
        comp_mode = 3'd5;
        edge_thresh = 8'd30;
        generate_frame;
        generate_frame;
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // TEST 6: Branch B in full-screen mode
        // -----------------------------------------------------------------
        $display("TEST 6: Full-screen filtered (mode 0, branch B)");
        comp_mode = 3'd0;
        branch_sel = 1;
        generate_frame;
        generate_frame;
        frame_count = frame_count + 2;

        // -----------------------------------------------------------------
        // Done
        // -----------------------------------------------------------------
        $display("");
        $display("===========================================");
        $display(" Simulation complete: %0d frames generated", frame_count);
        $display(" Check waveform (tb_compositor.vcd) for visual verification");
        $display("===========================================");
        $finish;
    end

    // =========================================================================
    // Output monitoring — check key invariants
    // =========================================================================
    reg [10:0] check_col;
    reg [10:0] check_row;
    reg        check_prev_vde;
    reg        check_prev_vsync;

    always @(posedge clk) begin
        if (!n_rst) begin
            check_col <= 0;
            check_row <= 0;
            check_prev_vde <= 0;
            check_prev_vsync <= 0;
        end else begin
            check_prev_vde <= o_vid_VDE;
            check_prev_vsync <= o_vid_vsync;

            if (o_vid_vsync && !check_prev_vsync) begin
                check_row <= 0;
                check_col <= 0;
            end else if (!o_vid_VDE && check_prev_vde) begin
                check_row <= check_row + 1;
                check_col <= 0;
            end else if (o_vid_VDE) begin
                check_col <= check_col + 1;

                // Verify output data based on mode (after 2 frames for latch)
                if (frame_count >= 2) begin
                    case (dut.mode_lat)
                        3'd0: begin // full-filtered
                            if (dut.branch_lat == 0 && o_vid_data[23:16] != 8'hAA && o_vid_VDE) begin
                                // Path A should have 0xAA in red
                                // (allow first few pixels for pipeline startup)
                                if (check_col > 3 && check_row > 2) begin
                                    $display("WARN: mode 0 branch A, unexpected red channel at (%0d,%0d): %h",
                                             check_col, check_row, o_vid_data[23:16]);
                                end
                            end
                        end
                        3'd2: begin // split-screen
                            // Left of wipe should be original (red=0x00)
                            // Right of wipe should be filtered (red=0xAA for branch A)
                            if (check_col > 3 && check_row > 2) begin
                                if (check_col < dut.wipe_lat) begin
                                    if (o_vid_data[23:16] != 8'h00) begin
                                        $display("WARN: split mode, left side not original at col %0d: red=%h",
                                                 check_col, o_vid_data[23:16]);
                                    end
                                end
                            end
                        end
                    endcase
                end
            end
        end
    end

endmodule
