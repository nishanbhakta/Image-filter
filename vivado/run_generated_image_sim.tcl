# Usage:
#   vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs generated_data
#   vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs generated_data my_project 100T
#   vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs generated_data my_project 100T --reset-runs
#
# Arguments:
#   1. generated data dir (default: generated_data)
#   2. simulation project name (default: cnn_generated_image_sim)
#   3. board variant           (default: 100T, supported: 100T, 50T)
#   4. optional flag           (--reset-runs to clear synth/impl results first)
#
# This script opens or creates a saved Vivado simulation project under
# vivado_build/, points the testbench at generated image data, launches
# behavioral simulation, adds common waves, runs the test to completion, and
# then compares the generated hardware output against the golden CSV.

set reset_runs 0
set positional_args {}
foreach arg $argv {
    if {$arg eq "--reset-runs"} {
        set reset_runs 1
    } else {
        lappend positional_args $arg
    }
}

if {[llength $positional_args] >= 1} {
    set generated_data_arg [lindex $positional_args 0]
} else {
    set generated_data_arg "generated_data"
}

if {[llength $positional_args] >= 2} {
    set project_name [lindex $positional_args 1]
} else {
    set project_name "cnn_generated_image_sim"
}

if {[llength $positional_args] >= 3} {
    set board_variant [string toupper [lindex $positional_args 2]]
} else {
    set board_variant "100T"
}

if {[llength $positional_args] > 3} {
    puts "Too many positional arguments. Usage: <generated_data_dir> ?<project_name>? ?<board_variant>? ?--reset-runs?"
    exit 1
}

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set generated_data_dir [file normalize [file join $repo_root $generated_data_arg]]
set generated_include [file join $generated_data_dir "generated_windows.vh"]
set input_windows_csv [file normalize [file join $generated_data_dir "input_windows.csv"]]
set golden_output_csv [file normalize [file join $generated_data_dir "golden_output.csv"]]
set output_csv [file normalize [file join $generated_data_dir "output.csv"]]
set output_trace_csv [file normalize [file join $generated_data_dir "output_trace.csv"]]
set comparison_csv [file normalize [file join $generated_data_dir "output_comparison.csv"]]
set vivado_vcd_file [file normalize [file join $generated_data_dir "cnn_generated_vivado.vcd"]]
set project_dir [file normalize [file join $repo_root "vivado_build" $project_name]]
set project_file [file join $project_dir "${project_name}.xpr"]
set compare_script [file normalize [file join $repo_root "scripts" "compare_feature_maps.py"]]

proc path_for_define {path_value} {
    return [string map {\\ /} [file normalize $path_value]]
}

proc python_command {} {
    foreach candidate {python python3} {
        set executable [auto_execok $candidate]
        if {$executable ne ""} {
            return [list $executable]
        }
    }

    return {}
}

switch -- $board_variant {
    "100T" { set fpga_part "xc7a100tcsg324-1" }
    "50T"  { set fpga_part "xc7a50tcsg324-1" }
    default {
        puts "Unsupported variant '$board_variant'. Use 100T or 50T."
        exit 1
    }
}

set source_files [list \
    [file join $repo_root "src" "multiplier.v"] \
    [file join $repo_root "src" "MAC.v"] \
    [file join $repo_root "src" "divide_by_9_Version2.v"] \
    [file join $repo_root "src" "divider_Version2.v"] \
    [file join $repo_root "src" "controller_Version2.v"] \
    [file join $repo_root "src" "cnn_accelerator_Version2.v"] \
    [file join $repo_root "src" "cnn_generated_image_runner.v"] \
    [file join $repo_root "src" "uart_tx.v"] \
    [file join $repo_root "src" "uart_result_streamer.v"] \
    [file join $repo_root "board" "nexys_a7_generated_image_top.v"] \
]

set sim_files [list \
    [file join $repo_root "tb" "cnn_accelerator_tb_Version2.v"] \
]

set constraint_files [list \
    [file join $repo_root "board" "nexys_a7_top.xdc"] \
]

proc ensure_files_exist {files} {
    foreach file_path $files {
        if {![file exists $file_path]} {
            puts "Required file not found: $file_path"
            exit 1
        }
    }
}

