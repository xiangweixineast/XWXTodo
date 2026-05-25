# Domain Docs

工程技能在理解本仓库时，按以下规则读取领域文档。

## 读取规则

- 优先读取根目录 `CONTEXT.md`
- 读取 `docs/adr/` 中与当前任务相关的 ADR
- 如果文件不存在，静默继续，不要求预先创建
- `/grill-with-docs` 可在术语或架构决策明确后再补充这些文档

## 布局

本仓库使用 single-context 布局：

```text
/
├── CONTEXT.md
├── docs/adr/
└── XWXTodo/
```

## 术语

输出 issue、重构建议、假设和测试名时，优先使用 `CONTEXT.md` 中定义的领域术语。

## ADR 冲突

如果输出内容与现有 ADR 冲突，需要明确指出冲突点，不要静默覆盖既有决策。
