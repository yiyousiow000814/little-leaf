# Little Leaf 音乐交接：版本纠错版 v2

请与另外三份附件一起接收。不要沿用之前错误的“用户认可完整 Corner Cafe V2 / Daybreak”总结。

## 四份文件

1. `01_LittleLeaf_Music_Skills_v2_Corrected.zip`：本包，两个 Skills、参考状态登记与整合说明。
2. `Corner_Cafe_Harmony_Study.zip`：用户本次上传的原档案，字节完全保留。里面 A、B 均为正向短试听参考。
3. `Restaurant_City_Default_original.mp3`：用户先前上传的原 MP3，字节完全保留，仅私人研究。
4. `04_Corner_Cafe_Reference_Rearrangement.zip`：本次新作/重编，未被用户批准。

不要把另一个完整 `LittleLeaf_Corner_Cafe_v2_Package.zip` 混进来。
不要包含或采用被否决的 Daybreak Steps。

## 整合方式

先读取当前 AGENTS / Audio Bible / 工作 Owner，复用已有音乐规范 PR。
本包 `repo_patch/` 是候选文件，不是覆盖整个仓库的安装器。
审查后更新两个 Music Skills 和参考研究页；Audio Bible 只链接它们、记录正确版本状态。
有用户认可的短例子，也不等于无需制作审核或可以自动替换 BGM。

Dots 在音乐任务中明确指定制作 Skill；由能实际感知音频的审查者使用审核 Skill。
没有可用音频感知能力时，如实报告，仅提交已完成的技术/符号分析，不能假装听过。

现有免费工具继续使用，不新增付费 API / 订阅 / GPU 租用。不要重启全仓库 QA。
私人的原作音频与大体积试听材料不直接提交公开 GitHub；公开规则使用安全的引用。
本包未执行任何 GitHub 写入、合并、发布、Dots 更新或游戏资源替换。

## 独立校验（不运行音乐生成、不联网）

解压本包后，在已有 Python 环境执行：

```sh
python verify_handoff.py --directory /path/to/the/four/downloads
```

校验结果只证明附件身份，不证明音乐好听。
