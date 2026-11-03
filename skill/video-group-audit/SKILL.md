---
name: video-group-audit
description: Audit video-frame dataset splits for shared source groups and exact cross-split duplicate files using an explicit CSV manifest.
---

读取 [README.md](README.md)。先确认来源视频ID可靠，再生成 `path,split,group` CSV并运行审计。按视频组划分后重新训练，旧的混合集训练结果不能作为无泄漏结果。

不要凭视频名不同就声称场景独立；完全重复文件检查不能发现所有相似帧。分别报告验证集与独立测试集，并标明数据数量。

