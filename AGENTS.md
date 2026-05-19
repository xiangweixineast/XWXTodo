## 沟通语言

- 除非明确要求，否则所有回答默认使用中文。

## 文档修改原则

- 项目中的所有文档修改都必须遵循原则：**合并优于追加，删除优于保留**

## App 功能介绍

- 当前 App 的功能介绍以 `docs/features.md` 为全局唯一来源。

## 当前技术栈

- Swift 5
- SwiftUI
- AppKit
- SQLite3
- XCTest
- Xcode 工程：`XWXTodo/XWXTodo.xcodeproj`
- 打包脚本：`scripts/package.sh`

## 代码架构

- 核心目录结构、代码架构和数据库结构以 `docs/architecture.md` 为全局唯一来源。

## 文档维护规则
**强调**: 只需要维护`docs/infos`下的文档，以下规则也只针对`docs/infos`
- 在每次完成代码改动后，对所有文档进行review，根据代码改动的信息及时修正文档内容，保证文档始终对应最新的代码
- 对于所有文档，强制遵循这个原则：合并优于追加，删除优于保留，用最短、最准确的语言描述事实。
- 内容保持**精确**、**简单**，AI能通过阅读代码得到的结论**不准**写入文档，文档中只提供功能简介、核心架构、代码阅读方向指引等关键信息

## Git规则

- 分支
	- 除非用户明确要求，不自动创建或切换新分支。
	- 合并或提交前先确认当前分支和工作区状态。
- commit message
	- 除前缀外，核心内容强制中文
	- `feat: `表示新功能
	- `fix: `表示Bug Fix
	- `opt: `表示优化

## 常用命令

运行测试：

```bash
xcodebuild test -project XWXTodo/XWXTodo.xcodeproj -scheme XWXTodo -destination 'platform=macOS'
```

运行 Debug 构建：

```bash
xcodebuild build -project XWXTodo/XWXTodo.xcodeproj -scheme XWXTodo -configuration Debug
```

打包 Release zip：

```bash
./scripts/package.sh
```

搜索文件：

```bash
rg --files
```

搜索文本：

```bash
rg "pattern"
```
