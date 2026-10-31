$ErrorActionPreference='Stop'
$simDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=Split-Path -Parent $simDir
$modelSim='D:\FPGA\Modelsim\modelsim_ase\win32aloem'
Push-Location $simDir
try {
    Copy-Item -LiteralPath "$root\user_source\data\voice_templates.mem" -Destination "$simDir\voice_templates.mem"
    if(!(Test-Path 'voice_work')) { & "$modelSim\vlib.exe" voice_work }
    & "$modelSim\vlog.exe" -sv -work voice_work "$root\user_source\hdl_source\voice_i2s_rx.v" "$root\user_source\hdl_source\voice_ahb_bridge.v" "$root\user_source\hdl_source\voice_axis_follow.v" "$root\user_source\hdl_source\voice_axis_control.v" "$root\user_source\hdl_source\voice_button_inputs.v" "$root\user_source\hdl_source\voice_peripheral.v" "$root\user_source\hdl_source\voice_target_select.v" tb_voice_io.sv tb_voice_axis.sv tb_voice_follow.sv tb_voice_tilt_rate.sv tb_voice_target_lock.sv tb_voice_buttons.sv tb_voice_preset.sv *> voice_compile.log
    if($LASTEXITCODE -ne 0) { throw 'Voice compilation failed: voice_compile.log' }
    & "$modelSim\vsim.exe" -c -novopt -l tb_voice_io.log voice_work.tb_voice_io -do 'run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath tb_voice_io.log -SimpleMatch 'VOICE IO PASS')) { throw 'Voice simulation failed: tb_voice_io.log' }
    & "$modelSim\vsim.exe" -c -novopt -l tb_voice_axis.log voice_work.tb_voice_axis -do 'run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath tb_voice_axis.log -SimpleMatch 'VOICE AXIS PASS')) { throw 'Axis simulation failed: tb_voice_axis.log' }
    & "$modelSim\vsim.exe" -c -novopt -l tb_voice_follow.log voice_work.tb_voice_follow -do 'run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath tb_voice_follow.log -SimpleMatch 'VOICE FOLLOW PASS')) { throw 'Follow simulation failed: tb_voice_follow.log' }
    & "$modelSim\vsim.exe" -c -novopt -l tb_voice_tilt_rate.log voice_work.tb_voice_tilt_rate -do 'run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath tb_voice_tilt_rate.log -SimpleMatch 'VOICE TILT RATE PASS')) { throw 'Tilt rate simulation failed: tb_voice_tilt_rate.log' }
    & "$modelSim\vsim.exe" -c -novopt -l tb_voice_target_lock.log voice_work.tb_voice_target_lock -do 'run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath tb_voice_target_lock.log -SimpleMatch 'VOICE TARGET LOCK PASS')) { throw 'Target lock simulation failed: tb_voice_target_lock.log' }
    foreach($bench in @('tb_voice_buttons','tb_voice_preset')) {
        & "$modelSim\vsim.exe" -c -novopt -l "$bench.log" "voice_work.$bench" -do 'run -all; quit -code 0'
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "$bench.log" -SimpleMatch 'VOICE EXTRA PASS')) { throw "Voice extra simulation failed: $bench.log" }
    }
} finally { Pop-Location }
