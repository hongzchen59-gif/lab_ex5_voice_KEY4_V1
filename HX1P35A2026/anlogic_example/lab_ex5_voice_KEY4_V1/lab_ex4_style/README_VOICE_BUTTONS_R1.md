# VOICE_BUTTONS_R1：预存四条语音模板与四个外接按键

本版沿用当前AXIS_FOLLOW_R5的跟踪参数和目标接续算法，增加真实语音模板的启动加载以及4个外接按键。FPGA ID为VOI8（0x564f4938），启动标记为VOICE_KEY4_V8 VOICE_BUTTONS_R1 AXIS_FOLLOW_R5，需要配套更新bit和ELF。

## 模板已经保存

用户提供records-2026-10-25-13-54-48.json，最终模板长度131、134、84、106，阈值500、间隔20。日志有各类ACCEPT记录，也有若干NO_SPEECH；没有逐条口述标签及负样本，不能据此计算完整准确率。

通过现有OpenOCD Tcl连接，临时暂停原R5程序，用对齐的32位读取导出四个RAM槽；确认轴关闭、录音未进行、ID/长度与日志匹配，读取后已恢复CPU运行。没有重载程序、修改目标内存或控制电机。

原始备份在 `D:/Anlogic/方案/voice_templates_20261025_135448`：

- templates_ram.bin：31200字节，4个7800字节槽，CRC32=0520e68a。
- templates.json：长度、口令、阈值、维度和每类校验值；4条有效特征都满足当前CMN归一化的数值检查。
- source_voice_key4.elf：与导出现场匹配的R5录入固件；原始串口JSON也已保留。

| 类别 | 口令 | 帧数 |
|---|---|---|
| 1 | 追踪红色圆形 | 131 |
| 2 | 追踪蓝色方形 | 134 |
| 3 | 停止追踪 | 84 |
| 4 | 云台回中 | 106 |

预存数据是用户本人的已录入特征，不是用测试音或虚构数据代替语音。500/20仍为此前联调参数，尚未做多说话人及电机噪声下的全面拒识标定。

## 预存与启动加载

模板放在现有48KiB特征RAM的初始化数据中，不把31.2KiB模板塞入已较满的CPU TCM。源文件为 `user_source/data/voice_templates.mem`，由FD工程中的generate_voice_preset.py读取已验证导出生成；TD按调用readmemh的Verilog源码目录解析`../data/voice_templates.mem`。生成脚本和仿真脚本另有工作目录副本，均来自同一份源数据。

RAM 0x80010000起的前31200字节为4条模板，查询录音仍用第5槽；头部位于0x8001bc00，包含magic、版本、采样率15625、维度13、槽长度7800、四个帧数、阈值、间隔以及数据和头部CRC32。头部CRC为4ebcb7dc。原启动RAM自检已移到0x8001bffc，避免覆盖第一条模板。

启动时先关闭输出，再做MFCC/首字RAM检查与预存数据校验。成功应输出：

```
PRESET_TEMPLATES=PASS frames=131,134,84,106 threshold=500 margin=20
```

此时可直接按识别键或发送r，不再需要1～4录入或T配置。预存模式阻止数字键覆盖固定模板，输出PRESET_LOCKED；更换录音需用保留的录入固件采集、导出，再更新初始化文件。T仍可临时调整识别阈值，重新启动恢复预置值。

模板会随FPGA重新配置恢复；查询录音不修改它，正常CPU重启也会重新读取并校验。当前仍使用原来的bit下载和TCM ELF加载流程，**尚未完成断电后的整机自主启动**；不要把“模板固化”当作Flash启动流程已完成。

## 4个按键接线

根据本板GPIO/J2和Bank32原理图核对，均为3.3V输入，内部上拉。每个独立常开按键的一端接下表GPIO，另一端共接J2-12或J2-30的GND；按下接通到地，松开断开，不需要给按键单独接电源。

| 按键 | 功能 | J2针号 | 网络 | FPGA球位 |
|---|---|---|---|---|
| K1 VOICE | 触发一次语音识别 | 8 | GPIOB7 | F18 |
| K2 MODE | 启用手动/切换跟踪 | 9 | GPIOB8 | G17 |
| K3 STOP | 停止并保持 | 10 | GPIOB9 | H17 |
| K4 DISABLE | 关闭STEP、EN与PWM输出 | 13 | GPIOB10 | H18 |

按J2丝印针号接线。原麦克风J2-1/2/3和两轴J2-4/5/6/7沿用现有接法。这里K1～K4指新增外接键，板载KEY1～KEY4的显示功能保留；原板载KEY1+KEY4识别组合键也保留。

按键采用2级同步和约20ms消抖。按住一次只触发一次；上电时已按住的键须松开再按才产生普通功能事件。STOP/DISABLE的消抖电平会直接作用于FPGA轴控制，持续按住时不能用MODE重新启用输出。

