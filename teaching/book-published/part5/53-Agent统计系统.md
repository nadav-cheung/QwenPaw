# 53 Agent 统计系统

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 理解 Token 使用量的追踪机制 2) 分析统计数据的存储和查询 3) 配置用量限制和告警 |
| **前置知识** | [07-智能体核心架构](./07-智能体核心架构.md)、[11-Model系统与LLM提供商](./11-Model系统与LLM提供商.md) |
| **预计时长** | 25 分钟（阅读 20 分钟 + 练习 5 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `统计` `Token` `用量` |

> **一句话概述**：本章讲解 QwenPaw 的 Agent 统计系统架构，包括会话文件的解析聚合流程、多维度统计模型和 Token 使用追踪机制，帮助读者掌握用量监控和成本分析方法。

## 概述

QwenPaw 的 Agent 统计系统（agent_stats）提供智能体的使用统计功能，包括消息计数、Token 消耗、工具调用频率等指标。统计服务通过分析会话历史文件计算聚合数据，支持按日期范围和渠道筛选。

`★ Insight ─────────────────────────────────────`
- **统计即代码**：将统计计算逻辑放在服务层而非数据库层，通过解析 JSON 会话文件实时聚合
- **懒加载模式**：使用生成器按需读取会话文件，避免一次性加载所有数据
- **分层统计**：支持按日期、渠道、会话多个维度聚合，提供灵活的查询能力
`─────────────────────────────────────────────────`

**源码路径**：`src/qwenpaw/agent_stats/`

---

## 1. 核心数据模型

### 1.1 AgentStatsSummary

**源码路径**：`src/qwenpaw/agent_stats/models.py:30`

```python
class AgentStatsSummary(BaseModel):
    total_active_sessions: int      # 总活跃会话数
    total_messages: int             # 总消息数
    total_user_messages: int       # 用户消息数
    total_assistant_messages: int   # 助手消息数
    total_prompt_tokens: int       # Prompt Token 总数
    total_completion_tokens: int   # Completion Token 总数
    total_llm_calls: int           # LLM 调用总次数
    total_tool_calls: int          # 工具调用总次数
    by_date: list[DailyStats]      # 按日期聚合的统计
    channel_stats: list[ChannelStats]  # 按渠道聚合的统计
    start_date: str                # 统计起始日期
    end_date: str                  # 统计结束日期
```

### 1.2 DailyStats

**源码路径**：`src/qwenpaw/agent_stats/models.py:17`

```python
class DailyStats(BaseModel):
    date: str                      # 日期 (YYYY-MM-DD)
    chats: int                     # 当日会话数
    active_sessions: int           # 当日活跃会话数
    user_messages: int             # 当日用户消息数
    assistant_messages: int        # 当日助手消息数
    total_messages: int           # 当日总消息数
    prompt_tokens: int             # 当日 Prompt Token
    completion_tokens: int        # 当日 Completion Token
    llm_calls: int                # 当日 LLM 调用次数
    tool_calls: int               # 当日工具调用次数
```

### 1.3 ChannelStats

**源码路径**：`src/qwenpaw/agent_stats/models.py:9`

```python
class ChannelStats(BaseModel):
    channel: str                    # 渠道名称 (如 "console", "telegram")
    session_count: int             # 该渠道会话数
    user_messages: int             # 该渠道用户消息数
    assistant_messages: int        # 该渠道助手消息数
    total_messages: int           # 该渠道总消息数
```

---

## 2. AgentStatsService

**源码路径**：`src/qwenpaw/agent_stats/service.py:70`

### 2.1 类定义

```python
class AgentStatsService:
    """Service for computing agent statistics."""

    async def get_summary(
        self,
        workspace_dir: Path,
        start_date: date,
        end_date: date,
    ) -> AgentStatsSummary:
        """获取指定日期范围的统计摘要。

        Args:
            workspace_dir: 工作区目录
            start_date: 统计起始日期
            end_date: 统计结束日期

        Returns:
            AgentStatsSummary: 聚合统计数据
        """
```

