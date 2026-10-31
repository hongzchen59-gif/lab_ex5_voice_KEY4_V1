# Run with td_commands_prompt.exe and forward slashes in the script argument.
set root [file normalize [file join [file dirname [info script]] ..]]
set td_root [file normalize [file join [file dirname [info nameofexecutable]] ..]]
set build_dir [file join $root td_project cli_build]
file mkdir $build_dir
cd $build_dir
if {[catch {
    # Normal .prj avoids GUI-run launcher and -single_run issues in TD 6.2.1.
    set preset_file [file join $root user_source data voice_templates.mem]
    if {![file exists $preset_file]} { error "Missing verified voice template initialization file" }
    file copy -force $preset_file [file join $build_dir voice_templates.mem]
    set f [open [file join $root td_project camera_to_dsi_display.al] r]
    set xml [read $f]; close $f
    set xml [string map [list "../user_source/" "$root/user_source/"] $xml]
    set f [open camera_to_dsi_display.prj w]
    puts $f {<?xml version="1.0" encoding="UTF-8"?>}
    puts $f {<Project Version="3" Minor="2">}
    puts $f {<Name>camera_to_dsi_display</Name>}
    foreach tag {HardWare Source_Files TOP_MODULE Configurations} {
        set pattern "<$tag>.*?</$tag>"
        if {![regexp -- $pattern $xml block]} { error "Missing $tag in .al project" }
        if {$tag eq "Source_Files"} {
            # An open GUI may save an older .al file list. These control
            # modules are required by voice_peripheral in this project.
            foreach {unit order} {voice_axis_control 100 voice_axis_follow 101 voice_button_inputs 102 video_motion 103 motion_overlay 104 video_latency 105 latency_overlay 106} {
                if {[string first "/${unit}.v\"" $block]<0} {
                    set src [file join $root user_source hdl_source ${unit}.v]
                    if {![file exists $src]} { error "Missing required axis source: $src" }
                    set entry [format {<File Path="%s"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="%s"/></FileInfo></File>} $src $order]
                    if {[string first "</Verilog>" $block]<0} { error "Missing Verilog source section" }
                    set block [string map [list "</Verilog>" "$entry\n</Verilog>"] $block]
                    puts "STYLE_BUILD_ADD_REQUIRED_SOURCE: ${unit}.v"
                }
            }
        }
        puts $f $block
    }
    puts $f {<FileSets><FileSet Name="design_1" Type="DesignFiles"/><FileSet Name="constraint_1" Type="ConstrainFiles"/></FileSets>}
    puts $f {<Property/><Device_Settings/></Project>}
    close $f
    set device_name ph1_35p.db
    set package_name PH1P35MDG324
    set speed 3
    set prj_name camera_to_dsi_display
    set top_model_name design_top_wrapper
    set start_step read_design
    set end_step bitgen
    set area_option -packarea
    set arr_filter false
    set drHoldFix on
    set ADCList [list [file join $root user_source constraints_source pin.adc]]
    set IpADCList [list ddr2 [file join $root user_source hdl_source ph1p35_ddr ddr2 src adc ddr2.adc]]
    set SDCList [list [file join $root td_project camera_to_dsi_display.sdc]]
    set IpSDCList [list ddr2 [file join $root user_source hdl_source ph1p35_ddr ddr2 src sdc ddr2.sdc] w128_d512_fifo [file join $root user_source ip_source w128_d512_fifo w128_d512_fifo.tcl]]
    # Explicit opt-in only; do not reuse an old synthesis by default.
    if {[info exists ::env(STYLE_RESUME_SYN)] && $::env(STYLE_RESUME_SYN)==1} {
        # Only reuse this new project's latest completed synthesis. This option
        # is for SDC-only repairs; RTL changes require the default full build.
        set parent $build_dir
        if {![file exists [file join $parent ${prj_name}_gate.db]]} { error "No synthesis database to resume" }
        set start_step opt_place
        # DefaultFlow reloads user SDC after import_db only when sp exists.
        set sp 1
    }
    if {[info exists ::env(STYLE_RESUME_PLACE)] && $::env(STYLE_RESUME_PLACE)==1} {
        if {![file exists ${prj_name}_place.db]} { error "No placement database to resume" }
        set start_step opt_route
        set sp 1
    }
    set f [open settings.cfg w]
    foreach name {device_name package_name speed prj_name top_model_name start_step end_step area_option arr_filter drHoldFix ADCList IpADCList SDCList IpSDCList parent sp} {
        if {[info exists $name]} { puts $f [list set $name [set $name]] }
    }
    close $f
    source [file join $td_root doc scripts DefaultFlow.tcl]
    # Bit generation can succeed even with timing violations; verify the report.
    set f [open ${prj_name}_phy.ts r]
    set timing_status [read $f];close $f
    if {![regexp {SWNS:\s+(-?[0-9.]+)ns} $timing_status -> setup_wns] ||
        ![regexp {HWNS:\s+(-?[0-9.]+)ns} $timing_status -> hold_wns]} {
        error "Cannot parse final timing status"
    }
    if {$setup_wns<0 || $hold_wns<0} {
        error "Final timing failed: setup=$setup_wns ns hold=$hold_wns ns"
    }
    puts "STYLE_TD_BUILD_FINISHED"
} reason]} {
    puts stderr "STYLE_TD_BUILD_ERROR: $reason"
    exit 1
}
exit
