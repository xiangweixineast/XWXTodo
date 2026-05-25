# XWXTodo 架构

## 目录

- `XWXTodo/XWXTodo/Models/`：TODO 模型
- `XWXTodo/XWXTodo/Cloud/`：云端 API、DTO、认证、Keychain 会话
- `XWXTodo/XWXTodo/Stores/`：TODO 状态入口
- `XWXTodo/XWXTodo/Caches/`：云端快照缓存接口 + SQLite 实现
- `XWXTodo/XWXTodo/Overlay/`：AppKit 顶部覆盖层
- `XWXTodo/XWXTodo/Views/`：SwiftUI 面板视图
- `XWXTodo/XWXTodoTests/`：macOS 客户端测试
- `server/app/`：FastAPI、配置、DB、schema、迁移、认证、TODO、后台账号
- `server/deploy/`：systemd、Nginx 部署
- `server/tests/`：服务端测试
- `docs/infos/`：当前事实文档

## 链路

```text
XWXTodoApp -> AppState
AppState -> CloudAuthStore + CloudAPIClient + SQLiteTodoSnapshotCache + TodoStore + OverlayController

CloudAuthStore -> CloudAuthClient -> CloudAPIClient -> HTTPS API
CloudAuthStore -> CloudSessionStore -> KeychainSessionStore -> Keychain

TodoStore -> CloudTodoClient -> CloudAPIClient -> HTTPS API
TodoStore -> TodoSnapshotCache -> SQLiteTodoSnapshotCache -> SQLite

OverlayController -> OverlayPanel -> NotchView / TodoPanelView

python -m app.main -> Settings -> create_app -> FastAPI -> Database
GET /health -> FastAPI -> SQLAlchemy -> MySQL
POST /auth/login -> AuthService -> SQLAlchemy -> MySQL
GET /auth/me / POST /auth/logout -> bearer token -> AuthService -> SQLAlchemy -> MySQL
GET /todos / TODO 写操作 -> bearer token -> TodoService -> SQLAlchemy -> MySQL
python -m app.migrate -> SQLAlchemy MetaData -> MySQL
python -m app.admin create-user <username> -> SQLAlchemy -> MySQL
```

## 边界

- `AppState`：客户端装配、登录恢复、首次同步、轮询同步、退出清理。
- `TodoStore`：TODO 业务状态入口；云端写入成功后应用快照。
- `CloudAPIClient`：HTTP 请求、JSON 编解码、云端错误映射。
- `CloudAuthStore`：认证状态入口；登录、恢复、失效、退出。
- `KeychainSessionStore`：只持久化 bearer token。
- `SQLiteTodoSnapshotCache`：只保存最近一次成功云端快照。
- `OverlayController`：`NSPanel` 生命周期、定位、折叠/展开。
- `schema.py`：服务端表结构唯一入口。
- `AuthService`：登录、token 哈希、token 校验、退出。
- `TodoService`：TODO 快照、状态流转、revision、单 doing。
- `app.admin`：后台建号；客户端无注册。