### 2.2 核心方法

| 方法 | 说明 | 源码行 |
|------|------|--------|
| `get_summary()` | 获取指定日期范围的统计 | `service.py:75` |
| `_process_session_file()` | 处理单个会话文件 | `service.py:28` |

---

## 3. 统计计算流程

### 3.1 统计入口

```python
async def get_summary(
    workspace_dir: Path,
    start_date: date,
    end_date: date,
) -> AgentStatsSummary:
    """获取 Agent 统计信息"""
```

### 3.2 会话文件处理

```python
# src/qwenpaw/agent_stats/service.py:28
def _process_session_file(
    session_data: dict,
    start_date_str: str,
    end_date_str: str,
    daily_stats: dict[str, dict],
    channel_stats: dict[str, dict],
    channel: str,
    session_stem: str,
    active_sessions: dict[str, set[str]],
) -> tuple[int, bool]:
    """处理单个会话文件，返回 (工具调用数, 是否有范围内消息)"""
```

**处理步骤**：

1. 解析会话文件中的 `agent.memory.memories` 或 `agent.memory.content`
2. 按时间戳筛选日期范围内的消息
3. 统计各类指标（消息数、Token数等）
4. 更新 daily_stats 和 channel_stats

### 3.3 统计维度

| 维度 | 说明 | 数据来源 |
|------|------|----------|
| 日期 | 按天聚合 | 消息 timestamp |
| 渠道 | 按 channel 聚合 | session 文件名 |
| 会话 | 单个会话统计 | session_stem |

---

## 4. Token 使用统计

**源码路径**：`src/qwenpaw/token_usage/`

Token 使用统计与 Agent 统计系统互补，提供更细粒度的 Token 消耗追踪。

### 4.1 TokenUsageRecord

```python
class TokenUsageRecord(BaseModel):
    timestamp: datetime
    model: str
    provider: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    duration_ms: int
```

### 4.2 TokenUsageStats

```python
class TokenUsageStats(BaseModel):
    total_prompt_tokens: int
    total_completion_tokens: int
    total_tokens: int
    by_model: dict[str, TokenUsageByModel]
    by_provider: dict[str, TokenUsageByModel]
```

### 4.3 TokenRecordingModelWrapper

**源码路径**：`src/qwenpaw/token_usage/model_wrapper.py:12`

```python
class TokenRecordingModelWrapper:
    """包装 ChatModel 以记录 Token 使用量"""

    def __init__(self, provider_id: str, model: ChatModelBase):
        self.provider_id = provider_id
        self._model = model
        self._usage_records: list[TokenUsageRecord] = []
```

---

## 5. API 端点

### 5.1 统计相关端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/agents/{agent_id}/stats` | GET | 获取 Agent 统计 |
| `/api/agents/{agent_id}/stats/date` | GET | 按日期范围查询 |

### 5.2 请求参数

```python
# 查询参数
start_date: str  # YYYY-MM-DD，可选
end_date: str    # YYYY-MM-DD，可选
channel: str     # 渠道筛选，可选
```

### 5.3 响应示例

```json
{
  "total_active_sessions": 42,
  "total_messages": 1234,
  "total_user_messages": 617,
  "total_assistant_messages": 617,
  "total_prompt_tokens": 456789,
  "total_completion_tokens": 123456,
  "total_llm_calls": 234,
  "total_tool_calls": 567,
  "by_date": [...],
  "channel_stats": [
    {"channel": "console", "session_count": 30, "total_messages": 800},
    {"channel": "telegram", "session_count": 12, "total_messages": 434}
  ],
  "start_date": "2026-04-01",
  "end_date": "2026-04-30"
}
```

---

## 6. 使用场景

### 场景一：月度使用报告

