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
├── XWXTodo/
│   ├── XWXTodoApp.swift
│   ├── ContentView.swift
│   ├── Models/
│   ├── Stores/
│   ├── Repositories/
│   ├── Overlay/
│   └── Views/
└── server/
    ├── app/
    └── tests/
```

核心目录职责：

| 目录 | 职责 |
| --- | --- |
| `Models/` | TODO 数据模型 |
| `Stores/` | 业务规则和可观察状态 |
| `Repositories/` | 持久化接口和 SQLite 实现 |
| `Overlay/` | AppKit 覆盖层窗口 |
| `Views/` | SwiftUI 界面 |
| `server/app/` | FastAPI 服务端入口、配置读取和数据库连接 |
| `server/tests/` | 服务端 pytest 测试 |

## 2. 代码架构

核心依赖方向：

```text
Views -> TodoStore -> TodoRepository -> SQLiteTodoRepository -> SQLite
```

覆盖层方向：

```text
OverlayController -> OverlayPanel -> NotchView / TodoPanelView
```

覆盖层状态：

```text
collapsed -> expanding -> expanded -> collapsing -> collapsed
```

启动装配：

```text
XWXTodoApp -> AppState -> SQLiteTodoRepository + TodoStore + OverlayController
```

服务端健康检查方向：

```text
GET /health -> FastAPI -> SQLAlchemy -> MySQL
```

核心边界：

- 视图只调用 `TodoStore`，不直接访问数据库。
- `TodoStore` 是 TODO 业务规则唯一入口。
- `TodoStore` 只依赖 `TodoRepository` 协议。
- `TodoStore` 提供列表排序、doing/pending 状态流转入口和收起态刘海屏文案。
- SQLite 细节只在 `SQLiteTodoRepository`。
- 覆盖层窗口行为只在 `Overlay/`。
- `OverlayController` 持有 `OverlayPanel` 和 `NSHostingController<AnyView>`。
- 收起态 frame 按 `TodoStore.collapsedNotchTitle` 和 `NotchView` fitting size 计算，高度固定为 `OverlayMetrics.notchHeight`。
- 展开态 frame 固定为 `OverlayMetrics.panelWidth` x `OverlayMetrics.panelHeight`。
- 悬停展开和离开收回通过 `Timer` 以约 60fps 插值 `NSPanel` frame；屏幕参数变化和显示覆盖层时直接定位。
- 展开和收回期间保持 `TodoPanelView` 内容，收回动画结束后切回 `NotchView`。
- 服务端配置从 `XWXTODO_` 环境变量或 `server/.env` 读取。
- 服务端当前只提供 `GET /health`。
- 服务端数据库层只封装 SQLAlchemy engine 和 `SELECT 1` 连通性检查。

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
