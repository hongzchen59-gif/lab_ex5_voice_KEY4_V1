$ErrorActionPreference='Stop'
$app=Split-Path $PSScriptRoot -Parent
$prefix='D:/Anlogic/FD/toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-'
$elf=Join-Path $PSScriptRoot 'dsp_test.elf'
& ($prefix+'gcc.exe') -march=rv32ima -mabi=ilp32 -Os -g -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -nostartfiles -nostdlib '-Wl,--no-relax,--gc-sections' -T (Join-Path $PSScriptRoot 'dsp_test.ld') (Join-Path $PSScriptRoot 'dsp_start.S') (Join-Path $PSScriptRoot 'dsp_test.c') (Join-Path $app 'voice_dsp.c') -o $elf
if($LASTEXITCODE -ne 0){throw 'DSP test compile failed'}
$gdb=@"
target sim --model=RV32IMA --architecture=riscv:rv32
sim memory-region 0x08000000,0x20000
sim memory-region 0x80010000,0xc000
load
break test_done
sim watch-clock-int 20000
run
print/x test_result
print test_checks
if test_result != 0x50415353
  quit 1
end
echo DTW CMN SIM PASS\n
quit
"@
$command=Join-Path $PSScriptRoot 'dsp_test.gdb'
[IO.File]::WriteAllText($command,$gdb)
$output=& ($prefix+'gdb.exe') -batch -nx $elf -x $command 2>&1
$exitCode=$LASTEXITCODE
$output | Tee-Object -FilePath (Join-Path $PSScriptRoot 'dsp_sim.log')
if($exitCode -ne 0 -or ($output -join "`n") -notmatch 'DTW CMN SIM PASS'){throw 'DSP simulator failed'}
