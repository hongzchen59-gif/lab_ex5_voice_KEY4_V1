$ErrorActionPreference='Stop'
$app=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PATH='D:\Anlogic\FD\toolchain\build-tools\bin;'+$env:PATH
Push-Location $app
try {
    & 'C:\Users\13329\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B .\generate_voice_tables.py
    if($LASTEXITCODE -ne 0){throw 'Table generation failed'}
    # Let cmd redirect native stderr directly to the log. Windows PowerShell 5.1
    # otherwise turns linker warnings into terminating NativeCommandError under
    # ErrorActionPreference=Stop. The make exit code still decides success.
    $makeCommand='""D:\Anlogic\FD\toolchain\build-tools\bin\make.exe" "SDK_ROOT=D:/Anlogic/FDwork/voice_key4_platform/voice_key4_platform" "COMPILE_PREFIX=D:/Anlogic/FD/toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-" "DOWNLOAD=tcm" "TARGET=voice_key4" -j4 > build.log 2>&1"'
    & $env:ComSpec /d /s /c $makeCommand
    $makeExitCode=$LASTEXITCODE
    if($makeExitCode -ne 0){Get-Content build.log -Tail 30;throw "Firmware build failed (make exit $makeExitCode)"}
    Get-Content build.log -Tail 6
    Write-Output 'VOICE_FIRMWARE_BUILD_PASS'
} finally { Pop-Location }
