# ===========================================================================
# run_lab2_sweep.tcl — Automated Lab 2 HLS pragma sweep
#
# Runs in Vitis HLS 2024.1 (NOT Vivado).
# Synthesizes all 7 pragma variants x 2 bit widths = 14 configurations.
# Outputs results to a CSV file.
#
# Usage: Open Vitis HLS TCL console, then:
#   cd C:/ES3F1/lab_results
#   source run_lab2_sweep.tcl
#
# Requires: matrix_mult.h and tb_matrix_mult.cpp in same directory
# ===========================================================================

set script_dir [file normalize [file dirname [info script]]]
set output_dir "$script_dir/lab2_results"
file mkdir $output_dir

# Results CSV
set csv_file "$output_dir/lab2_synthesis_results.csv"
set csv_fd [open $csv_file w]
puts $csv_fd "variant,bit_width,target_ns,estimated_ns,uncertainty_ns,latency_cycles,latency_ns,lut,ff,dsp,bram,uram"

# Define variants: {name, pragma_code_for_loops}
# The base code has 3 loops: ROWS_LOOP, COLS_LOOP, MULT_ACC_LOOP
set variants {
    {baseline         "// no pragmas"}
    {unroll_mult2     "#pragma HLS unroll factor=2"}
    {unroll_mult_full "#pragma HLS unroll"}
    {unroll_cols2     "COLS_UNROLL"}
    {pipe_cols_ii2    "PIPE_II2"}
    {pipe_cols_ii1    "PIPE_II1"}
    {pipe_ii1_unroll2 "PIPE_II1_UNROLL2"}
}

set bit_widths {32 16}

