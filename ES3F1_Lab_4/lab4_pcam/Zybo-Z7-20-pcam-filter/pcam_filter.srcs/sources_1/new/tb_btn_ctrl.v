`timescale 1ns / 1ps

module tb_btn_ctrl;

    parameter CLK_FREQ_HZ = 1_000_000;  // 1 MHz for fast sim (real is 148.5 MHz)
    parameter DEBOUNCE_MS = 1;           // 1ms debounce (1000 clocks at 1 MHz)
    parameter CLK_PERIOD = 1000;         // 1 us = 1000 ns

    reg        clk;
    reg        n_rst;
    reg  [3:0] btn_raw;
    reg        sw0_raw;
    reg        sw_override;
    reg  [2:0] sw_comp_mode;
    reg  [2:0] sw_filter_sel_a;
    reg  [2:0] sw_filter_sel_b;
    reg        sw_branch_sel;

    wire [3:0] cc_btn;
    wire [3:0] mf_btn;
    wire [2:0] comp_mode;
    wire       branch_sel;
    wire [3:0] led;

    // Instantiate DUT
    btn_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(DEBOUNCE_MS)
    ) dut (
        .clk(clk),
        .n_rst(n_rst),
        .btn_raw(btn_raw),
        .sw0_raw(sw0_raw),
        .sw_override(sw_override),
        .sw_comp_mode(sw_comp_mode),
        .sw_filter_sel_a(sw_filter_sel_a),
        .sw_filter_sel_b(sw_filter_sel_b),
        .sw_branch_sel(sw_branch_sel),
        .cc_btn(cc_btn),
        .mf_btn(mf_btn),
        .comp_mode(comp_mode),
        .branch_sel(branch_sel),
        .led(led)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer errors;

    // Task: press and release a button with debounce settling time
    task press_button;
        input [3:0] btn_mask;
        begin
            btn_raw = btn_mask;
            // Wait for debounce to settle (DEBOUNCE_MS * CLK_FREQ_HZ/1000 + margin)
            repeat (1500) @(posedge clk);
            btn_raw = 4'b0000;
            repeat (1500) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_btn_ctrl.vcd");
        $dumpvars(0, tb_btn_ctrl);

        errors = 0;

        // Init
        n_rst = 0;
        btn_raw = 4'b0000;
        sw0_raw = 0;
        sw_override = 0;
        sw_comp_mode = 3'd0;
        sw_filter_sel_a = 3'd0;
        sw_filter_sel_b = 3'd0;
        sw_branch_sel = 0;

        // Reset
        repeat (20) @(posedge clk);
        n_rst = 1;
        repeat (20) @(posedge clk);

        // -----------------------------------------------------------------
        // TEST 1: Initial state
        // -----------------------------------------------------------------
        $display("TEST 1: Initial state after reset");
        if (comp_mode !== 3'd0) begin
            $display("  FAIL: comp_mode = %d, expected 0", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: comp_mode = 0");

        if (cc_btn !== 4'b0000) begin
            $display("  FAIL: cc_btn = %b, expected 0000", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0000 (passthrough)");

        if (branch_sel !== 1'b0) begin
            $display("  FAIL: branch_sel = %b, expected 0", branch_sel);
            errors = errors + 1;
        end else $display("  PASS: branch_sel = 0 (path A)");

        // -----------------------------------------------------------------
        // TEST 2: BTN0 selects brightness (branch A active, sw0=0)
        // -----------------------------------------------------------------
        $display("\nTEST 2: BTN0 selects brightness in branch A");
        sw0_raw = 0;
        repeat (100) @(posedge clk);
        press_button(4'b0001);

        if (cc_btn !== 4'b0001) begin
            $display("  FAIL: cc_btn = %b, expected 0001", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0001 (brightness)");

        // -----------------------------------------------------------------
        // TEST 3: BTN0 again toggles off (deselect)
        // -----------------------------------------------------------------
        $display("\nTEST 3: BTN0 again deselects (toggle off)");
        press_button(4'b0001);

        if (cc_btn !== 4'b0000) begin
            $display("  FAIL: cc_btn = %b, expected 0000", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0000 (passthrough)");

        // -----------------------------------------------------------------
        // TEST 4: BTN1 selects gamma
        // -----------------------------------------------------------------
        $display("\nTEST 4: BTN1 selects gamma");
        press_button(4'b0010);

        if (cc_btn !== 4'b0010) begin
            $display("  FAIL: cc_btn = %b, expected 0010", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0010 (gamma)");

        // -----------------------------------------------------------------
        // TEST 5: BTN2 selects threshold (replaces gamma — one-hot)
        // -----------------------------------------------------------------
        $display("\nTEST 5: BTN2 selects threshold (replaces gamma)");
        press_button(4'b0100);

        if (cc_btn !== 4'b0100) begin
            $display("  FAIL: cc_btn = %b, expected 0100", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0100 (threshold)");

        // -----------------------------------------------------------------
        // TEST 6: Switch to branch B (sw0=1), BTN0 selects sobel
        // -----------------------------------------------------------------
        $display("\nTEST 6: Switch to branch B, BTN0 selects sobel");
        sw0_raw = 1;
        repeat (100) @(posedge clk);

        if (branch_sel !== 1'b1) begin
            $display("  FAIL: branch_sel = %b, expected 1", branch_sel);
            errors = errors + 1;
        end else $display("  PASS: branch_sel = 1 (path B)");

        press_button(4'b0001);

        if (mf_btn !== 4'b0001) begin
            $display("  FAIL: mf_btn = %b, expected 0001", mf_btn);
            errors = errors + 1;
        end else $display("  PASS: mf_btn = 0001 (sobel)");

        // -----------------------------------------------------------------
        // TEST 7: BTN3 cycles compositor mode (0 → 2)
        // -----------------------------------------------------------------
        $display("\nTEST 7: BTN3 cycles mode 0 -> 2");
        press_button(4'b1000);

        if (comp_mode !== 3'd2) begin
            $display("  FAIL: comp_mode = %d, expected 2", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: comp_mode = 2 (split-screen)");

        // -----------------------------------------------------------------
        // TEST 8: BTN3 again (2 → 3)
        // -----------------------------------------------------------------
        $display("\nTEST 8: BTN3 cycles mode 2 -> 3");
        press_button(4'b1000);

        if (comp_mode !== 3'd3) begin
            $display("  FAIL: comp_mode = %d, expected 3", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: comp_mode = 3 (wipe)");

        // -----------------------------------------------------------------
        // TEST 9: BTN3 cycles through 4, 5, back to 0
        // -----------------------------------------------------------------
        $display("\nTEST 9: Full mode cycle 3->4->5->0");
        press_button(4'b1000);
        if (comp_mode !== 3'd4) begin
            $display("  FAIL: expected 4, got %d", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: mode = 4 (ROI)");

        press_button(4'b1000);
        if (comp_mode !== 3'd5) begin
            $display("  FAIL: expected 5, got %d", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: mode = 5 (edge-overlay)");

        press_button(4'b1000);
        if (comp_mode !== 3'd0) begin
            $display("  FAIL: expected 0, got %d", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: mode = 0 (full-filtered, wrapped)");

        // -----------------------------------------------------------------
        // TEST 10: Edge-overlay forces sobel on path B
        // -----------------------------------------------------------------
        $display("\nTEST 10: Edge-overlay mode forces mf_btn = sobel");
        // Set mode to 5
        press_button(4'b1000); // 0->2
        press_button(4'b1000); // 2->3
        press_button(4'b1000); // 3->4
        press_button(4'b1000); // 4->5

        if (mf_btn !== 4'b0001) begin
            $display("  FAIL: mf_btn = %b, expected 0001 (forced sobel)", mf_btn);
            errors = errors + 1;
        end else $display("  PASS: mf_btn = 0001 (sobel forced by overlay mode)");

        // -----------------------------------------------------------------
        // TEST 11: Software override
        // -----------------------------------------------------------------
        $display("\nTEST 11: Software override");
        sw_override = 1;
        sw_comp_mode = 3'd4;
        sw_filter_sel_a = 3'd3;
        sw_filter_sel_b = 3'd2;
        sw_branch_sel = 0;
        repeat (20) @(posedge clk);

        if (comp_mode !== 3'd4) begin
            $display("  FAIL: comp_mode = %d, expected 4", comp_mode);
            errors = errors + 1;
        end else $display("  PASS: comp_mode = 4 (from software)");

        if (cc_btn !== 4'b0100) begin
            $display("  FAIL: cc_btn = %b, expected 0100 (thresh from sw)", cc_btn);
            errors = errors + 1;
        end else $display("  PASS: cc_btn = 0100 (thresh from software)");

        if (branch_sel !== 1'b0) begin
            $display("  FAIL: branch_sel = %b, expected 0", branch_sel);
            errors = errors + 1;
        end else $display("  PASS: branch_sel = 0 (from software)");

        // -----------------------------------------------------------------
        // TEST 12: LED outputs
        // -----------------------------------------------------------------
        $display("\nTEST 12: LED outputs");
        if (led[0] !== branch_sel) begin
            $display("  FAIL: led[0] = %b, expected %b", led[0], branch_sel);
            errors = errors + 1;
        end else $display("  PASS: led[0] = branch_sel");

        if (led[1] !== 1'b1) begin
            $display("  FAIL: led[1] = %b, expected 1 (filter active)", led[1]);
            errors = errors + 1;
        end else $display("  PASS: led[1] = 1 (filter active)");

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("\n===========================================");
        if (errors == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" %0d TESTS FAILED", errors);
        $display("===========================================");
        $finish;
    end

endmodule
