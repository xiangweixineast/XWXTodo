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
