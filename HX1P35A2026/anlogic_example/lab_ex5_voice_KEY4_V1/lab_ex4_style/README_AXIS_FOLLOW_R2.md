# AXIS_FOLLOW_R2：加快上下跟踪、扩大工作范围

**当前源码已更新为AXIS_FOLLOW_R3 / VOI5，抑制上下反复摆动的改动与配套下载见README_AXIS_FOLLOW_R3.md。本页保留R2历史参数和构建记录；用户随后反馈R2接近中心后上下反复越过，因此不能将R2构建通过当作闭环稳定性通过。**

用户实机反馈R1上下跟踪速度不足，目标会移出视野，初期限位也限制运动范围。本版只调整上下反馈速度及两轴工作范围；保留既有接线、方向、50Hz PWM、水平脉冲速度、目标选择和丢失处理。

## 参数变化

| 参数 | R1 | R2 |
|---|---|---|
| 水平相对软件零点限位 | ±128脉冲 | ±1024脉冲 |
| 垂直脉宽限位 | 1300～1700us | 1000～2000us |
| 垂直误差绝对值≤24像素 | 保持 | 保持 |
| 垂直误差25～80像素 | 2us/20ms | 4us/20ms |
| 垂直误差81～160像素 | 4us/20ms | 12us/20ms |
| 垂直误差>160像素 | 4us/20ms | 24us/20ms |

远离中心时最大脉宽指令变化速度从200us/s提高到1200us/s，接近中心后减速。这是指令变化速度，不代表实机转速提高6倍或保证不再丢失目标。实际运动受负载、舵机速度及视觉更新延迟影响，需看板上效果；本版没有引入PID或目标预测。

用户说明不上电时机构可以转360度；S20F仍按已确认的180度型号使用，不将手动可转角度当作通电有效行程。1000～2000us是本版扩大后的工作区间，尚未做该安装机构的脉宽到角度标定，也不声称覆盖全部180度。水平细分与传动比未提供，因此用脉冲数表示限位，不声称±1024对应具体角度。限位仍有效，不通过反复z清零绕过限位。

水平STEP仍约100脉冲/秒、10us高电平、至少20us方向建立时间；j/l仍为每次±32脉冲，i/k仍为±50us。l为俯视顺时针，i向上，k向下；x/y仍只翻转反馈符号并退出自动模式。

目标明确无效时撤销待执行位移并保持；没有新结果帧500ms后停止跟随；不通过延长旧坐标有效期来掩盖丢失。失去目标后将目标重新放入视野，选择同类目标的后续有效结果可以恢复跟随。s保持，e手动，d关闭输出。d仍通过CPU串口主循环处理，录音/分类期间不是独立硬件急停。

## 配套下载与使用

FPGA ID为VOI4（0x564f4934），启动标记为VOICE_KEY4_V4 AXIS_FOLLOW_R2。新版ELF检查ID，防止误用旧bit。必须同时更新bit与ELF。

1. 旧程序发d，停止FD调试。TD下载 `td_project/cli_build/camera_to_dsi_display.bit`，结束TD下载连接后再启动FD调试。
2. FD使用 `D:/Anlogic/FDwork/voice_key4_app/build/voice_key4.elf`；COM11先打开，加载后Resume。确认AXIS_FOLLOW_R2、MFCC_SELFTEST=PASS和FABRIC_ID_RAM_PASS。
3. a选择红色圆形或b选择蓝色方形，目标放入画面；f开启跟踪。p查看servo_us/active_us、pan_steps/target及FOLLOW新鲜度。模板仍易失，a/b不要求重录语音。
4. 用正常移动速度观察上下是否能跟上、回到中心附近是否摆动。如需停止，s保持或e返回手动；d关闭输出。

当前TD `.al` 清单包含voice_axis_control.v和voice_axis_follow.v。若GUI一直打开旧工程，应重新加载当前工程后再保存或构建；本轮发现缺少上述清单项的首次构建已经失败，补回后重新全量构建，没有复用旧综合网表。

R1 bit、ELF及被修改的核心源码保存在 `D:/Anlogic/方案/axis_follow_r1_before_speed_range_20261022`。若需回到R1，必须恢复其中配套的axis_follow_r1.bit与axis_follow_r1.elf。

## 验证记录

- ModelSim：tb_voice_io、tb_voice_axis、tb_voice_follow通过。新增了生产默认±1024脉冲及1000/2000us的AHB限幅检查、实际PWM两端脉宽检查、上下三档调节量及死区边界检查；保留STOP/HOME、目标代次、失效/冻结帧、反向、输出失能等回归。
- FD构建通过：text34720、data240、bss10180，合计45140字节；原SDK链接RWX段警告仍在。
- TD从源码完整构建通过，耗时11分1秒；日志 `td_project/follow_r2_build_20261022.log` 末尾为STYLE_TD_BUILD_FINISHED。bit生成于2026-10-23 00:02:32，1789539字节。未下载设备，R2机械运动效果尚未验证。

| 最终R2构建指标 | 结果 |
|---|---|
| 建立 / 保持 | +0.132ns / +0.020ns；TNS均为0 |
| 检查角 | Slow与Fast均检查Max/Min |
| Slice | 19134/21216，90.19% |
| ERAM / DSP | 97/108、21/40 |
| STA coverage | 95.74%，不代表所有外部接口都已完整约束 |
| 请求 / 响应 / 命令 / 遥测跨域路径 | 54/34/10/63条均受既有有限最大延迟约束，Ignored均为0 |

本轮未修改SDC。旧视频FIFO例外被原异步时钟分组覆盖的情况仍在。资源与时序取自本版 `camera_to_dsi_display_phy.area`、`camera_to_dsi_display_phy.ts`、`camera_to_dsi_display_pr.timing` 和 `camera_to_dsi_display_exception.timing`；R1报告不用于本版验收。

其余接线、命令与寄存器布局见README_AXIS_FOLLOW_R1.md；R1的速度、限位、ID及资源/时序数据不用于R2。
