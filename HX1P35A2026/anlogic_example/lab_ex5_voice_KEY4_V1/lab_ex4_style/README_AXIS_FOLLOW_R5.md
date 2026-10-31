# AXIS_FOLLOW_R5：微增上下幅度、接续远处目标

**当前源码增加VOICE_BUTTONS_R1 / VOI8，跟踪参数与目标接续仍沿用本页R5。预存模板、匹配bit/ELF和4键接线见README_VOICE_BUTTONS_R1.md，本页为R5构建历史。**

用户实机反馈R4效果明显改善，希望上下单次修正再大一点；同时提供远处目标偏离中心但云台不动的状态：cfg=3、fresh=0、VISION valid=0、XY=0，pan_steps=-190、servo_us=1754，并确认屏幕标签为RED UNKNOWN或其他形状。该记录表明当时自动模式已启用，但没有有效选中目标，位置也未到当前软件边界。原选择器逐帧严格匹配RED CIRCLE，标签漂移与这次丢失相符。

## 上下幅度

| 垂直偏差绝对值 | R4 | R5 |
|---|---|---|
| >160像素 | 6us | 8us |
| 81～160像素 | 4us | 5us |
| 其他有效调整 | 2us | 3us |

每次仅增加1～2us；保留80ms非零修正间隔、每个新结果最多一次、40/64像素双阈值、启动/反向两帧确认、目标失效时保持及500ms冻结帧超时。短暂目标丢失不能跳过80ms间隔。手动步长和工作范围沿用R4：j/l±32脉冲、i/k±50us、水平±1024脉冲、舵机1000～2000us。

## 目标接续

首次锁定仍严格检查口令指定的颜色和形状：a要求红色圆形，b要求蓝色方形（包括原方形宽高比检查）。UNKNOWN不能直接获取新锁定。

锁定后用上一帧选中目标的位置和尺寸关联同色候选，不再因为每帧形状标签变化立即清掉目标：中心曼哈顿距离不超过128像素，宽和高分别在上一帧的0.5～2倍内；若多个候选满足条件，选距离最近的一个。因此从近处确认后逐渐拉远，目标标签变为UNKNOWN/其他形状时，仍可沿用该次锁定。此时关联可以持续，只要每次新结果继续满足条件；屏幕分类器的标签本身没有被改写成CIRCLE。

没有满足条件的候选时，立即输出valid=0、XY=0，轴保持；只在内部保留至多两个连续失配结果的关联记忆，供短暂缺失后回接。第三个连续失配结果清掉锁定，再出现目标时必须重新严格识别形状。新口令、STOP和检测失败也会清锁。没有使用旧坐标伪装新有效结果。

这不是外观身份识别或遮挡重识别；同色、尺寸相近且靠得很近的多个物体仍可能误关联。真正小到检测器不再输出候选的目标，仍会丢失；本版没有改检测尺寸门槛或提升形状分类器分辨率。快速跳变超过关联门槛时可能先保持，再重新严格获取目标，不能声称任意距离或任意移动速度都能跟住。

## 新状态字段

目标信息寄存器0x2c原未使用的位增加诊断，跨域包仍为80位：bit15=continued，bit14=color_seen，bits13:11=候选数量，bits10:9=检测状态；bit8有效位、低8位操作和高16位口令代次不变。诊断与同次COMMIT的结果帧号一起发布。

串口p增加：`SELECT detect=1 count=1 color=1 continued=1`。

- detect：0等待，1检测结果正常，2失败/溢出；count为原候选数量（最多输出四项，原计数可显示5）。
- color：扫描候选中出现指定颜色；不保证形状或关联条件满足。
- continued：当前选中目标不是严格形状匹配，而是沿用已确认目标的同色位置/尺寸连续性。配合VISION valid=1和FOLLOW fresh=1判断是否在跟踪。

这些UART行分多次读取和打印，不声称组成同一瞬间的原子快照。

## 配套使用

FPGA ID为VOI7（0x564f4937），启动标记VOICE_KEY4_V7 AXIS_FOLLOW_R5；必须同时更新bit和ELF。

1. 旧程序发d、结束FD调试；TD下载 `td_project/cli_build/camera_to_dsi_display.bit`。关闭TD下载连接，再用FD加载 `D:/Anlogic/FDwork/voice_key4_app/build/voice_key4.elf` 并Resume；COM11先打开。
2. 确认R5启动与自检通过，发e启用手动并调整起始姿态。f仍要求先手动启用，避免首次发f直接输出保存的姿态脉宽。
3. 在近处让屏幕显示RED CIRCLE，发a并等到p显示VISION valid=1，再发f。之后沿用此次锁定逐渐拉远，观察SELECT continued与跟踪动作。b蓝色方形使用同样方式。
4. 若远处起初已经只有UNKNOWN，需先回到能确认形状的位置获取锁定；新a会重新严格选择目标。s保持、e手动、d关闭输出，x/y反馈方向规则沿用R4。

R4配套bit/ELF及修改前主要源码、相关测试在 `D:/Anlogic/方案/axis_follow_r4_before_step_target_20261023`。回退时axis_follow_r4.bit与axis_follow_r4.elf配套恢复。

## 验证

- ModelSim五组通过：tb_voice_io、tb_voice_axis、tb_voice_follow、tb_voice_tilt_rate与新增tb_voice_target_lock。覆盖3/5/8us调节、最大8us单步、≥80ms间隔、中心保持，以及严格获取、近处UNKNOWN连续接续、同色多候选时选择关联对象、错误颜色、尺寸/位置跳变、连续缺失后重新严格获取、检测失败、STOP、方形宽高比和诊断字段。
- FD构建通过：text35004、data240、bss10180，总45424字节；原SDK RWX段警告保留。
- TD完整构建通过，耗时11分44秒，`td_project/follow_r5_build_20261023.log`末尾STYLE_TD_BUILD_FINISHED。bit生成于2026-10-23 20:06:43，1789539字节；ELF为171192字节。本轮未下载或操作设备，R5实机摆动幅度和远处目标接续尚待确认。

| 本版最终指标 | 结果 |
|---|---|
| 建立 / 保持 | +0.002ns / +0.020ns，TNS均为0 |
| 检查角 | Slow与Fast均检查Max/Min |
| Slice | 19137/21216，90.20% |
| ERAM / DSP | 97/108、21/40 |
| STA coverage | 95.75%，不声称所有外部接口完整约束 |
| 请求 / 响应 / 命令 / 遥测路径 | 54/34/10/70条受既有有限最大延迟约束，Ignored均为0 |
| ELF加载与栈 | 主LOAD结束0x0800a990，栈起点0x0800b800，中间3696字节 |

新增诊断使遥测中动态路径由63增加为70，仍在原80位握手包内；本轮没有修改SDC。原视频FIFO被原异步时钟分组覆盖的例外仍保留。最终依据为cli_build中的camera_to_dsi_display_phy.ts、camera_to_dsi_display_phy.area、camera_to_dsi_display_pr.timing和camera_to_dsi_display_exception.timing。建立余量很小，当前通过结果只适用于这次生成的bit；后续RTL、引脚、时钟或重新布局布线都需重新核验，不能借用本次报告。
