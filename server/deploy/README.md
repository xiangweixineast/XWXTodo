# XWXTodo 服务端部署

生产部署使用 systemd 管理 FastAPI，并通过 Nginx 暴露 HTTPS API：

```text
https://xwxai.cn/xwxtodo/api/v1 -> http://127.0.0.1:18080
```

## 服务器路径

- 代码目录：`/opt/xwxtodo/server`
- 环境文件：`/etc/xwxtodo/xwxtodo.env`
- systemd unit：`/etc/systemd/system/xwxtodo.service`
- Nginx 站点：`/etc/nginx/sites-available/xwxtodo`

## 部署要点

1. 用 `rsync` 同步本地 `server/` 到 `/opt/xwxtodo/server`，排除 `.venv`、`.env`、缓存和 `__pycache__`。
2. 在服务器创建 `.venv`，安装 `requirements.txt`。
3. 在 `/etc/xwxtodo/xwxtodo.env` 写入 `XWXTODO_DATABASE_URL`、`XWXTODO_TOKEN_SECRET`、`XWXTODO_HOST=127.0.0.1`、`XWXTODO_PORT=18080`。
4. 执行 `python -m app.migrate` 创建或更新表结构。
5. 启用 `xwxtodo.service` 和 Nginx 站点。

## 验证

```bash
systemctl status xwxtodo
sudo nginx -t
curl http://127.0.0.1:18080/health
curl https://xwxai.cn/xwxtodo/api/v1/health
```
