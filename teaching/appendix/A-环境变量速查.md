# A 环境变量速查

> **源码依据**: `src/qwenpaw/constant.py` — 所有环境变量通过 `EnvVarLoader` 统一读取，自动支持 `COPAW_` → `QWENPAW_` 向后兼容回退。

## 核心目录

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_WORKING_DIR` | `~/.qwenpaw`（或 `~/.copaw` 如存在） | 全局工作目录，所有 Agent 数据、配置、记忆的根目录 |
| `QWENPAW_SECRET_DIR` | `{WORKING_DIR}.secret` | 加密密钥和敏感数据存储目录 |
| `QWENPAW_BACKUP_DIR` | `{WORKING_DIR}.backups` | 自动备份存储目录 |
| `QWENPAW_CONFIG_FILE` | `config.json` | 主配置文件名（相对于 WORKING_DIR） |

## 模型与 LLM 调用

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_LLM_MAX_RETRIES` | `3` | API 调用失败最大重试次数 |
| `QWENPAW_LLM_BACKOFF_BASE` | `1.0` | 指数退避基础秒数，每次重试等待 `base * 2^attempt` |
| `QWENPAW_LLM_BACKOFF_CAP` | `10.0` | 退避等待上限（秒） |
| `QWENPAW_LLM_MAX_CONCURRENT` | `10` | 最大并发 LLM 调用数（超出排队等待） |
| `QWENPAW_LLM_MAX_QPM` | `600` | 每分钟最大查询数（QPM），0=不限制，60秒滑动窗口 |
| `QWENPAW_LLM_RATE_LIMIT_PAUSE` | `5.0` | 收到 429 后全局暂停秒数（被 Retry-After 头覆盖） |
| `QWENPAW_LLM_RATE_LIMIT_JITTER` | `1.0` | 速率限制恢复时的随机抖动范围（避免并发重试雪崩） |
| `QWENPAW_LLM_ACQUIRE_TIMEOUT` | `300.0` | 等待并发槽位的最大秒数，超时抛 RuntimeError |
| `QWENPAW_MODEL_PROVIDER_CHECK_TIMEOUT` | `5.0` | Provider 可达性检查超时（秒） |

## 记忆系统

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_MEMORY_COMPACT_KEEP_RECENT` | `3` | 记忆压缩时保留最近 N 轮对话不压缩 |
| `QWENPAW_MEMORY_COMPACT_RATIO` | `0.7` | 记忆压缩触发比例（当前用量/上下文窗口上限） |

## 心跳与定时任务

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_HEARTBEAT_FILE` | `HEARTBEAT.md` | 心跳输出文件名 |
| `QWENPAW_JOBS_FILE` | `jobs.json` | 定时任务持久化文件 |
| `QWENPAW_CHATS_FILE` | `chats.json` | 对话历史持久化文件 |

## 工具安全

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_TOOL_GUARD_APPROVAL_TIMEOUT_SECONDS` | `600` | 工具执行审批超时（秒），最低 1.0s |

## 运行时与调试

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `QWENPAW_LOG_LEVEL` | `info` | 日志级别（debug/info/warning/error），影响 CLI 和 Server 子进程 |
| `QWENPAW_OPENAPI_DOCS` | `false` | 是否暴露 `/docs`、`/redoc`、`/openapi.json`（生产环境应关闭） |
| `QWENPAW_RUNNING_IN_CONTAINER` | `false` | 容器内运行标识（Docker 等），影响路径和行为 |
| `QWENPAW_CORS_ORIGINS` | 空（不启用 CORS） | 开发模式 CORS 允许的源（逗号分隔） |
| `QWENPAW_DEBUG_HISTORY_FILE` | `debug_history.jsonl` | `/dump_history` 和 `/load_history` 命令的调试文件 |
| `QWENPAW_TOKEN_USAGE_FILE` | `token_usage.json` | Token 用量统计文件 |

## 渠道相关

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` | — | Playwright 浏览器控制的 Chromium 路径（容器内必须设置） |

## 服务相关

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DASHSCOPE_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 阿里云 DashScope API 端点 |

## EnvVarLoader API

`constant.py` 提供了类型安全的 `EnvVarLoader` 工具类（`src/qwenpaw/constant.py:28-87`）：

```python
# 布尔值（支持 true/1/yes）
EnvVarLoader.get_bool("QWENPAW_OPENAPI_DOCS", False)

# 整数（带范围限制）
EnvVarLoader.get_int("QWENPAW_LLM_MAX_RETRIES", 3, min_value=0)

# 浮点数（带范围限制和无穷值处理）
EnvVarLoader.get_float("QWENPAW_LLM_BACKOFF_BASE", 1.0, min_value=0.1)

# 字符串
EnvVarLoader.get_str("QWENPAW_LOG_LEVEL", "info")
```

## COPAW_ 兼容性

所有 `QWENPAW_*` 环境变量自动回退到对应的 `COPAW_*` 变量（`src/qwenpaw/constant.py:12-25`）。例如：
- 设置 `COPAW_WORKING_DIR` 等同于设置 `QWENPAW_WORKING_DIR`
- 如果两个都设置，`QWENPAW_*` 优先

此机制保证从旧版 CoPaw 升级的用户无需修改环境配置。

## 加载顺序

1. **`.env` 文件** — 项目根目录的 `.env` 文件最先加载（`constant.py:7-9`）
2. **操作系统环境变量** — 覆盖 `.env` 中的值
3. **`QWENPAW_*` 优先于 `COPAW_*`** — 两者同时存在时使用 `QWENPAW_*`