proc sync_files_in_set {fileset_name files} {
    set fileset [get_filesets $fileset_name]
    set desired_files {}

    foreach file_path $files {
        lappend desired_files [file normalize $file_path]
    }

    foreach file_obj [get_files -quiet -of_objects $fileset] {
        set normalized_existing [file normalize [get_property NAME $file_obj]]
        if {[lsearch -exact $desired_files $normalized_existing] < 0} {
            remove_files -fileset $fileset $file_obj
        }
    }

    foreach file_path $desired_files {
        set existing_file [get_files -quiet -of_objects $fileset $file_path]
        if {$existing_file eq ""} {
            add_files -norecurse -fileset $fileset $file_path
        }
    }
}

if {![file exists $generated_data_dir]} {
    puts "Generated data directory not found: $generated_data_dir"
    exit 1
}

if {![file exists $generated_include]} {
    puts "Generated include not found: $generated_include"
    puts "Run scripts/run_image_sim.py or scripts/preprocess_image.py first."
    exit 1
}

ensure_files_exist $source_files
ensure_files_exist $sim_files
ensure_files_exist $constraint_files

catch {close_sim -force}
catch {close_project}

if {[file exists $project_file]} {
    open_project $project_file
} else {
    if {![file exists $project_dir]} {
        file mkdir $project_dir
    }
    create_project $project_name $project_dir -part $fpga_part -force
}

sync_files_in_set sources_1 $source_files
sync_files_in_set sim_1 $sim_files
sync_files_in_set constrs_1 $constraint_files

foreach file_path $source_files {
    set_property file_type SystemVerilog [get_files $file_path]
}

foreach file_path $sim_files {
    set_property file_type SystemVerilog [get_files $file_path]
}

set sim_fileset [get_filesets sim_1]
set source_fileset [get_filesets sources_1]
set sim_defines [list \
    USE_GENERATED_IMAGE_DATA \
    "CNN_ACTUAL_OUTPUT_CSV=\"[path_for_define $output_csv]\"" \
    "CNN_ACTUAL_TRACE_CSV=\"[path_for_define $output_trace_csv]\"" \
    "CNN_VCD_FILE=\"[path_for_define $vivado_vcd_file]\"" \
]

set_property top nexys_a7_generated_image_top $source_fileset
set_property top cnn_accelerator_tb $sim_fileset
set_property include_dirs [list $generated_data_dir] $source_fileset
set_property include_dirs [list $generated_data_dir] $sim_fileset
set_property verilog_define $sim_defines $sim_fileset

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

if {$reset_runs} {
    puts "Resetting synth_1 and impl_1 before launching simulation."
    catch {reset_run synth_1}
    catch {reset_run impl_1}
} else {
    puts "Preserving existing synth_1 and impl_1 results."
}

launch_simulation -simset sim_1 -mode behavioral
restart

catch {add_wave /cnn_accelerator_tb/*}
catch {add_wave /cnn_accelerator_tb/dut/*}
catch {add_wave /cnn_accelerator_tb/generated_output_vram}
catch {add_wave /cnn_accelerator_tb/generated_output_valid}

run all

puts ""
if {![file exists $output_csv]} {
    puts "Hardware output CSV was not generated: $output_csv"
} elseif {![file exists $golden_output_csv]} {
    puts "Golden output CSV was not found: $golden_output_csv"
} elseif {![file exists $compare_script]} {
    puts "Comparison helper was not found: $compare_script"
} else {
    set python_cmd [python_command]
    if {[llength $python_cmd] == 0} {
        puts "Python was not found in PATH, so the comparison report was skipped."
    } else {
        set compare_command $python_cmd
        lappend compare_command $compare_script $golden_output_csv $output_csv --comparison-csv $comparison_csv
        if {[catch {exec {*}$compare_command} compare_output]} {
            puts "Comparison step failed:"
            puts $compare_output
        } else {
            puts "Comparison step complete."
            puts $compare_output
        }
    }
}

puts ""
puts "Vivado generated-image simulation complete."
puts "Simulation project: $project_name"
puts "Project file       : $project_file"
puts "Synth top          : nexys_a7_generated_image_top"
puts "Generated data dir : $generated_data_dir"
puts "Input CSV          : $input_windows_csv"
puts "Golden output CSV  : $golden_output_csv"
puts "Hardware output CSV: $output_csv"
puts "Output trace CSV   : $output_trace_csv"
puts "Comparison CSV     : $comparison_csv"
puts "Vivado VCD dump    : $vivado_vcd_file"
puts "Reset synth/impl   : [expr {$reset_runs ? \"yes\" : \"no\"}]"
puts "Implementation note: the synth top now wraps the generated runner in a constrained Nexys A7 board top, so bitstream generation can target real board pins."
puts "Inspect the Wave window in Vivado for the full testbench trace."
