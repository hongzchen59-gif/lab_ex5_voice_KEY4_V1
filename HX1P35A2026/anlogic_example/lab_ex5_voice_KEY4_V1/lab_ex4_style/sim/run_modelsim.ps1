param(
    [string]$ModelSimDir = 'D:\FPGA\Modelsim\modelsim_ase\win32aloem',
    [string[]]$Benches = @('tb_color_fill','tb_thin_contour','tb_vivid_status','tb_video_timebase','tb_video_latency','tb_latency_overlay','tb_latency_pipeline','tb_latency_startup','tb_motion_cdc','tb_motion','tb_video_tag','tb_motion_overlay','tb_motion_720p','tb_isp_ddr_frame','tb_awb_stability','tb_preserve_norm','tb_dark_control','tb_camera_config','tb_video_style','tb_key_mode','tb_video_out_align','tb_video_720p','tb_detect_mask','tb_detect_components','tb_detect_deadline','tb_detect_overlay','tb_detect_720p')
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $rtl = Join-Path $PSScriptRoot '..\user_source\hdl_source'
    $pythonExe = 'C:\Users\13329\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    & $pythonExe (Join-Path $PSScriptRoot 'generate_vectors.py')
    if ($LASTEXITCODE) { throw 'Reference generation failed' }
    & $pythonExe (Join-Path $PSScriptRoot 'generate_motion_vectors.py')
    if ($LASTEXITCODE) { throw 'Motion reference generation failed' }
    & $pythonExe (Join-Path $PSScriptRoot 'check_visual_properties.py')
    if ($LASTEXITCODE) { throw 'Synthetic image behavior checks failed' }
    & $pythonExe (Join-Path $PSScriptRoot 'detect_reference.py')
    if ($LASTEXITCODE) { throw 'Detection reference generation failed' }
    if (-not (Test-Path -LiteralPath 'work')) { & "$ModelSimDir\vlib.exe" work }
    $sources = @('key_mode_ctrl.v','video_pixel_align.v','rgb_window_3x3.v','edge_preserve.v','video_style_core.v','video_style.v','detect_color_mask.v','detect_components.v','detect_overlay.v','video_detect.v') | ForEach-Object { Join-Path $rtl $_ }
    $sources += @('video_latency.v','latency_overlay.v','video_motion.v','motion_overlay.v','awb.v','base_gamma.v','frame_meter.v','meter_cdc.v','camera_auto_exposure.v') | ForEach-Object { Join-Path $rtl $_ }
    $sources += @('uicfgcs500_720p.v','uics500reg_720p30.v','uics500regAE.v','uii2c.v','SC500GainTbl.v') | ForEach-Object { Join-Path (Join-Path $rtl 'uics500_cfg') $_ }
    $sources += @('video_in.v','data_96bit_to_128bit.v','video_out.v','hdmi_mixer.v','osd_char_lib.v','anlogic_logo_rom.v') | ForEach-Object { Join-Path $rtl $_ }
    $sources += Join-Path $rtl 'vtc\uivtc.v'
    $fifo = Join-Path $PSScriptRoot '..\user_source\ip_source\w128_d512_fifo'
    $sources += @((Join-Path $fifo 'w128_d512_fifo.v'), (Join-Path $fifo 'soft_fifo_al_4057d6b76aa6.v'))
    & "$ModelSimDir\vlog.exe" -sv -work work @sources tb_color_fill.sv tb_thin_contour.sv tb_vivid_status.sv tb_video_timebase.sv tb_video_latency.sv tb_latency_overlay.sv tb_latency_pipeline.sv tb_latency_startup.sv tb_motion_cdc.sv tb_motion.sv tb_video_tag.sv tb_motion_overlay.sv tb_motion_720p.sv tb_isp_ddr_frame.sv tb_awb_stability.sv tb_video_style.sv tb_key_mode.sv tb_video_out_align.sv tb_video_720p.sv tb_dark_control.sv tb_camera_config.sv tb_preserve_norm.sv tb_detect_mask.sv tb_detect_components.sv tb_detect_deadline.sv tb_detect_overlay.sv tb_detect_720p.sv
    if ($LASTEXITCODE) { throw 'RTL compilation failed' }
    foreach ($bench in $Benches) {
        & "$ModelSimDir\vsim.exe" -c -novopt -l "$bench.log" "work.$bench" -do 'run -all; quit -code 0'
        if ($LASTEXITCODE) { throw "$bench simulation failed" }
        if (-not (Select-String -LiteralPath "$bench.log" -Pattern ' PASS:' -Quiet)) { throw "$bench did not report PASS" }
    }
} finally { Pop-Location }
