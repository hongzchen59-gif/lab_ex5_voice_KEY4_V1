# SDC-only recheck of THIS version's existing routed database. Never use after
# any RTL, pin or clock-configuration change; then use build_td.tcl instead.
set root [file normalize [file join [file dirname [info script]] ..]]
cd [file join $root td_project cli_build]
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.prj -noanalyze
    import_db camera_to_dsi_display_pr.db
    clear_sdc -user
    read_sdc [file join $root td_project camera_to_dsi_display.sdc]
    update_timing -mode final
    report_timing_status -file camera_to_dsi_display_phy.ts
    report_timing_summary -file camera_to_dsi_display_pr.timing
    report_timing_exception -file camera_to_dsi_display_exception.timing
    report_area -io_info -file camera_to_dsi_display_phy.area
    set f [open camera_to_dsi_display_phy.ts r]
    set result [read $f];close $f
    if {![regexp {SWNS:\s+(-?[0-9.]+)ns} $result -> setup] ||
        ![regexp {HWNS:\s+(-?[0-9.]+)ns} $result -> hold]} {error "Missing timing status"}
    if {$setup<0 || $hold<0} {error "Timing failed setup=$setup hold=$hold"}
    export_db camera_to_dsi_display_pr.db
    bitgen -bit camera_to_dsi_display.bit
    puts "VOICE_ROUTED_TIMING_AND_BIT_PASS setup=$setup hold=$hold"
} reason]} {
    puts stderr "VOICE_FINALIZE_ERROR: $reason"
    exit 1
}
exit
