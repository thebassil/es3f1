# ES3F1 Submission Checklist

## Phase 1: Test Lab 4 features on hardware

- [ ] Pull latest from GitHub (`git pull`)
- [ ] Replace `main.cc` in Vitis with `vitis_sources/main.cc`, add `#include "xuartps.h"`, rebuild
- [ ] Program board with latest bitstream
- [ ] **Test single-pixel filters**: SW0=0, press BTN0 (brightness), BTN1 (gamma), BTN2 (threshold)
- [ ] **Test multi-pixel filters**: SW0=1, press BTN0 (sobel), BTN1 (erosion), BTN2 (dilation)
- [ ] **Test split-screen**: press BTN3 once - left=original, right=filtered at midpoint
- [ ] **Test wipe mode**: press BTN3 again - same as split (moves via UART)
- [ ] **Test ROI spotlight**: press BTN3 again - filtered box in centre
- [ ] **Test edge overlay**: press BTN3 again - white cartoon outlines on colour
- [ ] **Test mode wrap**: press BTN3 again - back to full-screen filtered
- [ ] **Test LEDs**: LED[3:2] change pattern with each BTN3 press
- [ ] **Test UART menu**: connect serial 115200, type `i` then `2` - split activates
- [ ] **Test wipe position**: type `j` then `1` - divider moves left
- [ ] **Test ROI presets**: type `i` then `4`, then `k` then `2` - small box
- [ ] **Test edge threshold**: type `i` then `5`, then `n` then `1` - lots of edges
- [ ] **Test auto-demo**: type `m` - wipe sweeps, filters cycle, any key stops
- [ ] **Record 10-min demo video** showing all features

## Phase 2: Lab 2 HLS sweep (run concurrently with report writing)

- [ ] Open **Vitis HLS 2024.1** on the machine
- [ ] In TCL console: `cd C:/ES3F1/ES3F1_Lab_4/lab_results` then `source run_lab2_sweep.tcl`
- [ ] Wait ~30 min for all 14 variants to synthesize
- [ ] Collect `lab2_results/lab2_synthesis_results.csv`
- [ ] Copy CSV to report - make a table comparing LUTs, FFs, DSPs, latency across variants

## Phase 3: Lab 1 data (quick, while Lab 2 runs)

- [ ] Open existing Lab 1 Vivado project (`LAB1/lab_1_vivado`)
- [ ] Open existing Lab 1 Vitis workspace (`LAB1/lab_1_vitis`)
- [ ] Run `matrix_mult` application on the board
- [ ] Screenshot serial output showing matrix result + timing
- [ ] Note down SW execution time in cycles

## Phase 4: Lab 3 HW vs SW (after Lab 2 finishes)

- [ ] Take the packaged IP from Lab 2 sweep (`lab2_results/array_mult_ip.zip`)
- [ ] Open existing Lab 3 Vivado project or create new one per lab guide
- [ ] Add IP repo, build block design, generate bitstream, export XSA
- [ ] Create Vitis platform from XSA, import `lab3.c`, `platform.c`, `platform.h`
- [ ] Run on board, screenshot serial output showing SW cycles vs HW cycles + speedup
- [ ] Record: SW cycles, HW cycles, speedup, correct match

## Phase 5: Write report (start during Phase 2, finish after Phase 4)

- [ ] **Intro + background** (1 page): Zynq platform, HLS overview, project objectives
- [ ] **Labs 1-3 discussion** (3 pages): Lab 1 overview, Lab 2 pragma comparison table with discussion, Lab 3 HW vs SW table with discussion
- [ ] **Lab 4 design description** (4 pages): block diagram, compositor module, btn_ctrl module, filter modules, AXI GPIO register map, software menu
- [ ] **Extra features + creative** (1 page): split-screen, wipe, ROI, edge overlay, auto-demo
- [ ] **Testbench + testing** (0.5 page): iverilog simulation results, hardware test procedure
- [ ] **Conclusion + reflection** (0.5 page): what worked, limitations, future improvements
- [ ] Code in appendix with syntax highlighting (does NOT count toward 10 pages)
- [ ] Harvard referencing
- [ ] 11pt Arial, 1.5 spacing, 25mm margins
- [ ] Export as PDF: `studentnumber_ES3F1-ES4F3_Lab Report.pdf`

## Phase 6: Package submission

- [ ] Zip: demo video + Vivado project folder -> `studentnumber_ES3F1-ES4F3_Demonstration.zip`
- [ ] Submit PDF + zip to Tabula before Wednesday 12 noon Week 30
