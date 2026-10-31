# FD 工作区入口

**最新为VOICE_BUTTONS_R1（VOICE_KEY4_V8、VOI8），跟踪沿用AXIS_FOLLOW_R5。**真实口令模板131/134/84/106已导出并放入FPGA RAM初始化，启动会检查CRC并自动加载500/20；新增4键识别、启用/跟踪、停止、关闭。需要配套新bit与ELF。接线及操作见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_VOICE_BUTTONS_R1.md`。下文为历史记录。

**最新为AXIS_FOLLOW_R5（VOICE_KEY4_V7、VOI7），需配套R5 bit。**上下步长由2/4/6微增到3/5/8us，保留80ms等待；首次严格识别颜色/形状后按同色位置/尺寸连续性接续，状态增加SELECT诊断。操作与验证见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_FOLLOW_R5.md`。下文为历史记录。

**最新为AXIS_FOLLOW_R4（VOICE_KEY4_V6、VOI6），须配套R4 bit。**上下自动步长2/4/6us，非零修正至少间隔80ms；先e启用并定位，再f进入跟踪，失能状态直接f不会启用输出。状态新增VISION十进制坐标。操作与验证边界见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_FOLLOW_R4.md`。下方是历史版本记录。

**最新为AXIS_FOLLOW_R3（VOICE_KEY4_V5、VOI5），需配套R3 bit。**上下修正改为每个新视觉结果最多一次、中心40/64像素双阈值、启动/反向两帧确认；保持R2工作限位与串口命令。操作和验证状态见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_FOLLOW_R3.md`。下文为历史记录。

**当前版本为AXIS_FOLLOW_R2（VOICE_KEY4_V4、VOI4），须配套R2 bit。**上下采用4/12/24us三档20ms调节，脉宽工作范围1000～2000us、水平±1024脉冲；原串口命令不变。操作和验证状态见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_FOLLOW_R2.md`。下文为历史版本记录。

**当前源码/ELF进入AXIS_FOLLOW_R1（VOICE_KEY4_V3、VOI3），必须与新闭环bit配套；不能继续加载VOI2点动bit。**最新操作见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_FOLLOW_R1.md`。默认输出关闭，e手动、f跟踪、d失能，a/b可先用串口选目标而无需重录模板。此前验证正常的点动bit和R3固件在 `D:/Anlogic/方案/axis_jog_r3_before_follow_20261022`。下方R3/R2/R1为历史修订记录，不代表当前ELF的配套版本。

**最新FD软件修订AXIS_JOG_R3：j/l改为-32/+32脉冲，i/k保留+50/-50us；l仍为俯视顺时针，i向上、k向下。继续配套AXIS_JOG_R1/VOI2 FPGA bit，只更新ELF。水平累计范围仍为软件零点两侧各128脉冲；达到限制后继续同向点动会被限幅。脉冲频率未增加，每次32脉冲约需0.32秒，实际转角取决于细分和传动比。**下方R2/R1说明为修订历史，以本段为准。

**最新FD软件修订AXIS_JOG_R2：i/k步长改为+50/-50us，实机反馈i向上、k向下；j/l仍为-8/+8脉冲，l为俯视顺时针。继续使用已通过构建的AXIS_JOG_R1/VOI2 FPGA bit，无需重下载bit或修改TD工程。**仅停止并重新启动FD调试加载新版ELF，启动标记为AXIS_JOG_R2；重新启动会失能轴并清空易失语音模板。

**当前源码/ELF已更新为AXIS_JOG_R1，须配套新的VOI2 FPGA bit，不能与旧语音bit混用。**点动指令和接线见 `D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/README_AXIS_JOG_R1.md`。旧语音/视觉bit、ELF和源码备份在 `D:/Anlogic/方案/voice_axis_before_20261022`。本版新增默认失能的STEP/DIR/高有效EN及舵机PWM，仅做手动点动，未接自动视觉闭环。以下早期章节保留历史定位记录，以最新匹配ID、启动标记和新说明为准。

当前是PH1P35语音通路/录入式模板验证固件。用户已在板上验证UART状态回复、录音和特征提取，并提供红色圆形、蓝色方形及停止口令的目标模板分数最低记录；仍使用全拒识配置，尚未完成准确率、拒识阈值和云台联调验证。

在FD工作区 `D:/Anlogic/FDwork` 中使用 File -> Import -> General -> Existing Projects into Workspace，选择该目录并搜索嵌套项目，导入 voice_key4_platform 和 voice_key4_app；不要勾选 Copy projects into workspace。项目文件已生成，本轮未操作FD界面验证导入。

右键 voice_key4_app -> Build Project，或直接运行 build.ps1。产物为 build/voice_key4.elf。Platform文件在 voice_key4_platform/voice_key4_platform 中，使用实际新工程导出的 voice_key4.hpf。

