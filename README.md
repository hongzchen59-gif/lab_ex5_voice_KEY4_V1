# 语音视觉云台工程（TOON R4）

基于安路 PH1P35MDG324 的摄像头图像处理、语音控制和云台目标跟踪工程。
本仓库收录当前 FPGA 工程、配套 FD 软件/BSP，以及 TOON R4 发布文件和已有验证记录。

## 工程入口

| 内容 | 位置 |
| --- | --- |
| TD 工程 | [camera_to_dsi_display.al](HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/td_project/camera_to_dsi_display.al) |
| FPGA RTL、IP、引脚和时序约束 | [user_source](HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/user_source) |
| FPGA 构建脚本 | [build_td.tcl](HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/scripts/build_td.tcl) |
| 仿真与参考模型 | [sim](HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/sim) |
| FD 应用源码与构建说明 | [voice_key4_app](FDwork/voice_key4_app/README_FD.md) |
| FD 配套 BSP | [voice_key4_platform](FDwork/voice_key4_platform/voice_key4_platform) |
| TOON R4 发布目录 | [voice_key4_toon_r4](FDwork/voice_key4_toon_r4) |
| 接线说明 | [接线说明_语音视觉云台.md](HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style/接线说明_语音视觉云台.md) |

## 使用已有烧录镜像

使用 [voice_toon_r4_flash.bin](FDwork/voice_key4_toon_r4/voice_toon_r4_flash.bin)。
原发布说明要求 BitWriter 选择 PROGRAM_FLASH、128 Mbits、1 MHz、地址 0，添加这一份完整组合 BIN。
烧录后断电重启，KEY3 应显示 `TOON R4`。
具体步骤和验收范围见 [烧录与KEY3验收说明](FDwork/voice_key4_toon_r4/烧录与KEY3验收说明.md)。

## 开发环境与路径

- FPGA：TD 6.2.1；配套 FD 工具和 PH1P35 RISC-V 工具链。
- 仿真：ModelSim；部分参考模型使用 Python。
- 仓库保留原 `D:/Anlogic` 下的目录层次。部分 TD/FD 配置、Makefile、PowerShell/Python 脚本仍引用原开发机的绝对路径。
- 在原开发目录布局中使用，或在新机器上调整 TD、FD、Python、ModelSim 和 BSP 路径后再构建。
- FD 应用入口为 `FDwork/voice_key4_app`，BSP 为 `FDwork/voice_key4_platform/voice_key4_platform`；TD 工程入口见上表。
- `FDwork/voice_key4_app/build/voice_key4.elf` 为当前配套应用；TOON R4 目录保留发布时的 ELF、启动程序与完整镜像。

## 验证记录

[manifest.json](FDwork/voice_key4_toon_r4/manifest.json) 和 [validation](FDwork/voice_key4_toon_r4/validation) 保留原发布构建、时序和仿真结果。
原发布记录包含 2026-10-26 的 R4 实机通过反馈，具体适用范围以原记录为准。
本次上传仅整理工程副本，未重新运行 FPGA 综合、仿真或硬件烧录。

## 仓库内容

保留用于构建和检查工程的源文件、IP、约束、测试数据和发布产物。
软件安装目录、工具许可证、IDE 工作区缓存和临时综合/仿真数据库不在仓库内。
历史 README 和验证文件按原样保留，其中涉及的旧版本路径不表示仓库包含全部历史镜像。
第三方 IP 与 BSP 文件保留原有版权和授权声明，本仓库未额外授予其使用或再分发许可。
