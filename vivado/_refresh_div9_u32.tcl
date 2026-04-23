set repo_root [pwd]
set src_dir [file join $repo_root "src"]
set out_dir [file join $repo_root "vivado_build" "arithmetic_reports"]
file mkdir $out_dir
create_project div9_u32_refresh [file join $out_dir "div9_u32_refresh"] -part xc7a100tcsg324-1 -force
read_verilog [file join $src_dir "divide_by_9_Version2.v"]
synth_design -top divide_by_9 -part xc7a100tcsg324-1 -generic WIDTH=32
create_clock -name clk -period 10.000 [get_ports clk]
report_utilization -file [file join $out_dir "divide_by_9_u32_util.rpt"]
report_timing_summary -delay_type max -max_paths 5 -file [file join $out_dir "divide_by_9_u32_timing.rpt"]
close_project
