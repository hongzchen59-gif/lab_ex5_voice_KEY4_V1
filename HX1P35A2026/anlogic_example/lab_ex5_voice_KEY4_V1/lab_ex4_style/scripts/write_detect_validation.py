"""Summarize actual ModelSim/TD evidence after a successful build."""
from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
sim=root/'sim';build=root/'td_project/cli_build'
benches=('tb_preserve_norm','tb_dark_control','tb_camera_config','tb_video_style','tb_key_mode','tb_video_out_align','tb_video_720p','tb_detect_mask','tb_detect_components','tb_detect_deadline','tb_detect_overlay','tb_detect_720p')
passes={}
for b in benches:
    txt=(sim/(b+'.log')).read_text(errors='replace')
    lines=[line.lstrip('# ') for line in txt.splitlines() if ' PASS:' in line]
    assert lines and not re.search(r'\*\* (Fatal|Error):',txt),b
    passes[b]=lines[-1]
log=(build/'build.log').read_text(errors='replace')
assert 'STYLE_TD_BUILD_FINISHED' in log,'TD has not finished with passing timing'
timing=(build/'camera_to_dsi_display_phy.ts').read_text(errors='replace')
area=(build/'camera_to_dsi_display_phy.area').read_text(errors='replace')
setup=float(re.search(r'SWNS:\s+(-?[\d.]+)ns',timing)[1]);hold=float(re.search(r'HWNS:\s+(-?[\d.]+)ns',timing)[1])
assert setup>=0 and hold>=0
summary=(build/'camera_to_dsi_display_pr.timing').read_text(errors='replace')
coverage=re.search(r'STA coverage\s*:\s*([\d.]+)%',summary)
resources={}
for key in ('slice','eram','dsp'):
    m=re.search(r'^#'+key+r'\s+(\d+)\s+out of\s+(\d+)',area,re.M)
    resources[key]=dict(used=int(m[1]),total=int(m[2]))
bit=build/'camera_to_dsi_display.bit';assert bit.is_file() and bit.stat().st_size>0
assert bit.stat().st_mtime>=max(p.stat().st_mtime for p in (root/'user_source').rglob('*.v')),'RTL changed after bit generation'
data=dict(modelsim='D:/FPGA/Modelsim/modelsim_ase/win32aloem',tests=passes,setup_ns=setup,hold_ns=hold,sta_coverage_percent=float(coverage[1]) if coverage else None,resources=resources,bit=str(bit),bit_bytes=bit.stat().st_size)
(sim/'validation_summary.json').write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
(build/'final_timing.rpt').write_text(summary,encoding='utf-8')
max_cycles=int(re.search(r'max_cycles=(\d+)',passes['tb_detect_components'])[1])
rows='\n'.join(f'| {b} | {passes[b]} |' for b in benches)
res='\n'.join(f'- {key}: {d["used"]}/{d["total"]} ({100*d["used"]/d["total"]:.2f}%)' for key,d in resources.items())
delta={k:resources[k]['used']-v for k,v in dict(slice=16942,eram=53,dsp=15).items()}
budget_note=f'相对 V2.1 增加 Slice {delta["slice"]}、ERAM {delta["eram"]}、DSP {delta["dsp"]}。'
if delta['dsp']>4:budget_note+='实际 DSP 增量高于方案中 0～4 个的初始估算；优化后的总资源与最终时序满足当前器件限制。'
text=f'''# KEY4 目标检测 V1 验证记录

日期：2026-10-17。基准工程 V2.1 保留；本工程独立生成 bit。

## 仿真结果

使用 `{data['modelsim']}` 的 ModelSim 10.1d ALTERA Starter。十二组日志均含 PASS，未出现 Fatal/Error；不只依据工具退出码判定。

| 测试 | 实际通过记录 |
| --- | --- |
{rows}

检测参考使用独立 BFS 连通区域算法，与 RTL 的 RLE/等价标签实现不同。36 组检测场景含三色与圆/三角/矩形/倒三角组合、同色分离、八连通对角、异色接触、晚合并、多分支、随机区域、面积/触边筛选、4+数量及游程/标签容量边界。最长有效测试耗时为 {max_cycles} 拍，名义 75MHz 下约 {max_cycles/75000:.2f}ms；这是测试场景的最大值，不是所有可能输入的最坏时间证明。硬件在 1000000 拍截止时中止并清除结果。

完整 720p 检测仿真覆盖真实行帧长度、投票双缓冲、区域分析、圆/三角识别、按帧锁存、框线叠加、空画面清框和 KEY1 隐藏叠加；核对 2355200 个显示像素。它是合成图像测试，不是摄像头实拍准确率测试。

七组基础回归覆盖原有归一化、Gamma、AE/CDC、相机寄存器、按键、FIFO 对齐及 Logo；KEY4 参考更新为基础 Gamma 后中心像素透传，KEY1/2/3 行为保持。可选跨帧类别确认本版未启用。

## 综合、布局布线与 bit

TD 6.2.168116 从本工程源码完成构建，日志含 `STYLE_TD_BUILD_FINISHED`。最终布线后：

- SWNS: **{setup:+.3f}ns**；HWNS: **{hold:+.3f}ns**。
- STA 覆盖率：{data['sta_coverage_percent']}%，按当前 SDC 的 Slow/Fast 建立/保持检查；不是全设计 100% 无约束检查。
{res}
- bit 大小：{bit.stat().st_size} 字节。

{budget_note}

bit：`{bit}`。

保留既有 MIPI/DDR/显示跨域约束，检测逻辑使用同一 HDMI 像素时钟；未新增用来规避检测时序的 false path。

## 上板验收

尚未完成本版本的用户上板观感及实际识别率验收。下载后按 KEY4，使用浅色背景、近正面、互不接触的实心红/绿/蓝图形卡片。先做颜色与形状互换，再检查同色双目标、移入移出及四键切换；实际光照下的颜色阈值仍以用户反馈标定。

## 证据

- `sim/*.log`：逐组仿真日志。
- `sim/detect_reference.json`：独立区域参考与目标字段。
- `sim/validation_summary.json`：本记录的结构化数据。
- `td_project/cli_build/build.log`：本次源码构建与最终完成标志。
- `td_project/cli_build/camera_to_dsi_display_phy.area`、`final_timing.rpt`：最终资源与时序。
'''
(root/'验证结果_KEY4_DETECT_V1.md').write_text(text,encoding='utf-8')
print(json.dumps(data,ensure_ascii=False))
