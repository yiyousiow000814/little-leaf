CORNER CAFE — REFERENCE REARRANGEMENT (112 BPM)
本次新试听，未验收；不是被否决的 Daybreak Steps，也不是原来的完整 Corner Cafe V2。

先听 Corner_Cafe_Reference_Rearrangement_112bpm.mp3。
24 小节 / 4拍 / C大调 / 正文约51.43秒，含自然余音总长约53.03秒。

原始底稿：用户确实喜欢的 Corner_Cafe_Harmony_Study.zip 内 B_reduced_harmony。
选B是这次试验的工作选择，不代表用户选出了A/B赢家。A与B都继续保留。
第一至第八小节主旋律音符事件完全保留；中间八小节是原创较低音区回应；
最后八小节回到主题，并重写最后两小节收束。核心仍是电钢琴、尼龙吉他、
拨弦贝斯和克制的刷鼓，不采用新木管/铃声堆叠来证明“丰富”。

参考曲：用户上传的 Restaurant City Default。
吸收的是前期参考分析中的圆润键盘角色、稳定轻节奏、短回应和留白；
未使用原曲旋律、完整转录、分轨或录音采样。112 BPM沿用用户喜欢的A/B，
不根据“原作约120BPM”强行提速，也没有重新采用被拒绝的Daybreak降速方案。

文件：
- MP3：便捷试听；FLAC：24位无损试听母版。
- MIDI：4轨完整演奏事件，包括力度、发音长短和微小演奏延迟。
- Lead_Sheet.musicxml：主旋律+和弦，不是4声部完整总谱。
- music_events.json：完整音乐/演奏事件权威数据。
- stems/：四个时间对齐的处理后分轨，其和对应无损混音（量化误差除外）。
- source/：可离线修改/重建的免费工具源码及音源许可记录。

重建：先装已有免费依赖，不需要付费API。
python source/compose_arrangement.py
python source/render_arrangement.py --out rebuilt --soundfont /path/to/TimGM6mb.sf2

仅技术检查已完成；本次没有独立的人耳/音频模型盲审、真实游戏混音测试或
长时间耐听验收。不宣称它一定更好或已达到Restaurant City品质。
这是带结尾的闭合试听，不是已经验证的无缝游戏循环。
未修改GitHub、Dots、原音乐文件、用户存档或线上BGM。
音源使用环境现有TimGM6mb，音源/字体二进制不随包分发；许可记录见source/。
