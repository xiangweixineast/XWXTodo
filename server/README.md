# XWXTodo Sync Server

服务端使用 FastAPI + MySQL，包含基础配置、数据库连通性检查、表迁移和后台账号管理。

## 本地安装

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

编辑 `.env`，填入真实 MySQL 连接和 token 密钥。

## 运行测试

默认测试不依赖真实 MySQL。

```bash
cd server
source .venv/bin/activate
pytest
```

## 启动服务

```bash
cd server
source .venv/bin/activate
python -m app.main
```

## 后台创建账号

```bash
cd server
source .venv/bin/activate
python -m app.admin create-user <username>
```

密码通过终端隐藏输入并二次确认；数据库只保存密码哈希。

## 健康检查

```bash
curl http://127.0.0.1:18080/health
```

成功响应：

```json
{"status":"ok","database":"ok"}
```
