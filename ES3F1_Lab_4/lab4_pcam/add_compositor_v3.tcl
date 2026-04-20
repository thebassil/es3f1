# ===========================================================================
# add_compositor_to_bd.tcl — IDEMPOTENT / STATE-AGNOSTIC
#
# This script handles ANY starting state of the block design:
#   - Fresh from create_system_bd.tcl (no filter modules yet)
#   - Partially wired (filters exist, video_mux may or may not exist)
#   - Re-run after a failed previous attempt (cleans up and retries)
#
# Usage:
#   open_bd_design [get_files system.bd]
#   source add_compositor_to_bd.tcl
# ===========================================================================

set design_name system
current_bd_design $design_name

puts "================================================================"
puts " Starting compositor integration (state-agnostic)..."
puts "================================================================"

# ===========================================================================
# PHASE 0: NUKE — Remove anything from a previous run or conflicting state
# ===========================================================================

# Remove old video_mux_0
catch { delete_bd_objs [get_bd_cells video_mux_0] }

# Remove previous compositor integration attempt (if re-running)
catch { delete_bd_objs [get_bd_cells video_compositor_0] }
catch { delete_bd_objs [get_bd_cells btn_ctrl_0] }
catch { delete_bd_objs [get_bd_cells axi_gpio_0] }
catch { delete_bd_objs [get_bd_cells axi_gpio_1] }
catch { delete_bd_objs [get_bd_cells slice_comp_mode] }
catch { delete_bd_objs [get_bd_cells slice_filter_a] }
catch { delete_bd_objs [get_bd_cells slice_filter_b] }
catch { delete_bd_objs [get_bd_cells slice_branch] }
catch { delete_bd_objs [get_bd_cells slice_override] }
catch { delete_bd_objs [get_bd_cells slice_edge_thresh] }
catch { delete_bd_objs [get_bd_cells slice_wipe] }
catch { delete_bd_objs [get_bd_cells slice_roi_x] }
catch { delete_bd_objs [get_bd_cells slice_roi_y] }
catch { delete_bd_objs [get_bd_cells slice_roi_w] }
catch { delete_bd_objs [get_bd_cells slice_roi_h] }

# Remove LED port if it exists from a previous run
catch { delete_bd_objs [get_bd_ports led] }

# Disconnect the vid_io_out interface connection to rgb2dvi (if it exists as interface)
catch { delete_bd_objs [get_bd_intf_nets -of [get_bd_intf_pins rgb2dvi_0/RGB]] }

# Disconnect any existing nets going INTO rgb2dvi_0 video pins (individual nets)
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins rgb2dvi_0/vid_pData]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins rgb2dvi_0/vid_pHSync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins rgb2dvi_0/vid_pVSync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins rgb2dvi_0/vid_pVDE]] }

# Disconnect any existing btn/sw connections to filters (may be direct from ports)
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins colour_change_0/btn]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins multi_filter_select_0/btn]] }

# Disconnect existing connections from filter OUTPUTS (they went to old video_mux)
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins colour_change_0/o_vid_data]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins colour_change_0/o_vid_hsync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins colour_change_0/o_vid_vsync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins colour_change_0/o_vid_VDE]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins multi_filter_select_0/o_vid_data]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins multi_filter_select_0/o_vid_hsync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins multi_filter_select_0/o_vid_vsync]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_pins multi_filter_select_0/o_vid_VDE]] }

# Disconnect btn/sw port nets (they'll be reconnected through btn_ctrl)
catch { delete_bd_objs [get_bd_nets -of [get_bd_ports btn]] }
catch { delete_bd_objs [get_bd_nets -of [get_bd_ports sw]] }

puts "Phase 0: Cleanup complete"

# ===========================================================================
# PHASE 1: CREATE NEW CELLS
# ===========================================================================

