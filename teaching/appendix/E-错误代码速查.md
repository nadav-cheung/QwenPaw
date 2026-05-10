# E 错误代码速查

> **源码依据**: `src/qwenpaw/exceptions.py` — 所有业务异常定义和 LLM 错误转换逻辑。

## QwenPaw 业务异常

| 错误代码 | 异常类 | 说明 |
|----------|--------|------|
| `PROVIDER_ERROR` | `ProviderError` | LLM 提供商配置或调用错误 |
| `MODEL_FORMATTER_ERROR` | `ModelFormatterError` | 模型消息格式化失败（多模态适配、工具调用格式等） |
| `SYSTEM_COMMAND_ERROR` | `SystemCommandException` | `/compact`、`/new` 等系统命令执行失败 |
| `SKILLS_ERROR` | `SkillsError` | 技能加载、注册、扫描失败 |
| `AGENT_STATE_ERROR` | `AgentStateError` | Agent 会话状态异常（含 session_id） |
| — | `ChannelError(channel_name, message)` | 渠道通信错误（含渠道名称） |

## AgentScope 运行时异常

以下异常来自 `agentscope_runtime` 框架，QwenPaw 复用并通过 `convert_model_exception()` 转换：

| 错误代码 | 异常类 | 触发条件 |
|----------|--------|----------|
| — | `ModelExecutionException` | LLM API 调用通用失败 |
| — | `ModelTimeoutException` | LLM 调用超时 |
| — | `UnauthorizedModelAccessException` | API Key 无效或无权限 (HTTP 401/403) |
| — | `ModelQuotaExceededException` | API 配额耗尽或限流 (HTTP 429) |
| — | `ModelContextLengthExceededException` | 上下文超出模型窗口上限 |
| — | `UnknownAgentException` | 请求的目标 Agent 不存在 |
| — | `ExternalServiceException` | 外部服务（渠道等）通信失败 |
| — | `AgentRuntimeErrorException` | Agent 运行时通用错误基类 |

## LLM 异常自动转换

`convert_model_exception()` (`src/qwenpaw/exceptions.py:165-253`) 自动将 Provider SDK 原始异常转为 AgentScope 标准异常：

```
原始异常（openai.APIError / anthropic.APIStatusError / ...）
    │
    ├── _is_model_related_error()  ← 判断是否模型相关
    │
    ├── Level 1: HTTP 状态码映射
    │     401/403 → UnauthorizedModelAccessException
    │     429     → ModelQuotaExceededException
    │
    ├── Level 2: 错误消息关键词匹配
    │     "unauthorized" / "api key" → UnauthorizedModelAccessException
    │     "rate limit" / "quota"    → ModelQuotaExceededException
    │     "timeout" / "deadline"    → ModelTimeoutException
    │     "context" / "too many tokens" → ModelContextLengthExceededException
    │
    └── Level 3: 兜底
         模型相关 → ModelExecutionException
         非模型   → UnknownAgentException
```

## 常见故障排查

| 现象 | 可能异常 | 检查步骤 |
|------|----------|----------|
| 启动后 API 调用立即失败 | `UnauthorizedModelAccessException` | 1) `qwenpaw doctor` 检查 API Key 2) 检查环境变量 3) 检查 Provider 配额 |
| 长时间无响应后报错 | `ModelTimeoutException` | 1) 网络连通性 2) API 端点可达性 3) 增大超时配置 |
| 上下文过长时失败 | `ModelContextLengthExceededException` | 1) `/compact` 手动压缩记忆 2) 调整 `MEMORY_COMPACT_RATIO` |
| 高并发场景失败 | `ModelQuotaExceededException` | 1) 降低 `QWENPAW_LLM_MAX_CONCURRENT` 2) 降低 `QWENPAW_LLM_MAX_QPM` |
| 技能安装失败 | `SkillsError` | 1) 查看 `skill_scanner` 扫描报告 2) 检查 `SKILL.md` 格式 |
| 渠道收不到消息 | `ChannelError` | 1) `qwenpaw channels status` 2) Webhook URL 配置 3) 网络连通性 |

## 自定义异常处理

```python
from qwenpaw.exceptions import (
    ProviderError,
    SkillsError,
    SystemCommandException,
    ChannelError,
    AgentStateError,
)

try:
    await agent.process(message)
except ProviderError as e:
    logger.error(f"Provider error: {e.message}, details={e.details}")
except ChannelError as e:
    logger.error(f"Channel {e.service_name} error: {e.message}")
except AgentStateError as e:
    logger.error(f"Session {e.details['session_id']} error: {e.message}")
```

---

*基于源码 `src/qwenpaw/exceptions.py` (v1.1.2)*
*最后更新：2026-05-10*
