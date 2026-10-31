"""Validate and archive TOON_R4 after TD/export/merge; no hardware access."""
from pathlib import Path
import json
import re
import shutil
import zlib

root = Path('D:/Anlogic/HX1P35A2026/anlogic_example/lab_ex5_voice_KEY4_V1/lab_ex4_style')
out = Path(__file__).resolve().parent
build = root / 'td_project/cli_build'
validation = out / 'validation'

def read(path):
    return path.read_text(encoding='utf-8', errors='replace')

build_log = read(root / 'toon_r4_build.log')
assert 'STYLE_TD_BUILD_FINISHED' in build_log
assert 'STYLE_TD_BUILD_ERROR' not in build_log
assert 'STANDALONE_FPGA_BIN_EXPORT_PASS' in read(out / 'export_fpga_bin.log')
ts = read(build / 'camera_to_dsi_display_phy.ts')
timing = {k: float(re.search(k + r':\s*([-\d.]+)ns', ts).group(1))
          for k in ('SWNS', 'HWNS', 'STNS', 'HTNS')}
assert timing['SWNS'] >= 0 and timing['HWNS'] >= 0
assert timing['STNS'] == 0 and timing['HTNS'] == 0
area = read(build / 'camera_to_dsi_display_phy.area')
counts = {k: int(re.search(r'^#' + k + r'\s+(\d+)', area, re.M).group(1))
          for k in ('slice', 'lut6', 'eram', 'dsp')}

# The GUI may omit latency files when saving .al; the build script adds them.
prj = read(build / 'camera_to_dsi_display.prj')
for unit in ('video_latency.v', 'latency_overlay.v', 'video_style_core.v', 'hdmi_mixer.v'):
    assert '/' + unit + '"' in prj, unit
shutil.copy2(root / 'td_project/camera_to_dsi_display.al',
             out / 'source_changes/td_project/camera_to_dsi_display.al')
shutil.copy2(build / 'camera_to_dsi_display.prj', validation / 'compiled_project.prj')
for f in (out / 'source_changes').rglob('*'):
    if f.is_file():
        rel = f.relative_to(out / 'source_changes')
        assert f.read_bytes() == (root / rel).read_bytes(), str(rel)

runs = json.loads(read(validation / 'simulations.json'))['runs']
assert len(runs) == 12 and all(r['result'] == 'PASS' for r in runs)
for artifact in ('app_payload.bin', 'voice_boot.bin', 'voice_key4_tcm.elf', 'voice_templates.mem'):
    assert (out / artifact).read_bytes() == (out.parent / 'voice_key4_toon_r3' / artifact).read_bytes()

fpga = (out / 'voice_toon_r4_fpga.bin').read_bytes()
bit = (out / 'voice_toon_r4.bit').read_bytes()
image = (out / 'voice_toon_r4_flash.bin').read_bytes()
boot = (out / 'voice_boot.bin').read_bytes()
assert bit == (build / 'camera_to_dsi_display.bit').read_bytes()
assert bit.endswith(fpga)
assert len(image) == 14716736
assert image[:len(fpga)] == fpga
assert image[len(fpga):0xE00000] == b'\xff' * (0xE00000 - len(fpga))
assert image[0xE00000:] == boot
for release, crc in [('toon_r3', 'bf60a395'), ('toon_r2', 'd3364edf'),
                     ('toon_r1', '5401036b'), ('isp_r2', '23e45574')]:
    old = out.parent / ('voice_key4_' + release) / ('voice_' + release + '_flash.bin')
    assert f'{zlib.crc32(old.read_bytes()):08x}' == crc, old.name

shutil.copy2(root / 'toon_r4_build.log', validation / 'full_build.log')
for name in ('camera_to_dsi_display_phy.ts', 'camera_to_dsi_display_phy.area',
             'final_timing.rpt', 'route.qor'):
    shutil.copy2(build / name, validation / name)
manifest_path = out / 'manifest.json'
manifest = json.loads(read(manifest_path))
assert manifest['merged_crc32'] == f'{zlib.crc32(image):08x}'
manifest.update(
    validation='Full fresh synthesis/place/route/bitgen and final setup/hold PASS; 11 affected benches plus one ramp variant PASS; Flash layout verified. Hardware visual acceptance pending.',
    affected_regression_count=11, affected_simulation_runs=12,
    setup_wns_ns=timing['SWNS'], hold_wns_ns=timing['HWNS'],
    setup_tns_ns=timing['STNS'], hold_tns_ns=timing['HTNS'],
    slices=counts['slice'], slice_percent=round(counts['slice'] / 21216 * 100, 2),
    lut6=counts['lut6'], eram=counts['eram'], dsp=counts['dsp'],
    boot_matches_toon_r3=True,
    compiled_project='validation/compiled_project.prj; required latency units inserted by build_td.tcl when missing from GUI .al')
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
prior_path = out.parent / 'voice_key4_toon_r3/manifest.json'
prior = json.loads(read(prior_path))
prior['hardware_acceptance'] = {
    'result': 'COLOR_CONTOUR_TUNING_REQUIRED',
    'scope': 'User reports unclear contours, gray becoming black, white becoming gray; occurrence location uncertain.'}