# video_compositor_0
if { [catch {create_bd_cell -type module -reference video_compositor video_compositor_0} errmsg] } {
    puts "FATAL: Cannot create video_compositor_0: $errmsg"
    puts "       Make sure video_compositor.v is added to project sources first!"
    return 1
}

# btn_ctrl_0
if { [catch {create_bd_cell -type module -reference btn_ctrl btn_ctrl_0} errmsg] } {
    puts "FATAL: Cannot create btn_ctrl_0: $errmsg"
    puts "       Make sure btn_ctrl.v is added to project sources first!"
    return 1
}

# AXI GPIO 0 (compositor control + wipe)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
] [get_bd_cells axi_gpio_0]

# AXI GPIO 1 (ROI)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
] [get_bd_cells axi_gpio_1]

# xlslice instances for bit-field extraction
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_comp_mode
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {3}] [get_bd_cells slice_comp_mode]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_filter_a
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {5} CONFIG.DIN_TO {3} CONFIG.DOUT_WIDTH {3}] [get_bd_cells slice_filter_a]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_filter_b
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {8} CONFIG.DIN_TO {6} CONFIG.DOUT_WIDTH {3}] [get_bd_cells slice_filter_b]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_branch
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {9} CONFIG.DIN_TO {9} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_branch]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_override
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {11} CONFIG.DIN_TO {11} CONFIG.DOUT_WIDTH {1}] [get_bd_cells slice_override]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_edge_thresh
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {19} CONFIG.DIN_TO {12} CONFIG.DOUT_WIDTH {8}] [get_bd_cells slice_edge_thresh]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_wipe
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {10} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {11}] [get_bd_cells slice_wipe]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_roi_x
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {10} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {11}] [get_bd_cells slice_roi_x]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_roi_y
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {26} CONFIG.DIN_TO {16} CONFIG.DOUT_WIDTH {11}] [get_bd_cells slice_roi_y]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_roi_w
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {10} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {11}] [get_bd_cells slice_roi_w]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_roi_h
set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM {26} CONFIG.DIN_TO {16} CONFIG.DOUT_WIDTH {11}] [get_bd_cells slice_roi_h]

# LED port
create_bd_port -dir O -from 3 -to 0 led

puts "Phase 1: All cells created"

# ===========================================================================
# PHASE 2: EXPAND INTERCONNECT
# ===========================================================================

set_property CONFIG.NUM_MI {8} [get_bd_cells ps7_0_axi_periph]

puts "Phase 2: Interconnect expanded to 8 masters"

# ===========================================================================
# PHASE 3: CLOCK AND RESET CONNECTIONS
# ===========================================================================

# AXI GPIO — 50 MHz AXI-Lite domain
catch { connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_gpio_0/s_axi_aclk] }
catch { connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_gpio_1/s_axi_aclk] }
catch { connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn] }
catch { connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_gpio_1/s_axi_aresetn] }

# Interconnect new master ports — 50 MHz
# These may be auto-connected by Vivado when NUM_MI is expanded, so catch errors
catch { connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins ps7_0_axi_periph/M06_ACLK] }
catch { connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins ps7_0_axi_periph/M07_ACLK] }
catch { connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M06_ARESETN] }
catch { connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M07_ARESETN] }

# AXI bus connections
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M06_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M07_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]

# btn_ctrl_0 and video_compositor_0 — pixel clock domain
catch { connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins btn_ctrl_0/clk] }
catch { connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins video_compositor_0/clk] }
catch { connect_bd_net [get_bd_pins rst_vid_clk_dyn/peripheral_aresetn] [get_bd_pins btn_ctrl_0/n_rst] }
catch { connect_bd_net [get_bd_pins rst_vid_clk_dyn/peripheral_aresetn] [get_bd_pins video_compositor_0/n_rst] }

puts "Phase 3: Clocks and resets connected"

# ===========================================================================
# PHASE 4: VIDEO DATA PATH
# ===========================================================================

