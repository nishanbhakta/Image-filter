# Usage:
#   vivado -mode batch -source vivado/create_project.tcl
#   vivado -mode batch -source vivado/create_project.tcl -tclargs my_project 100T
#
# Arguments:
#   1. project name   (default: cnn_accelerator_nexys_a7)
#   2. board variant  (default: 100T, supported: 100T, 50T)

if {[llength $argv] >= 1} {
    set project_name [lindex $argv 0]
} else {
    set project_name "cnn_accelerator_nexys_a7"
}

if {[llength $argv] >= 2} {
    set board_variant [string toupper [lindex $argv 1]]
} else {
    set board_variant "100T"
}

switch -- $board_variant {
    "100T" { set fpga_part "xc7a100tcsg324-1" }
    "50T"  { set fpga_part "xc7a50tcsg324-1" }
    default {
        puts "Unsupported variant '$board_variant'. Use 100T or 50T."
        exit 1
    }
}

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set project_dir [file normalize [file join $repo_root "vivado_build" $project_name]]

create_project $project_name $project_dir -part $fpga_part -force

set source_files [list \
    [file join $repo_root "src" "multiplier.v"] \
    [file join $repo_root "src" "MAC.v"] \
    [file join $repo_root "src" "divide_by_9_Version2.v"] \
    [file join $repo_root "src" "divider_Version2.v"] \
    [file join $repo_root "src" "controller_Version2.v"] \
    [file join $repo_root "src" "cnn_accelerator_Version2.v"] \
    [file join $repo_root "board" "nexys_a7_top.v"] \
]

set sim_files [list \
    [file join $repo_root "tb" "multiplier_tb_Version2.v"] \
    [file join $repo_root "tb" "mac_tb_Version2.v"] \
    [file join $repo_root "tb" "divide_by_9_Version2.v"] \
    [file join $repo_root "tb" "divider_tb_Version2.v"] \
    [file join $repo_root "tb" "cnn_accelerator_tb_Version2.v"] \
]

set constraint_files [list \
    [file join $repo_root "board" "nexys_a7_top.xdc"] \
]

add_files -norecurse -fileset sources_1 $source_files
add_files -norecurse -fileset sim_1 $sim_files
add_files -norecurse -fileset constrs_1 $constraint_files

foreach file $source_files {
    set_property file_type SystemVerilog [get_files $file]
}

foreach file $sim_files {
    set_property file_type SystemVerilog [get_files $file]
}

set_property top nexys_a7_top [get_filesets sources_1]
set_property top cnn_accelerator_tb [get_filesets sim_1]
set_property target_constrs_file [file join $repo_root "board" "nexys_a7_top.xdc"] [current_project]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Created Vivado project:"
puts "  Name:  $project_name"
puts "  Part:  $fpga_part"
puts "  Dir:   $project_dir"
puts "  Synth top: nexys_a7_top"
puts "  Sim top:   cnn_accelerator_tb"
puts ""
puts "Next steps inside Vivado:"
puts "  1. Open I/O Planning or Elaborated Design to confirm ports."
puts "  2. Run Synthesis."
puts "  3. Run Implementation."
puts "  4. Generate Bitstream."
