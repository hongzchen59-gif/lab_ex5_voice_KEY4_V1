# Export TOON_R4 after a successful full RTL build.
# Export only; no hardware programming.
set output_dir [file normalize [file dirname [info script]]]
set routed_dir {D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/td_project/cli_build}
cd $routed_dir
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.prj -noanalyze
    import_db camera_to_dsi_display_pr.db
    # This TD command's filename parser requires a literal, not a Tcl [file join].
    # The baseline .bit is not overwritten by a bin-only export.
    bitgen -bin camera_to_dsi_display.bin
    file copy -force camera_to_dsi_display.bin [file join $output_dir voice_toon_r4_fpga.bin]
    file copy -force camera_to_dsi_display.bit [file join $output_dir voice_toon_r4.bit]
    puts "STANDALONE_FPGA_BIN_EXPORT_PASS"
} reason]} {
    puts stderr "STANDALONE_FPGA_BIN_EXPORT_ERROR: $reason"
    exit 1
}
exit
