# Usage:
#   vivado -mode batch -source vivado/run_arithmetic_reports.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set src_dir [file join $repo_root "src"]
set out_dir [file join $repo_root "vivado_build" "arithmetic_reports"]
set part_name "xc7a100tcsg324-1"
set clk_period_ns 10.000

file mkdir $out_dir

proc run_block {name top src_files out_dir part_name clk_period_ns} {
    puts "\n=== Running synthesis for $name (top: $top) ==="

    create_project ${name}_ooc [file join $out_dir ${name}_ooc] -part $part_name -force

    foreach src_file $src_files {
        read_verilog $src_file
    }

    synth_design -top $top -part $part_name

    if {[llength [get_ports clk]] > 0} {
        create_clock -name clk -period $clk_period_ns [get_ports clk]
    }

    report_utilization -file [file join $out_dir "${name}_util.rpt"]
    report_timing_summary -delay_type max -max_paths 5 -file [file join $out_dir "${name}_timing.rpt"]

    close_project
}

run_block "multiplier" "multiplier" [list \
    [file join $src_dir "multiplier.v"] \
] $out_dir $part_name $clk_period_ns

run_block "mac" "mac" [list \
    [file join $src_dir "multiplier.v"] \
    [file join $src_dir "MAC.v"] \
] $out_dir $part_name $clk_period_ns

run_block "divide_by_9" "divide_by_9" [list \
    [file join $src_dir "divide_by_9_Version2.v"] \
] $out_dir $part_name $clk_period_ns

run_block "divider" "divider" [list \
    [file join $src_dir "divider_Version2.v"] \
] $out_dir $part_name $clk_period_ns

run_block "cnn_accelerator_core" "cnn_accelerator" [list \
    [file join $src_dir "multiplier.v"] \
    [file join $src_dir "MAC.v"] \
    [file join $src_dir "divider_Version2.v"] \
    [file join $src_dir "divide_by_9_Version2.v"] \
    [file join $src_dir "controller_Version2.v"] \
    [file join $src_dir "cnn_accelerator_Version2.v"] \
] $out_dir $part_name $clk_period_ns

puts "\nArithmetic report generation complete. Reports are in: $out_dir"
