# 附录D：错误代码速查

QwenPaw 的异常体系建立在 `agentscope_runtime` 引擎的基础异常类之上，通过错误代码（error code）标识不同类型的故障。

---

## 核心业务异常

定义在 `src/qwenpaw/exceptions.py`。

| 错误代码 | 异常类 | 父类 | 说明 |
|---------|--------|------|------|
| `PROVIDER_ERROR` | `ProviderError` | `AgentRuntimeErrorException` | Provider 通信或配置错误 |
| `MODEL_FORMATTER_ERROR` | `ModelFormatterError` | `AgentRuntimeErrorException` | 模型消息格式化失败 |
| `SYSTEM_COMMAND_ERROR` | `SystemCommandException` | `AgentRuntimeErrorException` | 系统命令执行失败 |
| `AGENT_STATE_ERROR` | `AgentStateError` | `AgentRuntimeErrorException` | Agent 状态或会话错误 |
| `SKILLS_ERROR` | `SkillsError` | `AgentRuntimeErrorException` | 技能管理错误 |
| — | `ChannelError` | `ExternalServiceException` | 频道通信错误，附带 `channel` 和 `channel_name` 详情 |

---

## LLM API 异常转换

`convert_model_exception()` 函数将第三方 LLM SDK 异常自动转换为标准异常。转换规则如下：

### 按 HTTP 状态码

| 状态码 | 目标异常 | 说明 |
|--------|---------|------|
| `401` / `403` | `UnauthorizedModelAccessException` | 认证失败或无权访问 |
| `429` | `ModelQuotaExceededException` | 请求配额超限（频率限制） |

### 按错误消息关键词

| 关键词 | 目标异常 | 说明 |
|--------|---------|------|
| `unauthorized` / `authentication` / `api key` / `invalid key` / `forbidden` | `UnauthorizedModelAccessException` | 认证相关问题 |
| `rate limit` / `quota` / `too many requests` | `ModelQuotaExceededException` | 配额/频率限制 |
| `timeout` / `timed out` / `deadline exceeded` | `ModelTimeoutException` | 请求超时 |
| `context` / `maximum context` / `context window` / `too many tokens` | `ModelContextLengthExceededException` | 上下文长度超限 |

### 兜底

| 条件 | 目标异常 | 说明 |
|------|---------|------|
| 模型相关但无精确匹配 | `ModelExecutionException` | 通用模型执行错误 |
| 非模型相关错误 | `UnknownAgentException` | 包装原始异常 |

---

## 模块级异常

### ACP 协议 (`agents/acp/core.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `ACPErrors` | `Exception` | ACP 异常基类 |
| `ACPConfigurationError` | `ACPErrors` | ACP 配置错误 |
| `ACPTransportError` | `ACPErrors` | 传输层错误 |
| `ACPProtocolError` | `ACPErrors` | 协议格式错误 |
| `ACPSessionError` | `ACPErrors` | 会话管理错误 |

### 命令执行 (`utils/command_runner.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `CommandExecutionError` | `RuntimeError` | 命令执行失败 |
| `ProcessLaunchError` | `RuntimeError` | 进程启动失败 |

### 技能系统 (`agents/skills_hub.py`, `agents/skills_manager.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `SkillImportCancelled` | `RuntimeError` | 技能导入被取消 |
| `SkillConflictError` | `RuntimeError` | 技能名称冲突 |

### 技能安全扫描 (`security/skill_scanner/`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `SkillScanError` | `Exception` | 技能安全扫描检测到风险 |

### 备份系统 (`backup/models.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `BackupConflictError` | `Exception` | 备份版本冲突 |

### QQ 频道 (`app/channels/qq/channel.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `QQApiError` | `RuntimeError` | QQ API 调用错误 |

### Telegram 频道 (`app/channels/telegram/channel.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `_FileTooLargeError` | `Exception` | 文件超过大小限制 |
| `_MediaFileUnavailableError` | `Exception` | 媒体文件不可用 |

### Mission 模式 (`agents/mission/mission_runner.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `PrdValidationError` | `ValueError` | 任务描述验证失败 |

### 守护进程 (`app/runner/daemon_commands.py`)

| 异常类 | 父类 | 说明 |
|--------|------|------|
| `RestartInProgressError` | `Exception` | 重启已在进行中 |

---

## 配置验证错误

通过 `agentscope_runtime.engine.schemas.exception.ConfigurationException` 抛出，常见触发场景：

| 场景 | config_key | 说明 |
|------|-----------|------|
| MCP stdio 客户端缺少 command | `mcp.command` | stdio 传输类型必须有 command |
| MCP 远程客户端缺少 url | `mcp.url` | `streamable_http`/`sse` 传输类型必须有 url |
| LLM 退避参数不合理 | `llm_backoff` | `llm_backoff_cap` 必须大于等于 `llm_backoff_base` |

---

## Agent ID 验证错误

由 `validate_agent_id()` 抛出的 `ValueError`：

| 条件 | 说明 |
|------|------|
| 长度 < 2 | Agent ID 至少 2 个字符 |
| 长度 > 64 | Agent ID 最多 64 个字符 |
| 包含非法字符 | 仅允许字母、数字、连字符、下划线，不能以 `-` 或 `_` 开头/结尾 |
| 使用保留 ID | `default` 为保留 ID，不可使用 |
| ID 已存在 | 同名 Agent 已注册 |
