# XWXTodo 云同步实施计划

## Summary

- 采用“服务器唯一真相源”：登录后 TODO 读写都走云端，客户端不做离线写入、不展示离线旧缓存。
- 同步体验为 App 运行期间持续短轮询，默认每 3 秒拉取一次；本机操作成功后立即刷新状态，其他设备几秒内可见。
- 账号系统保持简单：服务端后台脚本创建账号，App 只提供登录、自动保持登录、退出登录，不提供注册。
- 首次登录直接用云端数据覆盖本机 TODO，不合并、不备份。

## Key Changes

- 在当前仓库新增 `server/`，实现 FastAPI + MySQL 同步服务、建号管理脚本、部署模板和服务端测试。
- 服务部署到 CVM：FastAPI 监听 `127.0.0.1:18080`，Nginx 通过 `https://xwxai.cn/xwxtodo/api/v1` 反代，复用现有 `xwxai.cn` 证书。
- 客户端新增主窗口登录/状态页：登录、同步状态、上次同步时间、错误提示、退出登录；顶部 TODO 面板只承载 TODO 使用。
- 登录成功后 token 存 Keychain；退出登录时删除 token，并清空本地 TODO 缓存。
- 修改 `TodoStore` 为云端驱动：新增/编辑/删除/开始/回退/完成都调用服务端，成功后用服务端快照替换本地状态。
- 更新 `docs/features.md` 和 `docs/architecture.md`：功能说明从“TODO 数据保存在本机”改为云同步当前事实；服务器变更同步更新 `docs/服务器信息.md`。

## Public APIs / Interfaces

- 固定 API Base URL：`https://xwxai.cn/xwxtodo/api/v1`。
- 认证接口：
  - `POST /auth/login`：`username/password` 登录，返回 bearer token、账号信息和过期时间。
  - `POST /auth/logout`：注销当前 token。
  - `GET /auth/me`：校验 token 并返回当前账号。
- TODO 接口：
  - `GET /todos`：返回 `{ revision, todos }`；客户端轮询使用。
  - `POST /todos`：新增 TODO，服务端生成 id、时间戳和 sort order。
  - `PATCH /todos/{id}`：编辑标题。
  - `DELETE /todos/{id}`：删除未完成 TODO，保持当前“已完成不可删除”规则。
  - `POST /todos/{id}/start|pause|complete`：状态流转；服务端事务保证同账号同一时间只有一个 doing。
- 冲突策略：所有写入按服务端收到顺序串行处理，最后操作生效；每次成功写入递增账号 revision。

## Test Plan

- 服务端 pytest 覆盖：登录失败/成功、token 校验、后台建号、TODO CRUD、单 doing 约束、revision 递增、最后操作生效。
- Swift XCTest 覆盖：登录状态恢复、退出清理、云端快照替换、网络失败不展示旧缓存、各 TODO 操作成功/失败路径。
- 集成验收：部署后用管理脚本创建测试账号，curl 验证 HTTPS API，再用 App 登录两次模拟双设备同步。
- 本地验证命令：`xcodebuild test -project XWXTodo/XWXTodo.xcodeproj -scheme XWXTodo -destination 'platform=macOS'`，并运行服务端测试套件。

## Assumptions

- 第一版不做 WebSocket/SSE、不做离线队列、不做 App 内注册、不做本地数据备份。
- Release 客户端固定连接 `xwxai.cn`，不暴露服务器地址配置。
- 默认首个正式账号可用管理脚本创建，密码在服务器终端交互输入，不写入仓库或文档。
- 现有服务器上的 127.0.0.1:8000 无关服务保持不动，XWXTodo 同步服务使用独立端口。
