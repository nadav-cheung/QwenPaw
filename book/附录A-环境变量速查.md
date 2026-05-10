# 附录A：环境变量速查

所有环境变量均可通过 `.env` 文件、系统环境变量、`qwenpaw env set` 命令或 `envs.json` 持久化文件设置。

> **旧版兼容**：以 `QWENPAW_` 为前缀的变量会自动回退到 `COPAW_` 前缀。例如 `QWENPAW_WORKING_DIR` 未设置时会检查 `COPAW_WORKING_DIR`。

---

## 路径与目录

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `QWENPAW_WORKING_DIR` | str | `~/.qwenpaw`（若 `~/.copaw` 存在则使用旧路径） | 工作目录根路径，存放配置、会话、技能等所有运行时数据 |
| `QWENPAW_SECRET_DIR` | str | `{WORKING_DIR}.secret` | 密钥目录，存放加密的 `envs.json` |
| `QWENPAW_BACKUP_DIR` | str | `{WORKING_DIR}.backups` | 备份目录 |
| `QWENPAW_CONFIG_FILE` | str | `config.json` | 配置文件名（相对于 WORKING_DIR） |
| `QWENPAW_JOBS_FILE` | str | `jobs.json` | Cron 任务文件名 |
| `QWENPAW_CHATS_FILE` | str | `chats.json` | 聊天记录文件名 |
| `QWENPAW_TOKEN_USAGE_FILE` | str | `token_usage.json` | Token 用量文件名 |
| `QWENPAW_HEARTBEAT_FILE` | str | `HEARTBEAT.md` | 心跳查询文件名 |
| `QWENPAW_DEBUG_HISTORY_FILE` | str | `debug_history.jsonl` | 调试历史文件名 |

---

## 模型与 LLM 调用

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `QWENPAW_LLM_MAX_RETRIES` | int | `3` | LLM API 瞬态错误最大重试次数 |
| `QWENPAW_LLM_BACKOFF_BASE` | float | `1.0` | 指数退避基础延迟（秒） |
| `QWENPAW_LLM_BACKOFF_CAP` | float | `10.0` | 退避最大延迟上限（秒） |
| `QWENPAW_LLM_MAX_CONCURRENT` | int | `10` | 最大并发 LLM 请求数 |
| `QWENPAW_LLM_MAX_QPM` | int | `600` | 每分钟最大查询数（滑动窗口），0 表示不限 |
| `QWENPAW_LLM_RATE_LIMIT_PAUSE` | float | `5.0` | 收到 429 后全局暂停时间（秒） |
| `QWENPAW_LLM_RATE_LIMIT_JITTER` | float | `1.0` | 暂停后随机抖动范围（秒），防止并发雪崩 |
| `QWENPAW_LLM_ACQUIRE_TIMEOUT` | float | `300.0` | 获取信号量槽位的最大等待时间（秒） |
| `QWENPAW_MODEL_PROVIDER_CHECK_TIMEOUT` | float | `5.0` | Provider 连通性检查超时（秒） |
| `DASHSCOPE_BASE_URL` | str | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 阿里云 DashScope API 基础 URL |

---

## 安全与认证

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `QWENPAW_AUTH_ENABLED` | str | `""`（未启用） | Web 认证开关，设为 `true` 启用 |
| `QWENPAW_AUTH_USERNAME` | str | `""` | Web 登录用户名（首次启动时自动注册） |
| `QWENPAW_AUTH_PASSWORD` | str | `""` | Web 登录密码（首次启动时自动注册） |
| `QWENPAW_TOOL_GUARD_APPROVAL_TIMEOUT_SECONDS` | float | `600.0` | 工具防护审批超时（秒） |

---

## 运行时与容器

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `QWENPAW_LOG_LEVEL` | str | `info` | 日志级别：`critical`/`error`/`warning`/`info`/`debug`/`trace` |
| `QWENPAW_RUNNING_IN_CONTAINER` | bool | `false` | 是否运行在容器（如 Docker）内 |
| `QWENPAW_RELOAD_MODE` | str | `""` | 开发热重载模式标记（由 `--reload` 自动设置） |
| `QWENPAW_OPENAPI_DOCS` | bool | `false` | 是否暴露 `/docs`、`/redoc`、`/openapi.json`（仅开发用） |
| `QWENPAW_CORS_ORIGINS` | str | `""` | CORS 允许的来源，逗号分隔，如 `http://localhost:5173` |

---

## 记忆与压缩

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `QWENPAW_MEMORY_COMPACT_KEEP_RECENT` | int | `3` | 记忆压缩时保留的最近轮次数 |
| `QWENPAW_MEMORY_COMPACT_RATIO` | float | `0.7` | 记忆压缩触发比例 |

---

## 浏览器与前端

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` | str | `""` | Playwright 使用的 Chromium 路径（Docker 中设置系统 Chromium） |

---

## 外部服务 API Key

以下变量通常通过 `qwenpaw env set` 或 `.env` 文件配置，供 MCP 客户端和技能使用。

| 变量名 | 说明 |
|--------|------|
| `TAVILY_API_KEY` | Tavily 搜索 MCP 客户端 API Key，设置后自动启用 |
| `DASHSCOPE_API_KEY` | 阿里云 DashScope API Key |
| `OPENAI_API_KEY` | OpenAI 兼容 Provider 的 API Key |
| `ANTHROPIC_API_KEY` | Anthropic Provider 的 API Key |