2026-10-22修正Windows PowerShell 5.1兼容性：链接器的RWX警告曾因标准错误重定向被提升为NativeCommandError，导致FD构建退出1。build.ps1现由cmd将make输出直接重定向到build.log，仍检查make真实退出码，不屏蔽链接警告。已使用FD配置的WindowsPowerShell/v1.0/powershell.exe实际重新链接验证，退出码0，末尾输出VOICE_FIRMWARE_BUILD_PASS。该标记表示固件构建通过，不代表已装载或板上运行通过。

构建不会下载或烧写。不要运行Platform目录中的旧示例bit；该文件已从新BSP删除。匹配bit位于新的 lab_ex5_voice_KEY4_V1 工程。

调试时使用PH1P35 OpenOCD配置并扫描真实JTAG设备；先由TD加载匹配bit，再装载此ELF，设置执行入口为ELF的_start并停在main。此固件按官方TCM链接脚本生成，调试加载地址为0x08000000；不是Flash冷启动映像。不要将ELF的加载成功当作断电后自启动完成，也不要加载后按硬件复位以为仍会从TCM入口启动。

完整接线、寄存器、语音录入与拒识说明见新TD工程的README_VOICE_V1.md。当前X42S/S20F未驱动，HOME仅为状态请求。

## FD调试配置准备（2026-10-22）

GDB OpenOCD Debugging的OpenOCD路径使用`D:/Anlogic/FD/toolchain/openocd/fpsoc/bin/openocd.exe`，Config options使用`-f "D:/Anlogic/FDwork/voice_key4_app/voice_key4_openocd.cfg"`。GDB路径使用`D:/Anlogic/FD/toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-gdb.exe`。

该专用cfg依据FD官方ph1p35.cfg的FTDI和两TAP定义，仅配置TCM调试连接，不包含Flash bank/protect/erase/program命令。已通过OpenOCD noinit语法检查（VOICE_CONFIG_PARSE_PASS），该检查未初始化下载器或访问开发板，不代表硬件连接通过。系统当前枚举到了0403:6042 USB-JTAG设备。共享PAD/PL JTAG链仍须实机扫描确认。Startup页的halt/load/入口配置需继续核对，不能仅凭cfg语法通过就判断可启动。

## 首次启动报错的定位与修复（2026-10-22）

用户提供的OpenOCD日志已显示`Examined RISC-V core; found 1 harts`、`XLEN=32`、`Target successfully examined`及GDB连接，证明本次实际JTAG连接已到达RISC-V核；不代表ELF已装载或main已执行。

FD工作区.metadata/.log的最终启动异常发生在stepGnuMcuStart：EclipseUtils.getProjectByLaunchConfiguration因缺少CDT构建配置返回null，随后FD的ProjectUtils.isAArch32访问该空对象。已补充应用工程的.cproject，使用CDT内置defaultConfigDataProvider和Debug配置，保留现有外部Make/PowerShell构建方式。XML结构检查和原构建脚本验证通过；FD须刷新并关闭/重新打开该应用工程后重试Debug，IDE调试成功仍待新日志确认。

Startup设置：Initial Reset及Pre-run/Restart reset关闭；Initialization Commands为`monitor halt`；Load symbols与Load executable开启，均使用项目ELF，offset留空；Load binary及Arm semihosting关闭；Run/Restart Commands为`set $pc = _start`，main断点与Continue开启。函数地址随构建变化，使用ELF符号，不填写旧main地址。先打开115200 8N1串口，再启动调试、停在main并Resume观察启动自检。

## 录音起止诊断更新（2026-10-22，VAD_DIAG_R1）

用户实测出现NO_SPEECH、TRUNCATED及回中模板274帧被部分短录音的时长限制排除。最近重录失败后状态为templates=186,173,82,0；原程序失败时仍打印ENROLLED，这是提示错误，不能视为成功。

此次只更新FD软件：开口等待由1秒延长到3秒；检测到语音后单独计最多3秒（包含结束静音），不再由等待时间占用口令时长；总墙钟保护由4秒改为8秒。语音起点连续3帧超门限、结束30帧静音、MFCC、DTW、拒识配置及Fabric接口保持原逻辑。失败打印ENROLL_FAILED，不再打印成功提示。每次录音停止后输出VAD诊断，energy为每160样本平均绝对幅度，gate为最后一个完整音频帧使用的门限，voiced_run_max为起点阶段连续超门限的最大帧数；peak单独出现非零不能证明正常语音已被检测到。诊断在停止采集后输出，避免占用音频块处理期限。

构建成功不代表新版硬件验证通过。无需重建/重下载FPGA bit；保持板卡供电，终止旧FD调试后重新Debug加载build/voice_key4.elf并Resume。新启动行应含VAD_DIAG_R1。重新启动程序会清空全部易失模板和阈值；先发送4验证回中录入，并保留完整VAD/FEATURES/ENROLLED或失败日志，再录其余模板与恢复分数采集配置。此更新不保证解决噪声导致的起止判断，需用新增诊断继续定位。