```python
from qwenpaw.agent_stats import AgentStatsService
from datetime import date, timedelta

# 获取本月统计
today = date.today()
start = today.replace(day=1)
stats = await AgentStatsService().get_summary(
    workspace_dir=workspace_dir,
    start_date=start,
    end_date=today,
)

print(f"本月消息数: {stats.total_messages}")
print(f"本月 Token 消耗: {stats.total_prompt_tokens + stats.total_completion_tokens}")
```

### 场景二：渠道分析

```python
# 按渠道分组统计
stats = await service.get_summary(
    workspace_dir=workspace_dir,
    start_date=start_date,
    end_date=end_date,
)

for channel_stat in stats.channel_stats:
    print(f"{channel_stat.channel}: {channel_stat.session_count} 会话, "
          f"{channel_stat.total_messages} 消息")
```

### 场景三：Token 成本分析

```python
# 分析 Token 使用趋势
from collections import defaultdict

daily_tokens = defaultdict(int)
for daily in stats.by_date:
    daily_tokens[daily.date] = daily.total_prompt_tokens + daily.total_completion_tokens

# 找出 Token 消耗最高的日子
top_days = sorted(daily_tokens.items(), key=lambda x: x[1], reverse=True)[:5]
```

---

## 7. 最佳实践

### 7.1 定期归档旧会话

```python
# 会话文件过多会影响统计性能
# 建议定期归档超过30天的会话
import shutil
from datetime import date, timedelta

old_threshold = date.today() - timedelta(days=30)
archive_dir = workspace_dir / "sessions_archive"
archive_dir.mkdir(exist_ok=True)

for session_file in sessions_dir.glob("*.json"):
    if session_file.stat().st_mtime < old_threshold.timestamp():
        shutil.move(session_file, archive_dir / session_file.name)
```

### 7.2 缓存统计结果

```python
from functools import lru_cache

@lru_cache(maxsize=128)
async def get_cached_stats(
    start_date: str,
    end_date: str,
) -> AgentStatsSummary:
    """带缓存的统计查询"""
    return await service.get_summary(
        workspace_dir=workspace_dir,
        start_date=date.fromisoformat(start_date),
        end_date=date.fromisoformat(end_date),
    )
```

### 7.3 并行处理会话文件

```python
import asyncio
from pathlib import Path

async def get_stats_parallel(workspace_dir: Path) -> AgentStatsSummary:
    session_files = list(workspace_dir.glob("sessions/*.json"))

    # 并行处理会话文件
    tasks = [
        process_file(file)
        for file in session_files
    ]
    results = await asyncio.gather(*tasks)

    # 聚合结果
    return aggregate_results(results)
```

---

## 8. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| 数据模型 | `src/qwenpaw/agent_stats/models.py` |
| 统计服务 | `src/qwenpaw/agent_stats/service.py` |
| Token 使用 | `src/qwenpaw/token_usage/manager.py` |
| Token 记录 | `src/qwenpaw/token_usage/model_wrapper.py` |
| 会话仓储 | `src/qwenpaw/app/runner/repo/json_repo.py` |
| 会话管理 | `src/qwenpaw/app/runner/session.py` |

---

## 9. 总结

**核心要点**：

1. **统计维度**：AgentStatsService 提供按日期、渠道、会话的多维统计
2. **数据来源**：通过解析 JSON 会话文件实时聚合，无需独立存储
3. **Token 追踪**：TokenRecordingModelWrapper 包装模型，自动记录 Token 消耗
4. **懒加载**：使用生成器按需读取会话文件，避免一次性内存压力

**适用场景**：
- 生成使用报告和成本分析
- 监控 Agent 活跃度和消息量
- 分析 Token 消耗趋势
- 渠道效果对比

---

## 🐍 来自 Java 的你

### 核心概念对照

