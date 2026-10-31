# VOICE_KEY4_V1 验证记录

**2026-10-25：当前增加VOICE_BUTTONS_R1 / VOI8。**用户提供R5录入与识别日志，最终模板131/134/84/106、阈值500/20；通过现有OpenOCD连接实际导出31200字节特征，CRC32=0520e68a，校验通过且CPU运行状态已恢复。真实数据已保存到方案/voice_templates_20261025_135448，并生成RAM初始化。七组ModelSim与FD编译通过；新版本下载、按键和预存加载尚待实机核验。详见README_VOICE_BUTTONS_R1.md。

**最新为AXIS_FOLLOW_R5 / VOI7。**用户反馈R4效果改善，要求幅度微增；远处不动时提供cfg=3、fresh=0、valid=0、pan=-190、servo_us=1754，并确认标签为RED UNKNOWN或其他形状，与严格逐帧形状筛选导致无选中目标一致。R5采用3/5/8us步长及已锁定目标的同色位置/尺寸连续关联；首次获取仍严格检查形状。五组ModelSim和FD编译通过；TD与实机状态见README_AXIS_FOLLOW_R5.md。未把仿真结果当作远距离实机稳定性通过。

**最新为AXIS_FOLLOW_R4 / VOI6。**用户反馈R3仍快速下转/晃动，所提供records-2026-10-23-19-10-54.json证实R3启动自检及a/f/d操作，但无p和XY数据。R4减为2/4/6us自动上下修正并加入至少80ms间隔，f需先e手动启用定位，状态增加VISION坐标。四组ModelSim和FD编译通过；TD构建及实机证据边界见README_AXIS_FOLLOW_R4.md。尚未确认居中目标的实际检测坐标，未认定根因或实机稳定性已验证。

**最新为AXIS_FOLLOW_R3 / VOI5。**用户提供R2启动MFCC/Fabric ID自检通过截图、默认轴关闭状态，并确认跟踪静止目标会先接近中心再越过反复摆动。R3针对该反馈新增按视觉结果消费的上下修正、40/64像素保持阈值及两帧方向确认，并消除扫描候选时的瞬时假无效包。ModelSim三组与FD编译通过，TD和实机状态见README_AXIS_FOLLOW_R3.md；未将仿真当作机械闭环稳定性验收。

**最新源码为AXIS_FOLLOW_R2 / VOI4。**针对用户反馈上下跟随速度不足、限位范围过小，将垂直改为4/12/24us每20ms三档，工作脉宽1000～2000us，水平±1024脉冲。三组相关ModelSim与FD编译通过；TD完整构建状态及本版结果见README_AXIS_FOLLOW_R2.md。R2尚未下载或取得机械运动验证，下方R1及更早版本数字为历史证据。

**最新源码为AXIS_FOLLOW_R1 / VOI3。**在用户报告两轴点动正常后，已完成首版自动反馈代码、三组相关ModelSim仿真、FD编译及TD全量构建。最终18960 Slice（89.37%）、97 ERAM、21 DSP，建立+0.021ns/保持+0.020ns；80位目标遥测的63条跨域路径均受有限最大延迟检查。本轮未下载新闭环版或操作其运动，实际跟踪仍待验证。详见README_AXIS_FOLLOW_R1.md。下文语音V1与点动阶段的硬件记录不自动视为新闭环版通过。

## 2026-10-22新增的V1实机证据

以下为用户提供的串口导出和截图，区别于后文2026-10-19构建时尚无硬件结果的历史记录：

- `C:/Users/13329/Downloads/records-2026-10-22-21-14-39.json`包含启动`MFCC_SELFTEST=PASS`、`FABRIC_ID_RAM_PASS; fs=15625`，以及四类模板有效长度114/117/85/129。证明该次程序执行、MFCC黄金向量自检和Fabric ID/首字RAM校验有板上结果，不代表对全部RAM地址做过硬件遍历测试。
- 该导出有5次识别录音，最近模板顺序4/1/2/3/4，最低距离392/469/377/292/341，与次低有效距离差82/28/177/230/203。用户反馈口令方向符合预期；导出未记录实际口述标签，不据此计算准确率。没有非目标语音/电机噪声拒识数据。
- 新版VAD_DIAG_R1将开口等待改为3秒，并独立计语音最长3秒、增加VAD诊断及失败提示；本次四条模板均非零。早期回中274帧模板及NO_SPEECH/TRUNCATED失败不能算成功样本。最近导出最大块处理1532348周期；按配置300MHz换算约5.108ms，相比65.536ms银行期限有余量；处理器时钟没有用仪器测量。
- 用户随后选择临时联调配置`T 500 20`，提供`ACCEPT class=1 bus_ack=1`。同次距离345/445/591/608，最近与次近差100。
- 用户状态回复`STATE=1 XY=10103a5 TRACK=10101 templates=114,117,85,129`。按十六进制寄存器定义，命令代次1、SELECT操作、目标有效位1，坐标x=933/y=257。这证明本次语音命令、FPGA命令确认及视觉候选选择的链路有实机证据，不等同持续跟踪、目标识别准确率或实际两轴闭环通过。
- 用户确认S20F为180°、X42 En菜单H、信号直接接FPGA；COM仍未接/不确定。当前开始AXIS_JOG_R1两轴点动版开发，尚未有新版硬件运动证据。新版本的资源、时序和bit必须单独核验，见README_AXIS_JOG_R1.md；V1 bit/ELF及被修改源码保存在D:/Anlogic/方案/voice_axis_before_20261022。

