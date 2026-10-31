set root [file normalize [file join [file dirname [info script]] ..]]
cd [file join $root td_project cli_build]
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project camera_to_dsi_display.prj -noanalyze
set stage gate
if {[info exists ::env(VOICE_PROBE_STAGE)]} {set stage $::env(VOICE_PROBE_STAGE)}
import_db camera_to_dsi_display_${stage}.db
foreach pattern {{u_voice/u_bus/data_hold_reg*} {u_voice/u_bus/wdata_reg*} {u_voice/u_bus/response_hold_reg*} {u_voice/u_bus/hrdata_reg*} {u_voice/u_bus/req_sync_reg[0]*} {u_voice/u_bus/ack_sync_reg[0]*}} {
    puts "VOICE_COLLECTION $pattern => [get_cells $pattern]"
    puts "VOICE_REGISTERS $pattern => [get_regs $pattern]"
}
clear_sdc -user
read_sdc [file join $root td_project camera_to_dsi_display.sdc]
start_timer
report_timing_summary -file voice_constraint_probe.timing
report_timing_exception -file voice_constraint_probe.exception
exit