| Java | Python / QwenPaw | 说明 |
|------|-------------------|------|
| Micrometer | Agent 统计 (AgentStatsService) | Micrometer 通过 MeterRegistry 收集指标；QwenPaw 通过 AgentStatsService 聚合每日/渠道统计 |
| MeterRegistry | StatsManager | MeterRegistry 是指标注册中心；QwenPaw 的统计管理由 StatsManager 协调各统计服务 |
| @Timed | Token 追踪 (TokenRecordingModelWrapper) | @Timed 注解在方法级别计时；QwenPaw 通过模型包装器透明拦截每次调用并记录 Token |
| Prometheus + Grafana | 内置统计面板 | Java 生态通常外挂 Prometheus 采集 + Grafana 展示；QwenPaw 将统计直接内嵌在服务中 |
| Counter / Gauge | token_count / input_tokens | Micrometer 的 Counter 递增计数、Gauge 实时快照；QwenPaw 直接在统计模型中记录 Token 维度 |

### 关键差异

Java 生态的监控指标通常通过独立的时序数据库（Prometheus、InfluxDB）存储和查询，而 QwenPaw 将统计数据持久化在本地数据库中，无需额外基础设施。Token 维度的统计在 Java 应用中需要手动埋点，而 QwenPaw 通过模型包装器实现了自动化的 Token 透明追踪。

---

## 知识检查

1. AgentStatsService 的统计数据来源是什么？它是通过数据库查询还是文件解析实现的？

2. DailyStats 和 ChannelStats 两个聚合维度分别解决什么分析需求？它们的统计字段有哪些差异？

3. TokenRecordingModelWrapper 如何实现对 Token 消耗的透明追踪？它包装的是什么对象？

---

## 10. Contributor 指南

### 10.1 适合新手修改的文件

| 文件 | 难度 | 原因 |
|------|------|------|
| `agent_stats/stats_manager.py` 的统计聚合 | ⭐⭐ | 相对独立的统计逻辑 |
| `agent_stats/models.py` 的数据模型 | ⭐ | 纯粹的 Pydantic 模型 |
| `providers/token_recording.py` 的包装逻辑 | ⭐⭐ | 需要理解模型调用链 |

### 10.2 危险区域（绝对不要轻易修改）

| 文件/模块 | 危险原因 |
|-----------|----------|
| `providers/token_recording.py` 的 Token 记录 | 错误会导致统计失真 |
| `agent_stats/service.py` 的统计聚合算法 | 错误会导致统计数据错误 |
| `agent_stats/db.py` 的数据库操作 | 错误会导致数据丢失 |

### 10.3 调试方法

**测试 Token 记录**
```python
from qwenpaw.providers.token_recording import TokenRecordingModelWrapper

# 创建包装器
wrapper = TokenRecordingModelWrapper(inner_model)
response = await wrapper.chat([{"role": "user", "content": "hello"}])
print(f"Tokens recorded: {wrapper.total_tokens}")
```

**测试统计聚合**
```python
from qwenpaw.agent_stats import StatsManager

manager = StatsManager.get_instance()
stats = await manager.get_daily_stats("2024-01-01")
print(f"Total tokens: {stats.total_tokens}")
```

**测试数据库操作**
```python
from qwenpaw.agent_stats.db import StatsDatabase

db = StatsDatabase()
await db.save_stats(stats)
print("Stats saved")
```

### 10.4 如何避免破坏架构

**Token 记录原则**：
- TokenRecordingModelWrapper 必须在最内层（直接包装原始模型）
- 必须正确记录 input_tokens 和 output_tokens
- 必须处理流式和非流式两种响应

**统计聚合原则**：
- DailyStats 和 ChannelStats 必须独立聚合
- 统计数据必须持久化到数据库
- 统计查询必须支持时间范围筛选

**测试要求**：
- Token 记录必须测试流式和非流式
- 统计聚合必须测试多维度聚合
- 数据库必须测试并发写入

---

## 延伸阅读

- [11-Model系统与LLM提供商](11-Model系统与LLM提供商.md) -- Token 统计的上游，理解模型调用如何产生 Token 消耗
- [90-健康检查与监控](90-健康检查与监控.md) -- 将统计数据纳入监控告警体系，实现用量异常自动检测
