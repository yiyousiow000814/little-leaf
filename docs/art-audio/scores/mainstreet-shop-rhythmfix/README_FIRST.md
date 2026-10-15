# Little Leaf — Main Street 原版 + Shop 节奏修订版

## 先试听

| 文件 | 当前状态 |
|---|---|
| `01_Main_Street/Corner_Cafe_Main_Street_112bpm.mp3` | 用户已明确觉得很不错；原版逐字节保留，没有重渲染、改速或重新压缩。|
| `02_Shop_Rhythm_Fix/Corner_Cafe_Shop_112bpm_Rhythm_Fix.mp3` | 本次针对 kalimba 和 percussion 的新修订，待用户试听。|

两首均为 **112 BPM、4/4、24 小节，每轮 51.428571 秒**。

游戏用整首循环优先使用对应的 `*_Loop.ogg`，循环从采样 0 到 2,268,000（尾端不含）。
单轮 MP3/OGG/无损母版都没有结尾淡出。每个 `Two_Cycles.mp3` 是实际 OGG 解码后直接首尾拼接两次；中间 00:51.43 没有交叉淡化，只有整个试听文件最后一秒淡出。
`Seam_Check.mp3` 是接缝前后各两小节。
本次没有运行 Godot 或改动用户仓库；最终引擎循环与场景切换需单独验证。

## Shop 这次具体改了哪里

原版 kalimba 每小节的切分位置交替变化，部分小节含一个十六分拍的句尾插音；percussion 又有零星高音邦戈和移到弱拍的句尾敲击。这里是编配事实，不是声称原音乐有程序计时错误，也不是把切分音判为错误。

本次将两条伴奏当成一个共同的节奏来处理：

- **Kalimba**：主要落在第 1、3 拍；每四小节句尾让出第二个落点给主旋律／钢片琴。66 个音减少为 42 个。沿用原有和弦内音，不另写一条抢主旋律的伴奏旋律；跨和弦的落点按该拍和声检查。
- **Percussion**：以一种较低的木块音色轻落第 2、4 拍，去掉零星邦戈插音与句尾移拍；交接处留白，最后一小节仍有轻的规则落点接回开头。54 次敲击变为 43 次。
- 只将这两层的活动片段目标电平分别降低约 1.5 dB / 2.5 dB；不改变整体速度、不对完整混音另行推高或压低。

**以下完全不动：马林巴主旋律、钢片琴接句、低音的全部音符/力度/发音/时序，以及三份已处理的 FLAC 分轨文件本身。** 三个分轨逐字节复制，原始混音总增益沿用。
和声、24 小节结构和主题 123 个音的演奏事件也不变。

这不是“所有音乐都应该写成第 1/3 拍、第 2/4 拍”的长期公式，而是针对这一首的伴奏拥挤反馈所做的有界改动。最终是否更顺仍以用户试听为准。

## 包内资料

- `01_Main_Street/`：上一包的整个 Main Street 目录原样保留，含 MP3、OGG、母版、五个分轨、MIDI、主旋律与和弦谱和当时的验证记录。
- `02_Shop_Rhythm_Fix/`：新 Shop 全部音频、五个分轨、MIDI、演奏事件、未改动的主题谱、逐小节节奏表和本次技术检查。
- `previews/Shop_Rhythm_Before_After_8bars.mp3`：旧 Shop 前八小节 → 1 秒间隔 → 新 Shop 前八小节。仅比较文件做了微量响度匹配和片尾短淡出；不是游戏曲目。
- `source/`：原版制作源码及新修订脚本、原 Shop 事件/参数。没有原作 Restaurant City 录音、SoundFont、字体二进制。
- `evidence/`：原版身份、此次差异、技术验证与运行环境。

原 Main Street 目录中的 `validation.json` 是上次生成的历史技术记录；其旧“待试听”字样不覆盖本次用户认可。当前状态以本 README 和 `evidence/approval_and_preservation.json` 为准。
MusicXML 是 **Lead Sheet（主旋律与和弦谱），不是全乐队总谱**；精确伴奏与演奏在 MIDI/JSON 中。

## 给 Dots 的简短交接

Main Street 不要换成重新渲染的版本；使用 `01_Main_Street/` 里的原音频。
Shop 新候选是 `02_Shop_Rhythm_Fix/`，不要拿比较预览或旧 Shop 来接入游戏。
在用户确认这次修订之前，不将 Shop 新版标为最终批准。
不改变既有主 BGM，不修改游戏里的播放时机、经济或存档。
本次没有付费 API、订阅、额外素材购买、工具安装或 GPU 租用。

## 重建新 Shop

已具备相同依赖与相同 TimGM6mb 音源时，从包根目录运行：

```sh
python source/revise_shop.py --out /path/to/new-shop-folder --soundfont /path/to/TimGM6mb.sf2
```

脚本默认从本包 Shop/stems 读取三个未改动的原始分轨，先校验哈希，再只渲染 kalimba/percussion。必须输出到新空目录，不覆盖用户听过的文件。
不同音源不能假装为同一结果。主街区无需重建；旧 `build_scene_variants.py` 仅保留原始生产出处。
技术检查不能替代听感，也没有证明所有平台上的实时循环或场景切换。
