# This script generates the Zybo-Z7-20-pcam-5c vivado project

#--------------------------------------------------------------
# Setup
#--------------------------------------------------------------

# Get directory of current script
set script_dir [file normalize [file dirname [info script]]]

# Change current working directory
cd $script_dir

# Check vivado verison
set scripts_vivado_version 2024.1
set current_vivado_version [version -short]
set valid_version [string equal $scripts_vivado_version $current_vivado_version]
if { $valid_version != 1 } {
  common::send_msg_id "BD_TCL-1002" "WARNING" "Vivado version is not $scripts_vivado_version"
  common::send_msg_id "BD_TCL-1003" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

#--------------------------------------------------------------
# Create Project
#--------------------------------------------------------------

set _project_name "pcam_filter"
set _project_dir_name "Zybo-Z7-20-pcam-filter"
create_project $_project_name $_project_dir_name -part xc7z020clg400-1

# Get project directory path
set proj_dir [get_property directory [current_project]]

# Set current project object
set obj [current_project]

# Set project properties
set_property -name "target_language" -value "VHDL" -objects $obj
set_property -name "xpm_libraries" -value "XPM_CDC XPM_FIFO XPM_MEMORY" -objects $obj

#--------------------------------------------------------------
# Create Sources
#--------------------------------------------------------------

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

# Set 'sources_1' fileset object
set obj [get_filesets sources_1]

# Set IP repository paths
set_property "ip_repo_paths" "[file normalize "$script_dir/ip_sources/repo"]" $obj

# Rebuild user ip_repo's index before adding any source files
update_ip_catalog -rebuild

# Import local files from the original project
set files [list \
  [file normalize "$script_dir/project_sources/sources_1/DVIClocking.vhd"]\
  [file normalize "$script_dir/project_sources/sources_1/SyncAsync.vhd"]\
  [file normalize "$script_dir/project_sources/sources_1/SyncAsyncReset.vhd"]\
  [file normalize "$script_dir/project_sources/sources_1/system_wrapper.vhd"]\
]
add_files -fileset sources_1 $files

# Set 'sources_1' fileset properties
set_property -name "top" -value "system_wrapper" -objects $obj
set_property -name "top_auto_set" -value "0" -objects $obj

#--------------------------------------------------------------
# Create Constraints
#--------------------------------------------------------------

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set obj [get_filesets constrs_1]

# Add/Import constrs file and set constrs file properties
set files [list \
  [file normalize "$script_dir/project_sources/constrs_1/ZyboZ7_A.xdc"]\
  [file normalize "$script_dir/project_sources/constrs_1/timing.xdc"]\
  [file normalize "$script_dir/project_sources/constrs_1/auto.xdc"]\
]
add_files -fileset constrs_1 $files

#--------------------------------------------------------------
# Create Block Designs
#--------------------------------------------------------------

source ./create_system_bd.tcl

#--------------------------------------------------------------
# Finish
#--------------------------------------------------------------

puts "INFO: Project created:$_project_name"
