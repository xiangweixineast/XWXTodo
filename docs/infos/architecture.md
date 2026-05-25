# XWXTodo 核心架构

本文件只维护：文档规则、目录结构、代码核心架构。

## 0. 文档规则

- 只记录当前仓库的核心架构，不记录计划、历史或验收结果。
- 正文只保留目录结构和代码核心架构。
- 合并优于追加，删除优于保留。
- 用最短、最准确的语言描述事实。
- **强制遵守**: AI 能通过阅读代码推理出的细节不写入本文档。

## 1. 目录结构

```text
XWXTodo/
├── XWXTodo/
│   ├── XWXTodo.xcodeproj
│   ├── XWXTodo/
│   │   ├── Models/
│   │   ├── Cloud/
│   │   ├── Stores/
│   │   ├── Caches/
│   │   ├── Overlay/
│   │   └── Views/
│   └── XWXTodoTests/
├── server/
│   ├── app/
│   ├── deploy/
│   └── tests/
└── docs/infos/
```

| 目录 | 职责 |
| --- | --- |
| `XWXTodo/XWXTodo/Models/` | TODO 数据模型 |
| `XWXTodo/XWXTodo/Cloud/` | 云端 API、DTO、认证状态和 Keychain 会话存储 |
| `XWXTodo/XWXTodo/Stores/` | TODO 业务状态入口 |
| `XWXTodo/XWXTodo/Caches/` | 云端 TODO 快照缓存协议和本地 SQLite 实现 |
| `XWXTodo/XWXTodo/Overlay/` | AppKit 顶部覆盖层 |
| `XWXTodo/XWXTodo/Views/` | SwiftUI 界面 |
| `XWXTodo/XWXTodoTests/` | macOS 客户端测试 |
| `server/app/` | FastAPI 服务、配置、数据库连接、表定义、迁移、认证、TODO API 和后台账号管理 |
| `server/deploy/` | systemd、Nginx 部署模板和部署说明 |
| `server/tests/` | 服务端测试 |
| `docs/infos/` | 当前功能和架构信息文档 |

## 2. 代码核心架构

macOS 客户端启动装配：

```text
XWXTodoApp -> AppState -> CloudAuthStore + CloudAPIClient + SQLiteTodoSnapshotCache + TodoStore + OverlayController
```

macOS 客户端业务依赖：

```text
Views -> AppState / TodoStore
TodoStore -> CloudTodoClient -> CloudAPIClient -> URLSession -> HTTPS API
TodoStore -> TodoSnapshotCache -> SQLiteTodoSnapshotCache -> SQLite
```

macOS 客户端云同步基础层：

```text
CloudAuthStore -> CloudAuthClient -> CloudAPIClient -> URLSession -> HTTPS API
AppState -> CloudTodoClient -> CloudAPIClient -> URLSession -> HTTPS API
CloudAuthStore -> CloudSessionStore -> KeychainSessionStore -> Keychain
```

macOS 顶部覆盖层：

```text
OverlayController -> OverlayPanel -> NotchView / TodoPanelView
```

服务端启动装配：

```text
python -m app.main -> Settings -> create_app -> Database
```

服务端核心链路：

```text
GET /health -> FastAPI -> SQLAlchemy -> MySQL
POST /auth/login -> FastAPI -> AuthService -> SQLAlchemy -> MySQL
GET /auth/me / POST /auth/logout -> Bearer token -> AuthService -> SQLAlchemy -> MySQL
GET /todos / TODO 写操作 -> Bearer token -> TodoService -> SQLAlchemy -> MySQL
python -m app.migrate -> SQLAlchemy MetaData -> MySQL
python -m app.admin create-user <username> -> SQLAlchemy -> MySQL
```

核心边界：

- `TodoStore` 是 TODO 业务状态、云端操作和本地快照入口。
- SwiftUI 视图只调用 `TodoStore`，不直接访问持久化层。
- `AppState` 协调云端登录状态、首次同步和运行中短轮询。
- `TodoSnapshotCache` 隔离云端 TODO 快照缓存接口，当前实现为 `SQLiteTodoSnapshotCache`。
- `CloudAuthStore` 是客户端云端登录状态入口。
- `CloudAPIClient` 封装云端认证和 TODO API。
- `KeychainSessionStore` 只保存 bearer token。
- `OverlayController` 负责 `NSPanel` 生命周期、定位和折叠/展开状态。
- 服务端配置统一由 `Settings` 读取。
- 服务端表结构统一由 `app/schema.py` 定义。
- 服务端迁移由 `app/migrate.py` 显式执行。
- 服务端认证使用 bearer token，数据库只保存 token 哈希。
- 服务端 TODO 读写由 `TodoService` 统一维护快照和 revision。
- 服务端账号只能通过后台脚本创建，数据库只保存密码哈希。
