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