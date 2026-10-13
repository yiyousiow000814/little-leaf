# Corner Café — Reference Rearrangement / 112 BPM 循环版

## 文件身份与用户反馈

本包更新的是用户已试听认可的 `Corner_Cafe_Reference_Rearrangement_112bpm`，不是重新创作另一首曲子。
用户新增要求：去掉明显的结束感，让完整音乐可以持续循环。
原版听感已获认可；本次循环衍生的最后一小节及游戏内播放，仍需实际试听核对。
`source/approved_source_events.json` 和 `approved_mix_settings.json` 为原制作源的原样副本。
其中较早的“待试听”文字是历史元数据，不覆盖上述较新的用户决定。

## 先听

- `Corner_Cafe_Loop_Two_Cycles_Preview.mp3`：实际游戏 OGG 解码后连续播放两轮。
  **00:51.429** 处由第一轮末尾直接回到开头，没有插入静音或交叉淡化。
  仅整个试听文件最末 1 秒有方便结束播放的淡出；正式单轮文件完全没有淡出。
- `Corner_Cafe_Loop_Seam_Check.mp3`：末两小节 + 开头两小节的短对照。
  接缝在 **00:04.286**，不插入间隙、不重制另一种编排。

## 用于游戏

`Corner_Cafe_Reference_Rearrangement_112bpm_Loop.ogg` 是压缩游戏候选。
同名 WAV 为 24-bit PCM 无损可用版本，FLAC 为无损归档母版。
单轮 MP3 仅为方便试听的副本；不同播放器的重复播放行为应分别验证。

| 属性 | 值 |
|---|---|
| 拍速 | 112 BPM，未变速 |
| 拍号 / 调性 | 4/4，C major |
| 结构 | 24 小节，A 8 小节 + B 8 小节 + A 回归 8 小节 |
| 总拍数 | 96 拍 |
| 单轮时长 | 51.42857142857143 秒 |
| 采样率 | 44100 Hz，立体声 |
| LOOPSTART | 0 |
| LOOPEND（不含此样本） | 2268000 |
| Godot loop_offset | 0.0 秒 |

Godot 4.6 的 OGG 导入 Loop 选项设为启用，Loop Offset = 0。
也可由现有加载代码设置 `AudioStreamOggVorbis.loop = true`、`loop_offset = 0.0`。
OGG 内的 LOOPSTART/LOOPEND 标签只是辅助说明，不能替代引擎里的 Loop 设置。
不要用 finished 回调再次 play 来拼接，不要自动裁静音、加尾巴或修改节拍长度。
WAV 版本未嵌入自动循环元数据；使用 WAV 时需明确配置 Forward、起点 0、终点整文件。
首次进入游戏和切换曲目的音量包络属于播放器，不应烘焙到每一轮文件首尾。
本包未修改仓库、播放器、存档、平台适配或线上 BGM。

官方循环设置依据：
- https://docs.godotengine.org/en/4.6/classes/class_audiostreamoggvorbis.html
- https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_audio_samples.html

## 音乐改动范围

- 第 1–23 小节的全部音符、和声、力度、时值和微时序参数保留。
- 第 24 小节由 Dm7 / G7 / C6 的落地收束，改成 Dm7 / G7 的回接。
  旋律以 F–E–D 下降，再由 B–D 引向下一轮开头的 E–G–A。
- 保持鼓点，贝斯用 D–G–B 接回下轮 C；不再全体收在一个长 C 和弦上。
- 原电钢琴、尼龙吉他、贝斯、刷鼓音色、滤波、声像、混响比例及混音增益不变。
- 合成器释放尾音跨边界折回；滤波器使用周期稳态，房间混响使用圆周卷积。
  因此开头会有上一轮尾音，这是循环的正常组成，不是额外音符或任意音乐交叉淡化。

## 已完成的技术核对

- OGG 与无损单轮解码均为 2,268,000 个采样。
- FFmpeg 连续解码两轮为 4,536,000 个采样；两轮 PCM 完全相同。
- 无 NaN / Inf / 满幅削波；压缩解码后响度约 -17.97 LUFS，4 倍插值估计真峰约 -2.72 dBTP。
- 源事件证明前 23 小节完全相同；避开首端新回绕尾音与末小节提前 4ms 的贝斯攻击后，
  正文与获认可母版的 PCM 最大差约一个 24-bit 量化步长。
- 这不是人耳、真实 Godot/Web 解码输出或长时间游戏试听的验收替代。
  本次没有宣称已在 Little Leaf 引擎内实测。

详见 `evidence/loop_validation.json`。

## 源文件与重建

- `music_events.json`：完整 4 声部演奏事件及循环元数据。
- `.mid`：完整 4 轨演奏；默认 MIDI 不自动无限播放，在 DAW 设 24 小节循环区域。
- `Lead_Sheet_Loop.musicxml`：主旋律 + 和弦标记，带重复记号，不是全乐队总谱。
- `stems/*_loop.flac`：四个处理后无损循环分轨，同长、同起点；相加对应无损母版（量化误差除外）。
- `source/build_loop.py`：制作脚本；`audio_helpers.py`：沿用原版的合成与谱面辅助实现。
- `source/TimGM6mb_package_notice.txt`：现有音源许可记录；不分发音源或字体二进制。

```
python source/build_loop.py --out ./rebuilt --soundfont /path/to/TimGM6mb.sf2
python source/verify_loop.py ./rebuilt
```

需要已有 numpy、scipy、soundfile、mido、pyloudnorm、libfluidsynth 和 ffmpeg。
脚本不会安装软件、购买服务、联网下载或修改游戏。使用与原版相同 SHA-256 的音源；
不允许无提示换音源后把重渲染当成用户已认可的声音。
