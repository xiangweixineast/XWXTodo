# XWXTodo

XWXTodo 是一款 macOS 本地 TODO 应用。功能说明以 [docs/features.md](docs/features.md) 为准，代码架构和数据库结构以 [docs/architecture.md](docs/architecture.md) 为准。

## 环境

- macOS 14+
- Xcode 16+
- Swift 5

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

## 本地数据

TODO 数据保存在本机 SQLite 数据库：

```text
~/Library/Application Support/XWXTodo/xwxtodo.sqlite
```

## 分发说明

`scripts/package.sh` 会生成 `dist/XWXTodo.zip`。当前 zip 使用 ad-hoc 签名且未 notarize，发给其他 Mac 时可能被 Gatekeeper 阻止，需要用户手动允许。
