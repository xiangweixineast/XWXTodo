# Issue tracker: Local Markdown

本仓库的 Issues 和 PRD 使用本地 Markdown 文件管理，统一存放在 `.scratch/`。

## 约定

- 每个功能一个目录：`.scratch/<feature-slug>/`
- PRD 路径：`.scratch/<feature-slug>/PRD.md`
- 实现 issue 路径：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号
- triage 状态写在 issue 文件顶部附近的 `Status:` 行
- 评论和讨论记录追加到文件底部的 `## Comments`

## 发布到 issue tracker

在 `.scratch/<feature-slug>/` 下创建对应 Markdown 文件，目录不存在时先创建目录。

## 获取相关 ticket

读取用户提供的 issue 文件路径。用户通常会直接给出路径或编号。