prior_path.write_text(json.dumps(prior, indent=2) + '\n', encoding='utf-8')
metrics = (f"完整综合、布局、布线及 bitgen 通过；建立 WNS {timing['SWNS']:+.3f}ns，"
           f"保持 WNS {timing['HWNS']:+.3f}ns，两项 TNS 均为0。"
           f"Slice {counts['slice']}/21216，LUT6 {counts['lut6']}，ERAM {counts['eram']}/108，DSP {counts['dsp']}/40。")
guide = next(out.glob('*.md'))
text = read(guide)
if '## 最终构建记录' not in text:
    text += ('\n## 最终构建记录\n\n' + metrics + '\n\n'
             '11项受影响RTL测试及1项宽渐变参数变体全部通过；填色数值属性检查通过。'
             f"完整Flash镜像14716736字节，CRC32 {manifest['merged_crc32']}。"
             'FPGA原始配置、Flash填充区和CPU启动程序的布局已逐段校验。'
             '语音应用、预置模板及启动程序与R3逐字节一致；R1、R2、R3及ISP_R2旧镜像未改动。'
             '未自动烧录，实机颜色与轮廓效果仍待确认。\n')
    guide.write_text(text, encoding='utf-8')
plan = Path('D:/Anlogic/方案/KEY3_风格化诊断与修改方案.md')
text = read(plan)
lines = text.splitlines(keepends=True)
assert lines[2].startswith('当前执行目标')
lines[2] = ('当前执行目标是纠正填色压暗及中性色染色，并将轮廓与填色分开处理；'
            '最新版本为TOON_R4，见第十节。前序版本保留为诊断记录。\n')
text = ''.join(lines)
if '## 十、保色填色与结构细轮廓' not in text:
    text += ('\n## 十、保色填色与结构细轮廓：TOON_R4（2026-10-26）\n\n'
             '用户反馈轮廓不清、灰色变黑、白色变灰，希望颜色鲜明；发生位置为“两种都有／不确定”。'
             '代码复现两项问题：R3大梯度区域统一压暗，白色255可降为159、灰色112可降为79；'
             '独立RGB分档把近中性(127,129,127)放大为(136,160,136)，会产生假色。'
             '这些证据解释了明确存在的算法问题，但不能代替实机颜色标定。\n\n'
             '步骤1：改为共享亮度16级上取整并给三通道施加同一正向提升，保留低于16的暗部；'
             '不再单独量化RGB。仅对明确彩色中间调尝试1.125倍色差，只有候选颜色及共同提升'
             '都能完整落入色域时使用，否则回到原RGB；已明亮饱和的原色保留。'
             '填色亮度不低于现有边界保持平滑的输出，黑色轮廓不在此约束内。\n\n'
             '步骤2：取消宽区域半色压暗及描边后的75/25混合，按Sobel主方向检查局部曲率，'
             '只在亮侧结构边界画黑线；Sobel阈值256，二倍中心与对向邻点和之差需超过16。'
             '标准轴向阶跃只有亮侧一列黑线，高Sobel的线性渐变不涂黑。'
             '这不是完整Canny/NMS，复杂实景线宽仍需目测。\n\n'
             '步骤3：同图软件预览与属性测试先核对色彩方向，再核对RTL及完整720p时序。'
             '11项受影响测试加1项宽渐变变体通过，8450组RTL填色数值检查通过；'
             '原图、边缘、检测模式像素对照保持一致，显示流水仍3324时钟；'
             '实际VTC启动用例仍可从WAIT进入LIVE。\n\n' + metrics + '\n\n'
             f"完整镜像：`{out / 'voice_toon_r4_flash.bin'}`，14716736字节，CRC32 {manifest['merged_crc32']}。"
             'KEY3标识TOON R4，未建立窗口时FX WAIT；语音应用、模板及启动程序与R3逐字节一致。'
             '旧BIN保留，未自动烧录；本版本实机效果待用户确认。软件预览在本版本preview目录，'
             '验证报告和编译时实际工程文件在validation目录。\n')
plan.write_text(text, encoding='utf-8')
print('TOON_R4_RELEASE_VALIDATED', json.dumps({k: manifest[k] for k in (
    'merged_bytes', 'merged_crc32', 'setup_wns_ns', 'hold_wns_ns',
    'slices', 'slice_percent', 'lut6', 'eram', 'dsp')}))