# --- Original feed → compositor + both filters ---
# v_axi4s_vid_out_0 has pins: vid_data, vid_hsync, vid_vsync, vid_active_video
# We fan these out to: video_compositor_0/orig_*, colour_change_0/i_*, multi_filter_select_0/i_*

# vid_data net
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data] \
    [get_bd_pins video_compositor_0/orig_vid_data] \
    [get_bd_pins colour_change_0/i_vid_data] \
    [get_bd_pins multi_filter_select_0/i_vid_data]

# vid_hsync net
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_hsync] \
    [get_bd_pins video_compositor_0/orig_vid_hsync] \
    [get_bd_pins colour_change_0/i_vid_hsync] \
    [get_bd_pins multi_filter_select_0/i_vid_hsync]

# vid_vsync net
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_vsync] \
    [get_bd_pins video_compositor_0/orig_vid_vsync] \
    [get_bd_pins colour_change_0/i_vid_vsync] \
    [get_bd_pins multi_filter_select_0/i_vid_vsync]

# vid_active_video (VDE) net
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_active_video] \
    [get_bd_pins video_compositor_0/orig_vid_VDE] \
    [get_bd_pins colour_change_0/i_vid_VDE] \
    [get_bd_pins multi_filter_select_0/i_vid_VDE]

# --- Filter outputs → compositor ---
connect_bd_net [get_bd_pins colour_change_0/o_vid_data] [get_bd_pins video_compositor_0/a_vid_data]
connect_bd_net [get_bd_pins colour_change_0/o_vid_hsync] [get_bd_pins video_compositor_0/a_vid_hsync]
connect_bd_net [get_bd_pins colour_change_0/o_vid_vsync] [get_bd_pins video_compositor_0/a_vid_vsync]
connect_bd_net [get_bd_pins colour_change_0/o_vid_VDE] [get_bd_pins video_compositor_0/a_vid_VDE]

connect_bd_net [get_bd_pins multi_filter_select_0/o_vid_data] [get_bd_pins video_compositor_0/b_vid_data]
connect_bd_net [get_bd_pins multi_filter_select_0/o_vid_hsync] [get_bd_pins video_compositor_0/b_vid_hsync]
connect_bd_net [get_bd_pins multi_filter_select_0/o_vid_vsync] [get_bd_pins video_compositor_0/b_vid_vsync]
connect_bd_net [get_bd_pins multi_filter_select_0/o_vid_VDE] [get_bd_pins video_compositor_0/b_vid_VDE]

# --- Compositor output → rgb2dvi_0 ---
connect_bd_net [get_bd_pins video_compositor_0/o_vid_data] [get_bd_pins rgb2dvi_0/vid_pData]
connect_bd_net [get_bd_pins video_compositor_0/o_vid_hsync] [get_bd_pins rgb2dvi_0/vid_pHSync]
connect_bd_net [get_bd_pins video_compositor_0/o_vid_vsync] [get_bd_pins rgb2dvi_0/vid_pVSync]
connect_bd_net [get_bd_pins video_compositor_0/o_vid_VDE] [get_bd_pins rgb2dvi_0/vid_pVDE]

puts "Phase 4: Video data path connected"

# ===========================================================================
# PHASE 5: BUTTON / SWITCH / LED
# ===========================================================================

connect_bd_net [get_bd_ports btn] [get_bd_pins btn_ctrl_0/btn_raw]
connect_bd_net [get_bd_ports sw] [get_bd_pins btn_ctrl_0/sw0_raw]
connect_bd_net [get_bd_pins btn_ctrl_0/led] [get_bd_ports led]

# btn_ctrl outputs → filter btn inputs
connect_bd_net [get_bd_pins btn_ctrl_0/cc_btn] [get_bd_pins colour_change_0/btn]
connect_bd_net [get_bd_pins btn_ctrl_0/mf_btn] [get_bd_pins multi_filter_select_0/btn]

puts "Phase 5: Buttons, switch, LEDs connected"