## 使用顺序

1. 当前旧程序发d，结束FD调试。由TD直接下载本版 `td_project/cli_build/camera_to_dsi_display.bit`，关闭TD下载连接，再加载 `D:/Anlogic/FDwork/voice_key4_app/build/voice_key4.elf` 并Resume。COM11先打开，观察VOICE_BUTTONS_R1、MFCC_SELFTEST=PASS和PRESET_TEMPLATES=PASS。
2. 第一次按MODE：启用手动保持，舵机会输出保存的脉宽。确认起始姿态，必要时仍可串口i/k调整。第二次按MODE：进入跟踪待命；再按一次返回手动保持。
3. 按VOICE，等RECORD提示后说四条口令之一。ACCEPT class=1/2后会自动选中相应目标并跟踪，无需再按a/b。首次锁定仍需正确识别颜色/形状；锁定后沿用R5的远处目标接续。
4. 说“停止追踪”会清除当前目标并保持，之后可再次按VOICE说新目标；说“云台回中”仍是回到水平软件零点和1500us，不是已标定的机械绝对中心。
5. 按STOP：在FPGA侧停止追加位移、完成已发出的STEP高电平、保持姿态并退出自动模式。释放后也保持锁止；再次按MODE显式进入跟踪待命，再识别新口令。DISABLE优先级更高，会关闭输出；释放后先MODE手动启用，再MODE进入待命。

录音或分类忙时，VOICE/MODE事件不排队执行；STOP/DISABLE会中止当前识别，丢弃积压输入，并阻止稍晚到达的HOME等指令绕过停止。按键是FPGA功能控制，不声称构成经过认证的独立急停回路。

串口p新增BUTTONS pending/held，bit0～3依次对应VOICE、MODE、STOP、DISABLE；0x58为按下事件（写1清除），0x5c为消抖后的按住状态。AXIS status bit7新增按键停止锁止，显式启用可清除。原UART e/f/d/a/b/s/h/r及原目标字段含义保留。

## 本机验证

七组ModelSim通过：原音频/总线、轴脉冲与PWM、跟踪、修正间隔、目标接续，加上4键事件/消抖/同时清除/硬件停止和预存RAM校验。实际导出数据CRC、头部CRC、查询区与自检区隔离、复位后保持以及错误数据/头部检测都有覆盖。STOP在STEP高电平期间保持完整10us脉冲，DISABLE可立即撤销输出；没有CPU处理按键事件时，STOP/DISABLE也能作用于轴。

FD编译通过：text36324、data240、bss10188，总46752字节；代码/数据/堆LOAD末端0x0800aec0，预留2KiB栈起点0x0800b800，中间2368字节，无重叠。原SDK RWX段警告保留。

TD完整构建通过，耗时11分13秒，日志为td_project/voice_buttons_r1_build_20261025.log，末尾STYLE_TD_BUILD_FINISHED。bit生成于2026-10-25 14:22:54，1789539字节；ELF为177036字节。首次尝试因初始化文件查找路径失败，在读设计阶段停止；修正为源码相对路径后重新全量构建，未复用旧网表。本轮未下载新版本或实测新按键，不能用仿真和原R5跟踪反馈代替本版硬件验收。

新增SDC只将4个异步按键输入到第一同步级设为假路径，第二级与其他本地逻辑继续计时；原邮箱最大延迟约束保留。只读导入本次routed数据库后，get_ports匹配4个新输入，get_cells匹配4个meta_reg[*]_syn_2首级寄存器；探查没有重导出数据库或重新生成bit。探查日志为td_project/button_sync_probe_20261025.log。

| 本版最终指标 | 结果 |
|---|---|
| 建立 / 保持 | +0.122ns / +0.020ns，TNS均为0 |
| 检查角 | Slow与Fast均检查Max/Min |
| Slice | 19427/21216，91.57% |
| ERAM / DSP | 97/108、21/40，模板初始化没有新增ERAM |
| I/O | 73个，较R5增加4个按键输入 |
| STA coverage | 95.78%，不声称所有外部接口完整约束 |
| 请求 / 响应 / 命令 / 遥测路径 | 54/34/10/70条均受有限最大延迟约束，Ignored均为0 |

最终依据为cli_build中的camera_to_dsi_display_phy.ts、camera_to_dsi_display_phy.area、camera_to_dsi_display_pr.timing和camera_to_dsi_display_exception.timing。引脚报告确认F18/G17/H17/H18为LVCMOS33输入上拉。旧视频FIFO被原异步时钟分组覆盖的例外、物理打包后部分旧get_pins不匹配的告警仍保留，未扩大全局假路径。

本轮修改前的R5 bit、ELF和主要源码在 `D:/Anlogic/方案/voice_buttons_before_20261025`。真实模板原始备份独立保存，不依赖板卡继续供电。
