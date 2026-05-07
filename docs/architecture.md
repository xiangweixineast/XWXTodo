# XWXTodo 核心架构

本文件只维护：文档原则、目录结构、代码架构、数据库结构。

## 0. 文档原则

- 只记录当前仓库的核心架构，不记录计划、历史或验收结果。
- 只保留目录结构、代码架构、数据库结构三类正文信息。
- 用最短、最准确的语言描述事实。
- 优先使用目录树、表格、依赖箭头和 SQL。
- 不写产品介绍、技术栈清单、测试命令、打包命令或手动 QA。
- 架构变化时更新本文件，并删除过期内容。
- 全局只维护这一份核心架构文档。

## 1. 目录结构

```text
XWXTodo/
├── XWXTodo.xcodeproj
└── XWXTodo/
    ├── XWXTodoApp.swift
    ├── ContentView.swift
    ├── Models/
    ├── Stores/
    ├── Repositories/
    ├── Overlay/
    └── Views/
```

核心目录职责：

| 目录 | 职责 |
| --- | --- |
| `Models/` | TODO 数据模型 |
| `Stores/` | 业务规则和可观察状态 |
| `Repositories/` | 持久化接口和 SQLite 实现 |
| `Overlay/` | AppKit 覆盖层窗口 |
| `Views/` | SwiftUI 界面 |

## 2. 代码架构

核心依赖方向：

```text
Views -> TodoStore -> TodoRepository -> SQLiteTodoRepository -> SQLite
```

覆盖层方向：

```text
OverlayController -> OverlayPanel -> NotchView / TodoPanelView
```

启动装配：

```text
XWXTodoApp -> AppState -> SQLiteTodoRepository + TodoStore + OverlayController
```

核心边界：

- 视图只调用 `TodoStore`，不直接访问数据库。
- `TodoStore` 是 TODO 业务规则唯一入口。
- `TodoStore` 只依赖 `TodoRepository` 协议。
- SQLite 细节只在 `SQLiteTodoRepository`。
- 覆盖层窗口行为只在 `Overlay/`。

## 3. 数据库结构

数据库文件：

```text
~/Library/Application Support/XWXTodo/xwxtodo.sqlite
```

`todos` 表：

```sql
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  completed_at REAL,
  sort_order INTEGER NOT NULL
);
```

`status` 取值：

```text
pending | doing | completed
```

唯一 `doing` 索引：

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_todos_single_doing
ON todos(status)
WHERE status = 'doing';
```