# ===========================================================================
# PHASE 6: AXI GPIO → SLICES → CONTROL INPUTS
# ===========================================================================

# GPIO_0 ch1 → all control slices
connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] \
    [get_bd_pins slice_comp_mode/Din] \
    [get_bd_pins slice_filter_a/Din] \
    [get_bd_pins slice_filter_b/Din] \
    [get_bd_pins slice_branch/Din] \
    [get_bd_pins slice_override/Din] \
    [get_bd_pins slice_edge_thresh/Din]

# GPIO_0 ch2 → wipe slice
connect_bd_net [get_bd_pins axi_gpio_0/gpio2_io_o] [get_bd_pins slice_wipe/Din]

# GPIO_1 ch1 → ROI x,y slices
connect_bd_net [get_bd_pins axi_gpio_1/gpio_io_o] \
    [get_bd_pins slice_roi_x/Din] \
    [get_bd_pins slice_roi_y/Din]

# GPIO_1 ch2 → ROI w,h slices
connect_bd_net [get_bd_pins axi_gpio_1/gpio2_io_o] \
    [get_bd_pins slice_roi_w/Din] \
    [get_bd_pins slice_roi_h/Din]

# Slices → btn_ctrl_0
connect_bd_net [get_bd_pins slice_comp_mode/Dout] [get_bd_pins btn_ctrl_0/sw_comp_mode]
connect_bd_net [get_bd_pins slice_filter_a/Dout] [get_bd_pins btn_ctrl_0/sw_filter_sel_a]
connect_bd_net [get_bd_pins slice_filter_b/Dout] [get_bd_pins btn_ctrl_0/sw_filter_sel_b]
connect_bd_net [get_bd_pins slice_branch/Dout] [get_bd_pins btn_ctrl_0/sw_branch_sel]
connect_bd_net [get_bd_pins slice_override/Dout] [get_bd_pins btn_ctrl_0/sw_override]

# Slices → video_compositor_0
connect_bd_net [get_bd_pins btn_ctrl_0/comp_mode] [get_bd_pins video_compositor_0/comp_mode]
connect_bd_net [get_bd_pins btn_ctrl_0/branch_sel] [get_bd_pins video_compositor_0/branch_sel]
connect_bd_net [get_bd_pins slice_wipe/Dout] [get_bd_pins video_compositor_0/wipe_pos]
connect_bd_net [get_bd_pins slice_roi_x/Dout] [get_bd_pins video_compositor_0/roi_x]
connect_bd_net [get_bd_pins slice_roi_y/Dout] [get_bd_pins video_compositor_0/roi_y]
connect_bd_net [get_bd_pins slice_roi_w/Dout] [get_bd_pins video_compositor_0/roi_w]
connect_bd_net [get_bd_pins slice_roi_h/Dout] [get_bd_pins video_compositor_0/roi_h]
connect_bd_net [get_bd_pins slice_edge_thresh/Dout] [get_bd_pins video_compositor_0/edge_thresh]

puts "Phase 6: AXI GPIO control path connected"

# ===========================================================================
# PHASE 7: ADDRESS MAP
# ===========================================================================

assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
assign_bd_address -offset 0x41210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_1/S_AXI/Reg] -force

puts "Phase 7: Address map assigned"

# ===========================================================================
# PHASE 8: VALIDATE AND SAVE
# ===========================================================================

regenerate_bd_layout
validate_bd_design
save_bd_design

puts "================================================================"
puts " DONE! Compositor integration complete."
puts ""
puts " Added: video_compositor_0, btn_ctrl_0, axi_gpio_0, axi_gpio_1"
puts "        + 11 xlslice blocks for register decoding"
puts " Addresses: axi_gpio_0 @ 0x41200000, axi_gpio_1 @ 0x41210000"
puts ""
puts " Next steps:"
puts "   1. Right-click system.bd -> Create HDL Wrapper (let Vivado manage)"
puts "   2. Run Synthesis -> Implementation -> Generate Bitstream"
puts "================================================================"
