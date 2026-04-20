`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Button Controller — debounce, mode cycling, filter selection, LED output
//
// SW0:       branch select (0=single-pixel, 1=multi-pixel)
// BTN0–BTN2: select filter within active branch (one-hot, re-press deselects)
// BTN3:      cycle compositor mode (0→2→3→4→5→0)
// LED[0]:    branch_sel
// LED[1]:    any filter active
// LED[3:2]:  comp_mode[1:0]
//
// Software override: when sw_override=1, buttons ignored, register values used.
// Edge-overlay mode forces sobel on path B.
//////////////////////////////////////////////////////////////////////////////

module btn_ctrl #
(
    parameter CLK_FREQ_HZ = 148_500_000,
    parameter DEBOUNCE_MS = 20
)
(
    input  wire        clk,
    input  wire        n_rst,

    // Raw board I/O
    input  wire [3:0]  btn_raw,
    input  wire        sw0_raw,

    // Software override from AXI GPIO
    input  wire        sw_override,     // 1 = software controls all
    input  wire [2:0]  sw_comp_mode,
    input  wire [2:0]  sw_filter_sel_a, // 0=pass,1=bright,2=gamma,3=thresh,4=invert
    input  wire [2:0]  sw_filter_sel_b, // 0=pass,1=sobel,2=erode,3=dilate
    input  wire        sw_branch_sel,

    // Outputs to colour_change
    output reg  [3:0]  cc_btn,

    // Outputs to multi_filter_select
    output reg  [3:0]  mf_btn,

    // Outputs to compositor
    output reg  [2:0]  comp_mode,
    output reg         branch_sel,

    // LED outputs
    output wire [3:0]  led
);

    // -------------------------------------------------------------------------
    // Debounce logic
    // -------------------------------------------------------------------------
    localparam DEBOUNCE_COUNT = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam CNT_WIDTH = $clog2(DEBOUNCE_COUNT + 1);

    reg [3:0] btn_sync1, btn_sync2;  // double-flop synchronizer
    reg [3:0] btn_stable;
    reg [3:0] btn_prev;
    reg [CNT_WIDTH-1:0] debounce_cnt [3:0];

    reg sw0_sync1, sw0_sync2;

    integer i;

    always @(posedge clk) begin
        if (!n_rst) begin
            btn_sync1 <= 4'b0;
            btn_sync2 <= 4'b0;
            btn_stable <= 4'b0;
            btn_prev <= 4'b0;
            sw0_sync1 <= 1'b0;
            sw0_sync2 <= 1'b0;
            for (i = 0; i < 4; i = i + 1)
                debounce_cnt[i] <= {CNT_WIDTH{1'b0}};
        end else begin
            // Synchronize inputs
            btn_sync1 <= btn_raw;
            btn_sync2 <= btn_sync1;
            sw0_sync1 <= sw0_raw;
            sw0_sync2 <= sw0_sync1;

            // Per-button debounce
            for (i = 0; i < 4; i = i + 1) begin
                if (btn_sync2[i] != btn_stable[i]) begin
                    if (debounce_cnt[i] >= DEBOUNCE_COUNT[CNT_WIDTH-1:0])  begin
                        btn_stable[i] <= btn_sync2[i];
                        debounce_cnt[i] <= {CNT_WIDTH{1'b0}};
                    end else begin
                        debounce_cnt[i] <= debounce_cnt[i] + 1;
                    end
                end else begin
                    debounce_cnt[i] <= {CNT_WIDTH{1'b0}};
                end
            end

            btn_prev <= btn_stable;
        end
    end

    // Rising edge detection on debounced buttons
    wire [3:0] btn_posedge;
    assign btn_posedge = btn_stable & ~btn_prev;

    // -------------------------------------------------------------------------
    // Mode cycling state machine (BTN3)
    // Sequence: 0 (full-filtered) → 2 (split) → 3 (wipe) → 4 (ROI) → 5 (overlay) → 0
    // -------------------------------------------------------------------------
    reg [2:0] hw_comp_mode;

    always @(posedge clk) begin
        if (!n_rst) begin
            hw_comp_mode <= 3'd0;
        end else if (btn_posedge[3]) begin
            case (hw_comp_mode)
                3'd0: hw_comp_mode <= 3'd2;
                3'd2: hw_comp_mode <= 3'd3;
                3'd3: hw_comp_mode <= 3'd4;
                3'd4: hw_comp_mode <= 3'd5;
                3'd5: hw_comp_mode <= 3'd0;
                default: hw_comp_mode <= 3'd0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Filter selection (BTN0–BTN2 within active branch)
    // One-hot with toggle: pressing active filter deselects it (passthrough)
    // Pressing a different filter selects it and deselects the previous
    // -------------------------------------------------------------------------
    reg [2:0] hw_filter_a;  // which filter in branch A (0=none/pass)
    reg [2:0] hw_filter_b;  // which filter in branch B (0=none/pass)

    always @(posedge clk) begin
        if (!n_rst) begin
            hw_filter_a <= 3'd0;
            hw_filter_b <= 3'd0;
        end else begin
            if (!sw0_sync2) begin
                // Branch A active: BTN0-2 control single-pixel filters
                if (btn_posedge[0])
                    hw_filter_a <= (hw_filter_a == 3'd1) ? 3'd0 : 3'd1;
                else if (btn_posedge[1])
                    hw_filter_a <= (hw_filter_a == 3'd2) ? 3'd0 : 3'd2;
                else if (btn_posedge[2])
                    hw_filter_a <= (hw_filter_a == 3'd3) ? 3'd0 : 3'd3;
            end else begin
                // Branch B active: BTN0-2 control multi-pixel filters
                if (btn_posedge[0])
                    hw_filter_b <= (hw_filter_b == 3'd1) ? 3'd0 : 3'd1;
                else if (btn_posedge[1])
                    hw_filter_b <= (hw_filter_b == 3'd2) ? 3'd0 : 3'd2;
                else if (btn_posedge[2])
                    hw_filter_b <= (hw_filter_b == 3'd3) ? 3'd0 : 3'd3;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output logic: software override vs hardware buttons
    // -------------------------------------------------------------------------
    reg [2:0] active_filter_a;
    reg [2:0] active_filter_b;
    reg [2:0] active_comp_mode;
    reg       active_branch;

    always @(*) begin
        if (sw_override) begin
            active_comp_mode = sw_comp_mode;
            active_filter_a  = sw_filter_sel_a;
            active_filter_b  = sw_filter_sel_b;
            active_branch    = sw_branch_sel;
        end else begin
            active_comp_mode = hw_comp_mode;
            active_filter_a  = hw_filter_a;
            active_filter_b  = hw_filter_b;
            active_branch    = sw0_sync2;
        end
    end

    // Map filter selection to btn[3:0] one-hot encoding for colour_change
    // colour_change uses: btn[0]=bright, btn[1]=gamma, btn[2]=thresh, btn[3]=invert
    always @(*) begin
        case (active_filter_a)
            3'd1:    cc_btn = 4'b0001;  // brightness
            3'd2:    cc_btn = 4'b0010;  // gamma
            3'd3:    cc_btn = 4'b0100;  // threshold
            3'd4:    cc_btn = 4'b1000;  // invert
            default: cc_btn = 4'b0000;  // passthrough
        endcase
    end

    // Map filter selection to btn[3:0] for multi_filter_select
    // multi_filter_select uses: btn[0]=sobel, btn[1]=erode, btn[2]=dilate
    // Special case: edge-overlay mode forces sobel
    always @(*) begin
        if (active_comp_mode == 3'd5) begin
            // Edge-overlay: force sobel on path B
            mf_btn = 4'b0001;
        end else begin
            case (active_filter_b)
                3'd1:    mf_btn = 4'b0001;  // sobel
                3'd2:    mf_btn = 4'b0010;  // erosion
                3'd3:    mf_btn = 4'b0100;  // dilation
                default: mf_btn = 4'b0000;  // passthrough
            endcase
        end
    end

    // Output compositor control
    always @(*) begin
        comp_mode  = active_comp_mode;
        branch_sel = active_branch;
    end

    // -------------------------------------------------------------------------
    // LED outputs (registered to help Vivado module reference inference)
    // -------------------------------------------------------------------------
    wire any_filter_active;
    assign any_filter_active = (active_filter_a != 3'd0) || (active_filter_b != 3'd0);

    reg [3:0] led_reg;
    always @(posedge clk) begin
        if (!n_rst)
            led_reg <= 4'b0000;
        else begin
            led_reg[0] <= active_branch;
            led_reg[1] <= any_filter_active;
            led_reg[3:2] <= active_comp_mode[1:0];
        end
    end
    assign led = led_reg;

endmodule
