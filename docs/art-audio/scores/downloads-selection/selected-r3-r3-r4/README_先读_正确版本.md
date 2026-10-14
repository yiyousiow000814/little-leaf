# Little Leaf — 四首选定制作合集

## 先看版本，不要用“最新版本”自动覆盖

这份包只收录以下四首。R5 是此次合集编号，不是把前三首改成了 R5。

| 顺序 | 曲目 | 正确版本 | 当前状态 |
|---|---|---|---|
| 1 | 三叶微风 · Cloverlight | **R3 PhraseFix** | 用户明确选定，音频原样保留 |
| 2 | 花影小序曲 · Petal Promenade | **R3 Clarinet Main** | 用户明确选定，音频原样保留 |
| 3 | 花巷庆典 · Fiesta en Flor | **R4 Trumpet Throughout** | 用户明确选定，音频原样保留 |
| 4 | 晴日蹦跳 · Sunshine Skip | **新作，176 BPM** | 替代被否决的 Pinwheel；本首尚待用户试听 |

前三首 MP3、无损母版、原演奏事件、原 MIDI、MusicXML 与分轨均来自相应原制作包；没有再次混音、变速或偷偷换回另一个版本。前三首 MP3 还与此前直接提供的试听文件逐字节核对。

**Pinwheel Parade 不在本包中。** 也不包含 Cloverlight 的 R4 恢复版、Petal 的小提琴全程 R4 或 Fiesta 的吉他主奏 R3，避免 Dots 选错。

## 第四首的写法

《晴日蹦跳》是新旋律、新伴奏，不是 Pinwheel 的加速版。固定四分拍 176 BPM、4/4、G 大调，34 小节加弱起与自然尾音，约 48.53 秒。

手风琴承担所有旋律段，搭配较轻的吉他、拨奏弦乐、拨弦贝斯和刷鼓/轻镲。开头短促上行的节奏动机形成记忆点；随后有较高的回应、较疏的桥段、变化后的主题回归和两小节收束。没有中途换掉主奏、重新转入另一种独奏，也没有用音频变速或升调获得快拍。

参考时间：约 00:00–00:11 主主题；00:11–00:22 高音区回应；00:22–00:33 较疏桥段；00:33–00:44 主题变奏回归；00:44 后收束。拍子保持一致，变化来自旋律、发音、伴奏与密度。

“快乐、快拍、有记忆点”是本次写作方向，不是自动通过的评价。第四首仍需用户实际试听决定。

## 每首的资料

- MP3：方便试听；前三首与原试听文件一致。
- FLAC：24-bit、44.1 kHz 立体声无损母版。
- `stems/`：对齐的干声与混音分轨；`*_mix.flac` 相加重建母版（量化误差以内）。
- `*_Performance.mid`：实际音符、速度图与表情控制。
- `*_Lead_Sheet.musicxml`：主旋律与和弦谱，**不是全乐队总谱**。
- `performance_events.json`：完整分声部音符、精确时间、力度与连续表情控制。
- `CURRENT_STATUS.json`：本轮正确的用户选择与音频身份。

旧演奏账本中的 `pending`/`awaiting` 与 `original_technical_checks.json` 是原制作时间的历史标签。**当前反馈以根目录 `SELECTION_MANIFEST.json` 和各曲 `CURRENT_STATUS.json` 为准**，不要把历史标签当成用户尚未选择前三首。

## 复现与编辑

`source/render_selected.py` 使用本包四份演奏账本渲染。前三首从当前源码重新渲染后，全部无损母版及分轨与原版 PCM 样本一致；第四首也进行了第二次独立输出并核对一致。见 `verification/`。

运行环境与依赖在 `source/render_environment.json`、`source/requirements.txt`。需自行提供与记录哈希相同的 TimGM6mb.sf2；本包不分发 SoundFont 或字体二进制。不同音源/合成器版本可能改变声音，不应覆盖原试听。

```sh
python source/render_selected.py --package . --out ../littleleaf-rebuild --soundfont /path/to/TimGM6mb.sf2
```

只重建第四首：

```sh
python source/render_selected.py --package . --out ../sunshine-rebuild --soundfont /path/to/TimGM6mb.sf2 --track 04
```

从新作的可编辑作曲源重新生成第四首账本：

```sh
python source/compose_sunshine_skip.py ../new-fourth-ledger.json
```

重新导出的谱面标题/说明元数据可能与原谱不同；原谱在各曲目录中原样保留。MIDI 本身不含音源采样、自制打击乐波形、外部 EQ/混响和混音增益；要重现相同声音须使用渲染脚本与记录的依赖。

## 循环与游戏边界

**四首目前均是有收尾的完整试听，不是已验证的无缝循环资产。** 用户本轮选择了前三首的音频版本，不代表已经授权更改其结尾。不要直接切尾、强行循环或把 A/B 试听拼接当循环音乐。

本次没有修改 GitHub、Dots、存档、游戏音频逻辑或部署；第四首也没有被自动认定为正式游戏 BGM。

## 核验

`verification/` 保存：原版文件一致性、完整母版及分轨重建一致性、解码、音符时序、MIDI 数量、谱面小节时值和混音分轨相加检查。

技术核验不代表主观音乐品质通过。没有宣称第四首已经被用户接受，也没有宣称已在 Godot 中测试。

## 给 Dots

请以本包的版本选择为准：Cloverlight R3、Petal R3、Fiesta R4。不得按文件日期改用较新的其他版本。第四首为新的待试听快拍主题；被否决的 Pinwheel 不再列为正向参考。使用现有 Audio Bible/Music Skills，不新增付费依赖，不自动发布。第三方音源来源通知在 `licenses/`，不要把录音试听认可当作所有素材权利均已审清。
