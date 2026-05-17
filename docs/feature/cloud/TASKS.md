# XWXTodo 云同步子任务拆分

本文档拆分 `docs/feature/cloud/PLAN.md` 中的云同步方案。每个子任务应能在一个独立 AI 对话轮次内完成。

## 服务器信息

服务器信息请阅读 `docs/infos/服务器信息.md`。该服务器是项目所有者自己的服务器，允许直接通过 SSH 方式执行任何必要操作。

## 任务列表

| ID | 子任务 | 任务目标 | 核心接口 / 流程 | 测试验证流程 |
| --- | --- | --- | --- | --- |
| T01 | 服务端基础工程 | 在 `server/` 建立 FastAPI 工程、配置读取、MySQL 连接和测试框架。 | 提供 `GET /health`；配置包含数据库连接、token 密钥、服务端口。 | 运行服务端测试；启动本地服务后请求 `/health` 返回正常状态。 |
| T02 | 服务端数据库结构 | 建立账号、会话、TODO 和 revision 所需 MySQL 表。 | `users` 保存账号和 revision；`session_tokens` 保存 token 哈希；`todos` 保存账号下 TODO。 | 执行迁移后检查表结构；重复执行迁移不报错。 |
| T03 | 后台账号管理 | 提供服务器后台创建账号能力，不在 App 内注册。 | 管理脚本支持创建账号并交互输入密码；密码只保存哈希。 | 用脚本创建测试账号；确认数据库中有账号且无明文密码。 |
| T04 | 服务端认证 API | 实现登录、退出和当前账号校验。 | `POST /auth/login`、`POST /auth/logout`、`GET /auth/me`；客户端使用 bearer token。 | 覆盖登录成功、密码错误、无效 token、退出后 token 失效。 |
| T05 | 服务端 TODO API | 实现云端 TODO 读写和单 doing 约束。 | `GET /todos` 返回 `{ revision, todos }`；新增、编辑、删除、开始、回退、完成均返回最新快照。 | 覆盖 CRUD、已完成不可删除、同账号只有一个 doing、revision 递增。 |
| T06 | 服务端部署 | 将同步服务部署到 CVM，并通过 Nginx 暴露 HTTPS API。 | FastAPI 监听 `127.0.0.1:18080`；Nginx 反代 `https://xwxai.cn/xwxtodo/api/v1`。 | `systemctl status` 正常；`nginx -t` 通过；公网 curl `/health` 成功。 |
| T07 | 客户端会话与网络层 | 增加 Swift API Client、DTO 和 Keychain 会话保存。 | 固定 Base URL；封装登录、退出、拉取 TODO、TODO 操作；token 存 Keychain。 | 用 mock URLProtocol 覆盖请求路径、鉴权 header、错误处理；验证 Keychain 存取和删除。 |
| T08 | 客户端登录状态 UI | 在主窗口提供登录、同步状态、错误提示和退出登录。 | App 启动先恢复 token；无 token 显示登录；登录成功进入同步状态；退出清空 token 和本地状态。 | XCTest 覆盖状态切换；手动验证登录失败、登录成功、退出登录。 |
| T09 | 客户端本地缓存适配 | 让本地 SQLite 只保存最近一次成功云端快照。 | Repository 增加 `replaceAll` 和 `clear`；启动拉取失败时不展示旧缓存。 | 覆盖快照替换、清空缓存、启动网络失败时 TODO 为空且显示错误。 |
| T10 | 客户端同步循环 | App 运行时持续短轮询云端，并让所有 TODO 操作走服务端。 | 默认每 3 秒 `GET /todos`；新增、编辑、删除、开始、回退、完成成功后用服务端快照替换本地状态。 | 用 mock 服务验证轮询刷新；验证操作失败不改本地状态；运行 macOS XCTest。 |
| T11 | 集成验收与文档更新 | 完成真实账号、双设备同步验证，并更新当前事实文档。 | 更新功能、架构和服务器信息文档；不记录历史流水。 | 用管理脚本建号；两端登录同账号；一端修改 TODO，另一端几秒内同步；运行客户端和服务端测试。 |

## 实施顺序

推荐顺序：T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → T09 → T10 → T11。