## 2026-10-19历史记录（以下状态不自动覆盖为新版结论）

日期：2026-10-19。本记录仅描述本轮实际执行的检查，原工程硬件状态不作推断。

## 已完成

- 独立工程建立，未修改 KEY4_DETECT_V1 检测基线。
- FD应用已用安装目录的RISC-V GCC实际编译和链接；最近尺寸为text 33676 B、data 240 B、bss 10180 B，总44096 B。bss统计包含链接脚本预留的2 KiB栈和1 KiB堆，不是实测运行峰值。
- FD Platform使用本工程MCU配置导出的voice_key4.hpf；配置Core 300 MHz、Timer 50 MHz、AHB_DIV=2、PAD JTAG。频率是配置/静态时序结果，未在板上测量。
- `sim/tb_voice_io.log` 出现 `VOICE IO PASS`：I²S独立串行刺激、符号/高16位、AHB地址数据阶段、RAM读写、非法访问两周期ERROR、录音键消抖、2048样本无人消费后的溢出停止与恢复、命令切换清旧目标、等待新分析结果、600像素方形与长矩形区分、停止和无效检测清空。
- `sim/regression.log` 与十二个原视觉bench日志全部PASS。合成图案与协议仿真不代表摄像头实拍识别效果。
- 离线Python通过直接DFT计算MFCC自检黄金向量，固件启动时执行FFT版本对比；板上自检结果未取得。

## 未通过或仍待验证

- FD捆绑GDB指令模拟器兼容性探测未通过。压缩指令报SIGILL，独立RV32IMA测试在函数入口栈访问报SIGSEGV，尚未判定模拟器内部原因；不能据此宣称DSP算法运行通过。测试脚本和日志位于FD Application的tests目录，未编入生产固件。
- 未下载bit、装载ELF、烧写Flash，未操作连接设备。无CPU启动、AHB硬件读写、真实PCM、MFCC板上自检或口令准确率证据。
- 没有真实口令模板；当前需逐类录入，模板易失。阈值默认0，拒绝识别，必须先实际标定。
- 没有云台控制输出。已记录X42S与轮趣S20F；角度版本、零点/限位/接线与赛规许可未落实。HOME仅为请求状态。
- 未实现比赛用非易失模板、断电冷启动，也未完成多人识别。当前开发联调仍使用串口电脑。

## TD 完整构建

最终布线后的静态建立/保持检查已通过，bit已生成。最终日志`td_project/voice_finalize.log`末尾为`VOICE_ROUTED_TIMING_AND_BIT_PASS setup=0.159 hold=0.020`。

| 项目 | 最终结果 |
|---|---|
| Slice | 18735/21216，88.31% |
| ERAM | 97/108，89.81% |
| DSP | 21/40，52.50% |
| MCU | 1/1 |
| PLL | 4/6 |
| 建立 | WNS +0.159 ns，TNS 0 |
| 保持 | WNS +0.020 ns，TNS 0 |
| STA coverage | 95.66%，不声称100%覆盖全部外部接口 |
| bit | `td_project/cli_build/camera_to_dsi_display.bit`，1789539字节，2026-10-19 23:54:25生成 |

证据为`camera_to_dsi_display_phy.area`、`camera_to_dsi_display_phy.ts`、`camera_to_dsi_display_pr.timing`与`camera_to_dsi_display_exception.timing`，均在`td_project/cli_build`内。综合阶段91.33%的Slice占用不是最终资源数。

构建历史日志：`td_project/voice_build_console.log`。历史失败/中止尝试分别保存在attempt1/attempt2/attempt3/attempt4日志中，不作为可交付bit依据。完整综合和布局后，仅修正SDC约束匹配，再从本轮相同RTL的place数据库继续布线；没有借用旧检测版本的综合网表。最后一次仅对本轮已布线pr数据库重新加载最终SDC、进行最终STA并重新生成bit，见`voice_finalize.log`；没有修改RTL、引脚或PLL配置。

TD物理打包会改写SEQ名字，最初按引脚名约束未完整继承。最终Routed exception报告确认：请求54条、响应34条、命令10条、遥测/ACK47条受到有限最大延迟检查，均非Ignored。跨域按持有负载/同步握手设datapath-only上限，并排除不适用的相位保持关系；域内建立/保持仍正常检查。新增其他跨域连接时必须重新审查这些边界。FIFO的两条既有max-delay被旧工程的异步组覆盖，属于原视频IP约束，本轮未将其描述为新音频验证结果。

构建仍有原视频相关的局部时钟布线警告（`u_uicfgcs500/u_i2c/scl_clk`、`pll_clk_24m`局部分支）与SDK的RWX段警告。没有在本轮改造摄像头/I²C时钟结构；板上复测仍需检查视频输出和摄像头配置。阶段性日志中47条遥测保持告警已在最终握手约束和STA中处理，不能把历史告警数当作最终违例数。

最终bit必须与本目录源码、HPF和最新ELF配套，且最终建立/保持检查通过。