foreach bw $bit_widths {
    foreach variant $variants {
        set vname [lindex $variant 0]
        set full_name "${vname}_${bw}"

        puts "============================================"
        puts "  Running: $full_name"
        puts "============================================"

        # Create the .cpp file with appropriate pragmas
        set cpp_fd [open "$output_dir/matrix_mult_${full_name}.cpp" w]
        puts $cpp_fd "/* Auto-generated variant: $full_name */"
        puts $cpp_fd "#include \"matrix_mult.h\""
        puts $cpp_fd ""
        puts $cpp_fd "void array_mult (stream_data &in_a, data in_b\[ROWS*COLS\], stream_data &result)"
        puts $cpp_fd "\{"
        puts $cpp_fd "    #pragma HLS INTERFACE s_axilite port=return bundle=CTRL"
        puts $cpp_fd "    #pragma HLS INTERFACE s_axilite port=in_b bundle=DATA_IN_B"
        puts $cpp_fd "    #pragma HLS INTERFACE axis port=in_a"
        puts $cpp_fd "    #pragma HLS INTERFACE axis port=result"
        puts $cpp_fd ""
        puts $cpp_fd "    data i,j,k;"
        puts $cpp_fd "    packet mult_acc;"
        puts $cpp_fd "    packet in_a_store\[ROWS*COLS\];"
        puts $cpp_fd ""
        puts $cpp_fd "    for (i=0;i<ROWS*COLS;i++) \{"
        puts $cpp_fd "        in_a.read(in_a_store\[i\]);"
        puts $cpp_fd "    \}"
        puts $cpp_fd ""
        puts $cpp_fd "    ROWS_LOOP: for (i=0;i<ROWS;i++) \{"

        # COLS_LOOP pragmas
        if {$vname eq "unroll_cols2"} {
            puts $cpp_fd "        COLS_LOOP: for (j=0;j<COLS;j++) \{"
            puts $cpp_fd "            #pragma HLS unroll factor=2"
        } elseif {$vname eq "pipe_cols_ii2"} {
            puts $cpp_fd "        COLS_LOOP: for (j=0;j<COLS;j++) \{"
            puts $cpp_fd "            #pragma HLS pipeline II=2"
        } elseif {$vname eq "pipe_cols_ii1"} {
            puts $cpp_fd "        COLS_LOOP: for (j=0;j<COLS;j++) \{"
            puts $cpp_fd "            #pragma HLS pipeline II=1"
        } elseif {$vname eq "pipe_ii1_unroll2"} {
            puts $cpp_fd "        COLS_LOOP: for (j=0;j<COLS;j++) \{"
            puts $cpp_fd "            #pragma HLS pipeline II=1"
        } else {
            puts $cpp_fd "        COLS_LOOP: for (j=0;j<COLS;j++) \{"
        }

        puts $cpp_fd "            mult_acc.data=0;"
        puts $cpp_fd ""

        # MULT_ACC_LOOP pragmas
        if {$vname eq "unroll_mult2" || $vname eq "pipe_ii1_unroll2"} {
            puts $cpp_fd "            MULT_ACC_LOOP: for (k=0;k<MULT_ACC;k++) \{"
            puts $cpp_fd "                #pragma HLS unroll factor=2"
        } elseif {$vname eq "unroll_mult_full"} {
            puts $cpp_fd "            MULT_ACC_LOOP: for (k=0;k<MULT_ACC;k++) \{"
            puts $cpp_fd "                #pragma HLS unroll"
        } else {
            puts $cpp_fd "            MULT_ACC_LOOP: for (k=0;k<MULT_ACC;k++) \{"
        }

        puts $cpp_fd "                mult_acc.data+=in_a_store\[i*ROWS+k\].data*in_b\[k*ROWS+j\];"
        puts $cpp_fd "                mult_acc.last=in_a_store\[i*ROWS+k\].last&(j==(COLS-1));"
        puts $cpp_fd "                mult_acc.keep = in_a_store\[i*ROWS+k\].keep;"
        puts $cpp_fd "                mult_acc.strb = in_a_store\[i*ROWS+k\].strb;"
        puts $cpp_fd "            \}"
        puts $cpp_fd ""
        puts $cpp_fd "            result.write(mult_acc);"
        puts $cpp_fd "        \}"
        puts $cpp_fd "    \}"
        puts $cpp_fd "\}"
        close $cpp_fd

        # Create header with appropriate bit width
        set h_fd [open "$output_dir/matrix_mult.h" w]
        puts $h_fd "#include \"ap_axi_sdata.h\""
        puts $h_fd "#include \"hls_stream.h\""
        puts $h_fd "#include \"ap_int.h\""
        puts $h_fd ""
        puts $h_fd "#define SIZE 5"
        puts $h_fd "#define ROWS SIZE"
        puts $h_fd "#define COLS SIZE"
        puts $h_fd "#define MULT_ACC SIZE"
        puts $h_fd "#define MAX_VAL 10"
        puts $h_fd "#define MIN_VAL 0"
        puts $h_fd "#define BIT_W $bw"
        puts $h_fd ""
        puts $h_fd "typedef ap_axis<BIT_W,0,0,0> packet;"
        puts $h_fd "typedef ap_int<BIT_W> data;"
        puts $h_fd "typedef hls::stream<packet> stream_data;"
        puts $h_fd ""
        puts $h_fd "void array_mult (stream_data &in_a, data in_b\[ROWS*COLS\], stream_data &result);"
        close $h_fd

        # Run HLS
        catch {close_project}

        open_project -reset "hls_${full_name}"
        set_top array_mult
        add_files "$output_dir/matrix_mult_${full_name}.cpp" -cflags "-I$output_dir"
        add_files -tb "$script_dir/../lab_2_files/tb_matrix_mult.cpp" -cflags "-I$output_dir"
        open_solution -reset "sol1" -flow_target vivado
        set_part {xc7z020clg400-1}
        create_clock -period 10 -name default

        # Run C simulation
        catch { csim_design }

        # Run C synthesis
        if { [catch { csynth_design } err] } {
            puts "SYNTHESIS FAILED for $full_name: $err"
            puts $csv_fd "$full_name,$bw,FAILED,,,,,,,,"
            catch {close_project}
            continue
        }

        # Extract results from synthesis report
        set rpt_file "hls_${full_name}/sol1/syn/report/csynth.xml"
        if {[file exists $rpt_file]} {
            set rpt_fd [open $rpt_file r]
            set rpt_content [read $rpt_fd]
            close $rpt_fd

            # Parse XML for key metrics
            set est_ns "N/A"
            set unc_ns "N/A"
            set lat_cyc "N/A"
            set lat_ns "N/A"
            set lut "N/A"
            set ff "N/A"
            set dsp "N/A"
            set bram "N/A"
            set uram "N/A"

            regexp {<EstimatedClockPeriod>(.*?)</EstimatedClockPeriod>} $rpt_content -> est_ns
            regexp {<Uncertainty>(.*?)</Uncertainty>} $rpt_content -> unc_ns
            regexp {<Best-caseLatency>(.*?)</Best-caseLatency>} $rpt_content -> lat_cyc
            regexp {<Best-caseRealTimeLatency>(.*?)</Best-caseRealTimeLatency>} $rpt_content -> lat_ns
            regexp {<LUT>(.*?)</LUT>} $rpt_content -> lut
            regexp {<FF>(.*?)</FF>} $rpt_content -> ff
            regexp {<DSP>(.*?)</DSP>} $rpt_content -> dsp
            regexp {<BRAM_18K>(.*?)</BRAM_18K>} $rpt_content -> bram
            regexp {<URAM>(.*?)</URAM>} $rpt_content -> uram

            puts $csv_fd "$full_name,$bw,10,$est_ns,$unc_ns,$lat_cyc,$lat_ns,$lut,$ff,$dsp,$bram,$uram"
            puts "  Results: LUT=$lut FF=$ff DSP=$dsp BRAM=$bram Latency=$lat_cyc cycles"
        } else {
            # Try alternative report path
            set rpt_file2 "hls_${full_name}/sol1/syn/report/array_mult_csynth.xml"
            if {[file exists $rpt_file2]} {
                set rpt_fd [open $rpt_file2 r]
                set rpt_content [read $rpt_fd]
                close $rpt_fd

                set est_ns "N/A"; set unc_ns "N/A"; set lat_cyc "N/A"
                set lat_ns "N/A"; set lut "N/A"; set ff "N/A"
                set dsp "N/A"; set bram "N/A"; set uram "N/A"

                regexp {<EstimatedClockPeriod>(.*?)</EstimatedClockPeriod>} $rpt_content -> est_ns
                regexp {<Uncertainty>(.*?)</Uncertainty>} $rpt_content -> unc_ns
                regexp {<Best-caseLatency>(.*?)</Best-caseLatency>} $rpt_content -> lat_cyc
                regexp {<LUT>(.*?)</LUT>} $rpt_content -> lut
                regexp {<FF>(.*?)</FF>} $rpt_content -> ff
                regexp {<DSP>(.*?)</DSP>} $rpt_content -> dsp
                regexp {<BRAM_18K>(.*?)</BRAM_18K>} $rpt_content -> bram
                regexp {<URAM>(.*?)</URAM>} $rpt_content -> uram

                puts $csv_fd "$full_name,$bw,10,$est_ns,$unc_ns,$lat_cyc,$lat_ns,$lut,$ff,$dsp,$bram,$uram"
                puts "  Results: LUT=$lut FF=$ff DSP=$dsp BRAM=$bram Latency=$lat_cyc cycles"
            } else {
                puts "  WARNING: No synthesis report found"
                puts $csv_fd "$full_name,$bw,NO_REPORT,,,,,,,,"
            }
        }

        # Package for Lab 3 (only the fully-unrolled 32-bit variant)
        if {$vname eq "unroll_mult_full" && $bw == 32} {
            catch { export_design -format ip_catalog -output "$output_dir/array_mult_ip.zip" }
            puts "  Packaged IP for Lab 3"
        }

        catch {close_project}
    }
}

close $csv_fd

puts ""
puts "============================================"
puts " Lab 2 sweep complete!"
puts " Results: $csv_file"
puts "============================================"
