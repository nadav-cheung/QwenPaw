# 请求处理与 Runner：QwenPaw 核心引擎

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 追踪请求从入口到响应的完整链路 2) 理解命令路由和技能注入机制 3) 分析 SSE 流式输出的实现 |
| **前置知识** | [07-智能体核心架构](./07-智能体核心架构.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 50 分钟（阅读 35 + 练习 15） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `AgentRunner` `命令路由` `SSE` `技能注入` |

> **一句话概述**：AgentRunner 是 QwenPaw 的请求处理引擎，通过 12 阶段清晰分离实现工具审批、三层命令路由、热重载 Agent 实例化和 TaskTracker SSE 断线重连。

## 概述

Runner 是 QwenPaw 的请求处理引擎，负责接收用户查询、协调 Agent、执行工具、返回流式响应，并管理会话生命周期。本文深入分析 Runner 的架构设计、请求生命周期和关键设计模式。

**源码路径**: `src/qwenpaw/app/runner/`

**核心文件**:

| 文件 | 职责 |
|------|------|
| `runner.py` | AgentRunner 核心类，900+ 行，请求处理引擎 |
| `models.py` | Pydantic 数据模型：ChatSpec, ChatUpdate, ChatHistory |
| `session.py` | SafeJSONSession — 异步 JSON 文件会话状态持久化 |
| `command_dispatch.py` | 命令路由：daemon > control > conversation |
| `mission_dispatch.py` | /mission 命令检测与分发 |
| `task_tracker.py` | SSE 流式输出、后台任务追踪、断线重连缓冲 |
| `control_commands/` | /stop, /model, /skills 命令处理器 |
| `daemon_commands.py` | /daemon 子命令处理器 |

---

## 1. AgentRunner 核心类

### 1.1 类定义与继承关系

```python
# src/qwenpaw/app/runner/runner.py:130
class AgentRunner(Runner):  # 继承自 agentscope_runtime.engine.runner.Runner
    def __init__(
        self,
        agent_id: str = "default",
        workspace_dir: Path | None = None,
        task_tracker: Any | None = None,
    ) -> None:
```

### 1.2 关键辅助函数

**`_get_last_user_text`** (`command_dispatch.py:33-48`):

从运行时消息列表中提取最后一条用户消息的文本内容：

```python
def _get_last_user_text(msgs) -> str | None:
    """Extract last user message text from msgs (runtime message list)."""
    if not msgs or len(msgs) == 0:
        return None
    last = msgs[-1]
    if hasattr(last, "get_text_content"):
        return last.get_text_content()
    if isinstance(last, dict):
        content = last.get("content") or last.get("text")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    return block.get("text")
    return None
```

**`_is_approval`** (`runner.py:119-127`):

判断文本是否为审批确认（仅当文本恰好是 `approve`、`/approve` 或 `/daemon approve` 时返回 True）：

```python
def _is_approval(text: str) -> bool:
    normalized = " ".join(text.split()).lower()
    return normalized in _APPROVE_EXACT  # frozenset{"approve", "/approve", "/daemon approve"}
```

**`_stream_printing_messages_interruptible`** (`runner.py:79-116`):

可中断的流式消息输出函数，内部使用 `asyncio.Queue` 传递消息，支持外部取消时立即取消 Agent 任务：

```python
async def _stream_printing_messages_interruptible(
    *,
    agents: list[Any],
    coroutine_task: Coroutine[Any, Any, Msg],
) -> AsyncGenerator[tuple[Msg, bool], None]:
    queue: asyncio.Queue = asyncio.Queue()
    for agent in agents:
        agent.set_msg_queue_enabled(True, queue)
    task = asyncio.create_task(coroutine_task)
    if task.done():
        await queue.put(_PRINT_END_SIGNAL)
    else:
        task.add_done_callback(lambda _: queue.put_nowait(_PRINT_END_SIGNAL))
    try:
        while True:
            printing_msg = await queue.get()
            if isinstance(printing_msg, str) and printing_msg == _PRINT_END_SIGNAL:
                break
            msg, last, _ = printing_msg
            yield msg, last
        exception = task.exception()
        if exception is not None:
            raise exception from None
    except asyncio.CancelledError:
        await _cancel_streaming_agent_task(task)
        raise
    finally:
        await _cancel_streaming_agent_task(task)
```

Runner 继承自 `agentscope_runtime.engine.runner.Runner`，这是 agentscope 运行时提供的基类。AgentRunner 在此基础上扩展了 QwenPaw 特有的功能：

- **热重载支持**: 每次请求新建 Agent 实例，即时加载最新配置
- **三层命令路由**: daemon > control > conversation 优先级体系
- **会话自动注册**: 与 ChatManager 集成，自动创建/更新会话记录
- **MCP 客户端管理**: 通过 MCPManager 支持 MCP 服务器热重载
- **任务追踪**: 集成 TaskTracker 进行 SSE 流式输出和后台任务管理

### 1.2 核心属性

```python
# runner.py:130-150
class AgentRunner(Runner):
    def __init__(...):
        super().__init__()
        self.framework_type = "agentscope"
        self.agent_id = agent_id          # Agent ID，用于加载配置
        self.workspace_dir = workspace_dir # 工作目录，用于 prompt 构建
        self._chat_manager = None         # ChatManager 实例引用
        self._mcp_manager = None          # MCPClientManager 实例引用
        self._workspace = None             # Workspace 实例，用于控制命令
        self.memory_manager = None         # BaseMemoryManager 实例
        self._task_tracker = task_tracker # TaskTracker 实例
```

### 1.3 技能解析函数

**`_parse_skill_query`** (`runner.py:173-205`):

解析技能命令的两种格式：

```python
@staticmethod
def _parse_skill_query(query: str) -> tuple[str, str] | None:
    """Parse ``/name [input]`` or ``/[name with spaces] [input]``."""
    # 两种格式：
    # /[skill name] input — bracket form，处理名称中的空格
    # /name input — plain form
```

**`_maybe_inject_skill`** (`runner.py:207-281`):

处理 `/<skill_name> [input]` 或 `/[skill name] [input]` 格式的命令：

```python
@staticmethod
def _maybe_inject_skill(
    query: str | None,
    msgs: list,
    skills: dict,
) -> Msg | None:
    """Handle ``/<skill_name> [input]`` or ``/[skill name] [input]``."""
    # 1. 解析命令格式
    # 2. 查找技能（按文件夹名称匹配）
    # 3. 无输入 → 返回技能信息
    # 4. 有输入 → 将技能体合并到用户消息，返回 None 继续 LLM 处理
```

### 1.4 依赖注入方法

AgentRunner 通过依赖注入接收各组件引用：

```python
# runner.py:152-175
def set_chat_manager(self, chat_manager):
    """Set chat manager for auto-registration."""
    self._chat_manager = chat_manager

def set_mcp_manager(self, mcp_manager):
    """Set MCP client manager for hot-reload support."""
    self._mcp_manager = mcp_manager

def set_workspace(self, workspace):
    """Set workspace for control command handlers."""
    self._workspace = workspace
```

这种设计实现了：
- **依赖倒置**: Runner 不直接创建依赖，而是由外部注入
- **可测试性**: 便于在测试中注入 mock 组件
- **生命周期管理**: 各组件由外部统一管理，Runner 按需使用

---

## 2. 请求生命周期：query_handler 详解

`query_handler` 是 Runner 的核心方法，完整处理一次用户请求。以下是 12 个阶段的详细分析。

### Stage 1: 工具守卫审批检查 (lines 421-437)

**目的**: 检查是否有待审批的工具调用请求

```python
# runner.py:419-437
(
    approval_response,
    approval_consumed,
    approved_tool_call,
) = await self._resolve_pending_approval(session_id, query)
if approval_response is not None:
    yield approval_response, True
    user_id = getattr(request, "user_id", "") or ""
    await self._cleanup_denied_session_memory(
        session_id,
        user_id,
        denial_response=approval_response,
    )
    return
```

**关键逻辑**:
- 调用 `_resolve_pending_approval()` 检查审批队列
- 三种返回情况：
  - `(None, False, None)`: 无待审批，继续正常流程
  - `(Msg, True, None)`: 拒绝，yield 拒绝消息并清理内存
  - `(None, True, dict)`: 批准，包含批准的工具调用信息

**超时处理**: 审批超时时间默认 `TOOL_GUARD_APPROVAL_TIMEOUT_SECONDS`，超时自动拒绝

### Stage 2: 命令路由 (lines 439-443)

**目的**: 判断是否为命令，优先进入命令处理路径

```python
# runner.py:439-443
if not approval_consumed and query and _is_command(query):
    logger.info("Command path: %s", query.strip()[:50])
    async for msg, last in run_command_path(request, msgs, self):
        yield msg, last
    return
```

**命令检测**: `_is_command()` 判断逻辑见 command_dispatch.py

```python
# command_dispatch.py:65-76
def _is_command(query: str | None) -> bool:
    """True if query is any known command.

    Priority order: daemon > control > conversation
    """
    if not query or not query.startswith("/"):
        return False
    if parse_daemon_query(query) is not None:
        return True
    if _is_control_command(query):
        return True
    return _is_conversation_command(query)
```

**三层优先级**: daemon > control > conversation

### Stage 3: Agent 上下文设置 (lines 445-459)

**目的**: 设置 contextvars，供模型创建和 token 追踪使用

```python
# runner.py:445-459
# Set agent context for model creation
from ..agent_context import (
    set_current_agent_id,
    set_current_session_id,
)

set_current_agent_id(self.agent_id)

# Set session_id in context for token usage tracking
set_current_session_id(session_id)
```

**contextvars 机制**: 使用 Python 的 contextvars 模块在异步上下文中传递请求级别的信息，避免层层传递参数。

### Stage 4: Agent 构建准备 (lines 460-603)

**目的**: 收集 Agent 运行所需的所有上下文信息

### 4.1 环境上下文构建

```python
# runner.py:461-467
env_context = build_env_context(
    session_id=session_id,
    user_id=user_id,
    channel=channel,
    working_dir=(
        str(self.workspace_dir)
        if self.workspace_dir
        else str(WORKING_DIR)
    ),
)
```

环境上下文字符串包含：session/user/channel/OS/date/timezone 等信息，用于 system prompt。

### 4.2 MCP 客户端获取

```python
# runner.py:469-472
mcp_clients = []
if self._mcp_manager is not None:
    mcp_clients = await self._mcp_manager.get_clients()
```

从 MCPManager 获取当前可用的 MCP 客户端列表，支持热重载。

### 4.3 Agent 配置加载

```python
# runner.py:475
agent_config = load_agent_config(self.agent_id)
```

加载 Agent 特定配置，与 MCP 客户端一样支持热重载。

### 4.4 请求上下文构建

```python
# runner.py:477-492
base_request_context = {
    "session_id": session_id,
    "user_id": user_id,
    "channel": channel,
    "agent_id": self.agent_id,
    **(
        {
            "forced_tool_call_json": json.dumps(
                approved_tool_call,
                ensure_ascii=False,
            ),
        }
        if approved_tool_call
        else {}
    ),
}

# Merge custom request_context from request
custom_context = getattr(request, "request_context", None)
if custom_context and isinstance(custom_context, dict):
    base_request_context.update(custom_context)
```

### Stage 5: Mission Mode 检测 (lines 529-592)

**目的**: 检测并处理 /mission 命令或活跃的 mission phase

```python
# runner.py:529-549
mission_result = await maybe_handle_mission_command(
    query=query,
    msgs=msgs,
    workspace_dir=_ws,
    agent_id=self.agent_id,
    rewrite_fn=self._rewrite_last_message_text,
    session_id=session_id,
)
if isinstance(mission_result, Msg):
    yield mission_result, True
    return
if isinstance(mission_result, dict):
    mission_info = mission_result

# Active mission: auto-detect follow-up messages
if mission_info is None:
    mission_info = detect_active_mission_phase(
        _ws,
        session_id=session_id,
    )
```

**Mission Mode 特性**:
- 绕过工具守卫（`"_headless_tool_guard": "false"`）
- 自动注入 context reminder 到用户消息
- Phase 1: PRD review
- Phase 2: execution

### Stage 6: Agent 实例化 (lines 594-604)

**目的**: 创建 QwenPawAgent 实例

```python
# runner.py:594-604
agent = QwenPawAgent(
    agent_config=agent_config,
    env_context=env_context,
    mcp_clients=mcp_clients,
    memory_manager=self.memory_manager,
    request_context=base_request_context,
    workspace_dir=self.workspace_dir,
    task_tracker=self._task_tracker,
)
await agent.register_mcp_clients()
agent.set_console_output_enabled(enabled=False)
```

**关键设计**: **每次请求新建 Agent 实例**

这是保证配置热重载即时生效的核心机制。如果复用 Agent 实例，配置变更需要等待实例重建才能生效。

### Stage 7: 聊天自动注册 (lines 610-642)

**目的**: 如果有 ChatManager，自动注册会话

```python
# runner.py:610-642
if self._chat_manager is not None:
    logger.debug(
        f"Runner: Calling get_or_create_chat for "
        f"session_id={session_id}, user_id={user_id}, "
        f"channel={channel}, name={name}",
    )
    chat = await self._chat_manager.get_or_create_chat(
        session_id,
        user_id,
        channel,
        name=name,
    )
```

**自动注册流程**:
1. 从消息列表提取聊天名称（取第一条消息的前10个字符）
2. 调用 `get_or_create_chat()` 查找或创建聊天记录
3. ChatManager 负责持久化到 Redis 和 JSON 文件

### Stage 8: 技能注入 (lines 644-653)

**目的**: 处理 `/skillname [input]` 格式的命令

```python
# runner.py:644-653
if mission_info is None:
    skill_response = self._maybe_inject_skill(
        query,
        msgs,
        agent.toolkit.skills,
    )
    if skill_response is not None:
        yield skill_response, True
        return
```

**技能解析逻辑** (`runner.py:168-235`):

```python
@staticmethod
def _parse_skill_query(query: str) -> tuple[str, str] | None:
    """Parse ``/name [input]`` or ``/[name with spaces] [input]``."""
    # 两种格式：
    # /[skill name] input — bracket form，处理名称中的空格
    # /name input — plain form
```

**两种执行模式**:
- `/skillname` 无输入：返回技能信息（描述、路径）
- `/skillname <input>`：将技能体合并到用户消息，交给 Agent 处理

### Stage 9: 会话状态加载 (lines 655-672)

**目的**: 从 JSON 文件加载历史会话状态

```python
# runner.py:655-672
try:
    await self.session.load_session_state(
        session_id=session_id,
        user_id=user_id,
        agent=agent,
    )
except KeyError as e:
    logger.warning(
        "load_session_state skipped (state schema mismatch): %s; "
        "will save fresh state on completion to recover file",
        e,
    )
session_state_loaded = True

# Rebuild system prompt so it always reflects the latest
agent.rebuild_sys_prompt()
```

**关键设计**: `rebuild_sys_prompt()`

即使加载了历史会话状态，也会重新构建 system prompt，确保使用最新的 AGENTS.md / SOUL.md / PROFILE.md，而不是使用保存的旧版本。

### Stage 10: 执行 (lines 674-711)

**目的**: 根据模式执行 Agent

```python
# runner.py:674-711
if mission_info is not None:
    # Mission Mode: phased execution
    from ...agents.mission.mission_runner import (
        run_mission_phase1,
        run_mission_phase2,
    )
    phase = mission_info["mission_phase"]
    loop_dir = Path(mission_info["loop_dir"])
    max_iters = mission_info.get("max_iterations", 20)

    if phase == 1:
        async for msg, last in run_mission_phase1(...):
            yield msg, last
    else:
        async for msg, last in run_mission_phase2(...):
            yield msg, last
else:
    # Standard mode: streaming output
    async for msg, last in _stream_printing_messages_interruptible(
        agents=[agent],
        coroutine_task=agent(msgs),
    ):
        yield msg, last
```

**流式输出机制**: `_stream_printing_messages_interruptible` (lines 56-105)

```python
async def _stream_printing_messages_interruptible(
    *,
    agents: list[Any],
    coroutine_task: Coroutine[Any, Any, Msg],
) -> AsyncGenerator[tuple[Msg, bool], None]:
    """Like agentscope.stream_printing_messages, but cancel the agent task
    promptly when the outer stream is stopped or closed.
    """
    queue: asyncio.Queue = asyncio.Queue()
    for agent in agents:
        agent.set_msg_queue_enabled(True, queue)

    task = asyncio.create_task(coroutine_task)
    # ... 队列消费循环
```

特点：
- 使用 `asyncio.Queue` 传递消息
- 支持外部取消时立即取消 Agent 任务
- 通过 `task.add_done_callback()` 通知队列结束

### Stage 11: 错误处理 (lines 713-753)

**目的**: 转换异常为用户友好类型，写入错误转储文件

```python
# runner.py:713-753
except asyncio.CancelledError as exc:
    logger.info(f"query_handler: {session_id} cancelled!")
    if agent is not None:
        await agent.interrupt()
    raise AgentException("Task has been cancelled!") from exc
except AppBaseException:
    raise
except Exception as e:
    model_name = None
    if agent and hasattr(agent, "model"):
        model_name = getattr(agent.model, "model_name", None)

    converted = convert_model_exception(e, model_name)

    # Preserve all original error dump logic
    debug_dump_path = write_query_error_dump(
        request=request,
        exc=converted,
        locals_=locals(),
    )
    # ... 添加调试路径到异常
    raise converted from e
```

**异常分类处理**:
- `CancelledError`: 中断 Agent，抛出 AgentException
- `AppBaseException`: 直接重新抛出（业务异常）
- 其他异常: 通过 `convert_model_exception()` 转换，写入错误转储文件

### Stage 12: 清理 (lines 754-763)

**目的**: 保存会话状态，更新 chat 更新时间戳

```python
# runner.py:754-763
finally:
    if agent is not None and session_state_loaded:
        await self.session.save_session_state(
            session_id=session_id,
            user_id=user_id,
            agent=agent,
        )

    if self._chat_manager is not None and chat is not None:
        await self._chat_manager.touch_chat(chat.id)
```

**清理保证**: 使用 `finally` 块确保即使发生异常也会执行清理。

---

## 3. 三层命令路由设计

### 3.1 路由优先级

```
daemon > control > conversation
```

**源码**: `command_dispatch.py:65-76`

```python
def _is_command(query: str | None) -> bool:
    """True if query is any known command.

    Priority order: daemon > control > conversation
    """
    if not query or not query.startswith("/"):
        return False
    if parse_daemon_query(query) is not None:
        return True
    if _is_control_command(query):
        return True
    return _is_conversation_command(query)
```

### 3.2 Daemon 命令层

**处理**: 系统管理命令，如 `/daemon restart`, `/daemon status`, `/daemon logs`

**源码**: `daemon_commands.py`

```python
DAEMON_SUBCOMMANDS = frozenset(
    {"status", "restart", "reload-config", "version", "logs", "approve"},
)

# 短别名支持
DAEMON_SHORT_ALIASES = {
    "restart": "restart",
    "status": "status",
    "reload-config": "reload-config",
    ...
}
```

**处理流程** (`command_dispatch.py:82-130`):

```python
parsed = parse_daemon_query(query)
if parsed is not None:
    handler = DaemonCommandHandlerMixin()
    manager = getattr(runner, "_manager", None)
    # ... 构建 DaemonContext
    msg = await handler.handle_daemon_command(query, daemon_ctx)
    yield msg, True
    return
```

### 3.3 Control 命令层

**处理**: 影响运行中任务的高优先级命令，如 `/stop`, `/model`, `/skills`

**注册机制** (`control_commands/__init__.py`):

```python
_COMMAND_REGISTRY: Dict[str, BaseControlCommandHandler] = {}

def _register_defaults() -> None:
    """Register default control command handlers."""
    register_command(StopCommandHandler())
    register_command(ModelCommandHandler())
    register_command(SkillsCommandHandler())

def register_command(handler: BaseControlCommandHandler) -> None:
    """Register a control command handler."""
    command = handler.command_name.lower()
    _COMMAND_REGISTRY[command] = handler
```

**处理流程** (`command_dispatch.py:132-175`):

```python
if _is_control_command(query):
    workspace = runner._workspace
    channel = await channel_manager.get_channel(channel_id)
    # ...
    control_ctx = ControlContext(
        workspace=workspace,
        payload=request,
        channel=channel,
        session_id=session_id,
        user_id=user_id,
        args={},
    )
    response_text = await control_commands.handle_control_command(
        query,
        control_ctx,
    )
    yield response_msg, True
    return
```

**Control 命令处理器基类** (`control_commands/base.py`):

```python
@dataclass
class ControlContext:
    workspace: "Workspace"
    payload: Any
    channel: "BaseChannel"
    session_id: str
    user_id: str
    args: Dict[str, Any]

class BaseControlCommandHandler(ABC):
    command_name: str = ""

    @abstractmethod
    async def handle(self, context: ControlContext) -> str:
        raise NotImplementedError
```

### 3.4 Conversation 命令层

**处理**: 对话管理命令，如 `/compact`, `/new` 等

**源码**: `command_dispatch.py:178-207`

```python
# Conversation path: lightweight memory + CommandHandler
memory = runner.memory_manager.get_in_memory_memory()
session_state = await runner.session.get_session_state_dict(
    session_id=session_id,
    user_id=user_id,
)
memory_state = session_state.get("agent", {}).get("memory", {})
memory.load_state_dict(memory_state, strict=False)

conv_handler = CommandHandler(
    agent_name="Friday",
    memory=memory,
    memory_manager=runner.memory_manager,
    enable_memory_manager=runner.memory_manager is not None,
)
response_msg = await conv_handler.handle_conversation_command(query)
yield response_msg, True
```

---

## 4. SafeJSONSession 会话持久化

### 4.1 设计目标

```python
# session.py:85
class SafeJSONSession(SessionBase):
    """异步 JSON 文件会话状态，支持跨平台文件名清理和损坏恢复"""
```

### 4.2 Windows 文件名兼容性

```python
# session.py:30-40
_UNSAFE_FILENAME_RE = re.compile(r'[\\/:*?"<>|]')

def sanitize_filename(name: str) -> str:
    """Replace characters that are illegal in Windows filenames with ``--``."""
    return _UNSAFE_FILENAME_RE.sub("--", name)
```

### 4.3 损坏 JSON 恢复

```python
# session.py:15-40
def _safe_json_loads(content: str, filepath: str = "") -> dict:
    """Parse JSON with corruption recovery.

    1. 尝试标准 json.loads
    2. 失败则使用 raw_decode 提取第一个有效 JSON 对象
    3. 完全损坏则返回空 dict
    """
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        pass

    try:
        result, _ = json.JSONDecoder().raw_decode(content)
        logger.warning(
            "Session file %s had corrupted JSON. "
            "Recovered first valid object via raw_decode.",
            filepath,
        )
        return result
    except json.JSONDecodeError:
        return {}
```

### 4.4 核心方法

| 方法 | 用途 |
|------|------|
| `save_session_state()` | 异步保存状态到 JSON 文件 |
| `load_session_state()` | 异步从 JSON 文件加载状态 |
| `update_session_state()` | 更新特定 key 的状态 |
| `get_session_state_dict()` | 获取完整状态字典 |

---

## 5. TaskTracker 任务追踪

### 5.1 核心数据结构

```python
# task_tracker.py:25-31
@dataclass
class _RunState:
    """Per-run state (task, queues, buffer), guarded by tracker lock."""

    task: asyncio.Future
    queues: list[asyncio.Queue] = field(default_factory=list)
    buffer: list[str] = field(default_factory=list)
```

### 5.2 TaskTracker 类

```python
# task_tracker.py:34-48
class TaskTracker:
    """Per-workspace tracker: run_key -> RunState.

    All mutations to _runs under _lock. Producer broadcasts under lock.
    Subscribers use unbounded per-connection queues; disconnect removes them
    via :meth:`detach_subscriber`.
    """

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._runs: dict[str, _RunState] = {}
```

### 5.3 断线重连支持

```python
# task_tracker.py:144-162
async def attach(self, run_key: str) -> asyncio.Queue | None:
    """Attach to an existing run.

    Returns a new queue pre-filled with the event buffer, or ``None``
    if no run is active for *run_key*.
    """
    async with self._lock:
        state = self._runs.get(run_key)
        if state is None or state.task.done():
            return None
        q: asyncio.Queue = asyncio.Queue()
        for sse in state.buffer:
            q.put_nowait(sse)
        state.queues.append(q)
        return q
```

**重连机制**:
1. 新连接调用 `attach()` 获取已有运行的队列
2. 队列预填充事件缓冲区（`buffer`）
3. 新事件继续追加到 buffer 和所有订阅队列
4. 断开时自动 `detach_subscriber()` 移除队列引用

### 5.4 启动或附加

```python
# task_tracker.py:164-213
async def attach_or_start(
    self,
    run_key: str,
    payload: Any,
    stream_fn: Callable[..., Coroutine],
) -> tuple[asyncio.Queue, bool]:
    """Attach to an existing run or start a new one.

    Returns ``(queue, is_new_run)``.
    """
    async with self._lock:
        state = self._runs.get(run_key)
        if state is not None and not state.task.done():
            # 附加到已有运行
            q: asyncio.Queue = asyncio.Queue()
            for sse in state.buffer:
                q.put_nowait(sse)
            state.queues.append(q)
            return q, False

        # 启动新运行
        my_queue: asyncio.Queue = asyncio.Queue()
        run = _RunState(...)
        self._runs[run_key] = run

        async def _producer() -> None:
            async for sse in stream_fn(payload):
                # 广播到 buffer 和所有队列
                ...

        run.task = asyncio.create_task(_producer())
        return my_queue, True
```

---

## 6. Chat 数据模型

### 6.1 ChatSpec

```python
# models.py:12-50
class ChatSpec(BaseModel):
    """Chat specification with UUID identifier."""

    id: str = Field(
        default_factory=lambda: str(uuid4()),
        description="Chat UUID identifier",
    )
    name: str = Field(default="New Chat", description="Chat name")
    session_id: str = Field(...)
    user_id: str = Field(...)
    channel: str = Field(default=DEFAULT_CHANNEL, ...)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    meta: Dict[str, Any] = Field(default_factory=dict)
    status: str = Field(default="idle")
    pinned: bool = Field(default=False)
```

### 6.2 ChatUpdate

```python
# models.py:55-70
class ChatUpdate(BaseModel):
    """Mutable chat fields accepted from external clients."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None)
    pinned: bool | None = Field(default=None)
```

### 6.3 ChatHistory

```python
# models.py:75-82
class ChatHistory(BaseModel):
    """Complete chat view with spec and state."""

    messages: list[Message] = Field(default_factory=list)
    status: str = Field(default="idle")
```

---

## 7. Runner 协调关系图

```
                    ┌─────────────────────────────────────┐
                    │           AgentRunner               │
                    │         query_handler()             │
                    └───────────────┬─────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐       ┌───────────────────────┐   ┌─────────────────┐
│  ToolGuard    │       │    Command Dispatch    │   │   ChatManager   │
│  审批检查     │       │  daemon>control>conv   │   │  会话自动注册   │
└───────────────┘       └───────────────────────┘   └─────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────────┐
            │ /daemon   │   │ /stop     │   │ /model,skills │
            │ status    │   │ /model    │   │ /new,/compact │
            │ restart   │   │ /skills   │   │               │
            │ logs      │   │           │   │               │
            └───────────┘   └───────────┘   └───────────────┘

        ┌───────────────────────────────────────────────────────┐
        │                     Agent 构建                        │
        ├─────────────┬──────────────┬─────────────┬──────────┤
        │   MCPManager│  AgentConfig │MemoryManager│TaskTracker│
        │  (热重载)   │  (热重载)    │             │ (SSE流)  │
        └─────────────┴──────────────┴─────────────┴──────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────────┐
                    │         QwenPawAgent              │
                    │    (每次请求新建实例)              │
                    └───────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────┐       ┌───────────────────────┐   ┌─────────────────┐
│ SafeJSONSession│      │    Mission Mode        │   │  ToolGuard      │
│  状态持久化    │       │  Phase 1/Phase 2       │   │  工具守卫        │
└───────────────┘       └───────────────────────┘   └─────────────────┘
```

---

## 8. 关键设计模式总结

### 8.1 每次请求新建 Agent 实例

```python
# runner.py:594
agent = QwenPawAgent(
    agent_config=agent_config,
    ...
)
```

**优势**:
- 配置变更即时生效（AgentConfig、MCPClients、Skills 都重新加载）
- 无需显式重建 Agent 或重启进程
- 避免状态残留

**代价**:
- 每次请求有一定初始化开销
- 需要通过 SafeJSONSession 管理状态持久化

### 8.2 三层命令路由优先级

```python
# command_dispatch.py:65-76
# daemon > control > conversation
```

**设计理由**:
- daemon 命令需要最高优先级（系统管理不受对话影响）
- control 命令次之（影响当前任务，如 /stop）
- conversation 命令最后（内存管理等）

### 8.3 异步会话状态 + 损坏恢复

```python
# session.py
async def save_session_state(...):
    # 异步写入 JSON

async def load_session_state(...):
    # 异步读取 + raw_decode 恢复
```

**设计理由**:
- 异步 I/O 不阻塞事件循环
- `raw_decode` 回退处理并发写入导致的 JSON 损坏
- 跨平台文件名清理确保 Windows 兼容性

### 8.4 TaskTracker SSE 重连机制

```python
# task_tracker.py
buffer: list[str]  # 事件缓冲区
queues: list[asyncio.Queue]  # 订阅者队列
```

**设计理由**:
- buffer 存储最近事件，支持断线重连
- 多订阅者队列，每个连接独立
- 弱引用 + 清理机制避免泄漏

---

## 9. init_handler 与 shutdown_handler

### 9.1 init_handler

```python
# runner.py:797-815
async def init_handler(self, *args, **kwargs):
    """Init handler."""
    # 加载 .env 文件
    env_path = Path("./") / ".env"
    if env_path.exists():
        load_dotenv(env_path)

    # 初始化 SafeJSONSession
    session_dir = str(
        (self.workspace_dir if self.workspace_dir else WORKING_DIR)
        / "sessions",
    )
    self.session = SafeJSONSession(save_dir=session_dir)
```

### 9.2 shutdown_handler

```python
# runner.py:817-820
async def shutdown_handler(self, *args, **kwargs):
    """Shutdown handler."""
    # 目前为空，清理逻辑在各组件的生命周期中处理
```

---

## 10. 常见流程分析

### 10.1 普通用户查询流程

```
用户发送 "你好"
  → Runner.query_handler()
    → Stage 1: _resolve_pending_approval() → 无待审批
    → Stage 2: _is_command() → False
    → Stage 3: set_current_agent_id/session_id
    → Stage 4: build_env_context(), load_agent_config()
    → Stage 5: maybe_handle_mission_command() → None
    → Stage 6: QwenPawAgent() 实例化
    → Stage 7: ChatManager.get_or_create_chat() 注册
    → Stage 8: _maybe_inject_skill() → None
    → Stage 9: session.load_session_state() 加载历史
    → Stage 10: _stream_printing_messages_interruptible() 流式输出
    → Stage 11: 无异常
    → Stage 12: session.save_session_state(), touch_chat()
```

### 10.2 /stop 命令流程

```
用户发送 "/stop"
  → Runner.query_handler()
    → Stage 1: _resolve_pending_approval() → 无待审批
    → Stage 2: _is_command() → True
    → run_command_path()
      → _is_control_command("/stop") → True
      → 获取 workspace, channel
      → ControlContext 构建
      → StopCommandHandler.handle()
        → TaskTracker.request_stop()
        → ChannelManager.clear_queue()
      → yield response_msg
    → return
```

### 10.3 工具审批流程

```
用户发送 "approve"
  → Runner.query_handler()
    → Stage 1: _resolve_pending_approval(session_id, "approve")
      → pending = get_pending_by_session()
      → _is_approval("approve") → True
      → resolve_request(APPROVED)
      → 返回批准的工具调用
    → Stage 4: 构建 base_request_context
      → "forced_tool_call_json": {...}
    → ... 后续流程 Agent 使用批准的工具调用
```

---

## 11. 应用场景

### 场景1: 多渠道统一接入

当用户通过 Telegram 发送消息时，消息经过以下路径到达 Runner：
1. TelegramChannel 接收消息，解析为 AgentRequest
2. ChannelManager 根据 session_id 路由到对应队列
3. Runner.query_handler() 处理请求，返回流式响应
4. TaskTracker 追踪任务状态，支持断线重连

### 场景2: 热重载配置

管理员修改 agent.json 后：
1. AgentConfigWatcher 检测到文件变更
2. 触发 schedule_agent_reload()
3. MultiAgentManager.reload_agent() 执行热重载
4. 下次请求时，Runner 加载新配置，创建新的 QwenPawAgent 实例

### 场景3: 命令中断恢复

用户发送 /stop 命令时：
1. 命令进入 critical 优先级队列
2. StopCommandHandler.handle() 立即响应
3. TaskTracker.request_stop() 中断正在运行的任务
4. ChannelManager.clear_queue() 清理待处理消息
5. 会话状态保存，用户可随时恢复

---

## 12. 常见问题

### Q1: 为什么每次请求都要新建 Agent 实例？

**A**: 这是实现热重载的最简单方式。如果复用实例，配置变更需要显式重建 Agent 或重启进程。每次请求新建的开销在 QwenPaw 的设计中被接受，因为：
- 大部分时间花在等待 LLM 响应上
- Agent 初始化（加载配置、创建工具包）相对轻量
- 会话状态通过 SafeJSONSession 持久化，不依赖 Agent 实例

### Q2: SafeJSONSession 如何处理并发写入？

**A**: SafeJSONSession 使用原子写入机制：
1. 先写 `.tmp` 临时文件
2. 写入完成后 `shutil.move()` 原子替换
3. 读取时使用 `raw_decode` 容错，即使文件部分损坏也能恢复

### Q3: TaskTracker 如何支持多订阅者？

**A**: 每个 `attach()` 调用创建一个新的 `asyncio.Queue`，并添加到 `state.queues` 列表。新事件同时写入 `buffer` 和所有队列，实现广播。

### Q4: 三层命令路由的优先级是如何确定的？

**A**: 优先级基于**紧急程度**和**影响范围**：
- **daemon (high)**: 系统级操作，需要最快响应
- **control (critical/high)**: 影响当前任务的操作
- **conversation (normal)**: 对话管理，可以稍后处理

### Q5: 如何调试 Runner 的请求处理流程？

**A**: 可以通过以下方式：
1. 设置 `logger.setLevel(logging.DEBUG)` 查看详细日志
2. 检查 `sessions/*.json` 文件查看会话状态
3. 使用 TaskTracker API 获取任务状态
4. 查看错误转储文件 `error_dumps/` 目录

---

## 13. 最佳实践

### 实践1: 合理设计会话超时

```python
# 建议在 agent.json 中配置
{
    "running": {
        "max_iters": 50,
        "request_timeout_seconds": 120
    }
}
```

### 实践2: 避免长时间运行的命令

对于需要长时间执行的任务，建议：
1. 使用 `/mission` 命令进入任务模式
2. 使用后台任务（TaskTracker）而非同步等待
3. 设置合理的 `max_iters` 限制迭代次数

### 实践3: 正确处理会话状态

- 不要手动修改 `sessions/*.json` 文件
- 使用 `/compact` 命令压缩历史会话
- 定期清理过期会话文件

### 实践4: 命令使用建议

| 场景 | 推荐命令 |
|------|----------|
| 停止当前任务 | `/stop` |
| 切换模型 | `/model <model_name>` |
| 查看可用技能 | `/skills` |
| 使用技能 | `/skillname <input>` |
| 压缩上下文 | `/compact` |

---

## 14. 如果你来自 Java...

对于有 Java 背景的开发者，理 Runner 的设计时可以通过以下类比来理解：

| Python 概念 | Java/Spring 对应 | 说明 |
|-------------|-----------------|------|
| `AgentRunner` | `@Service` + `@Scope("prototype")` | 每次请求创建新实例，类似 Spring 的 prototype scope |
| `query_handler` | Controller Request Mapping | 入口点，处理请求生命周期 |
| `SafeJSONSession` | HttpSession + JDBC Session | 会话状态持久化，但使用 JSON 文件存储 |
| `TaskTracker` | `DeferredResult` + `SseEmitter` | 实现异步流式响应，类似于 Spring 的 SSE 支持 |
| `command_dispatch.py` | HandlerMapping + ControllerAdvice | 命令路由和优先级处理 |
| `asyncio.Queue` | `BlockingQueue` | 异步消息队列，用于流式输出 |
| 三层命令路由 | 过滤器链 Filter Chain | daemon > control > conversation 类似拦截器优先级 |

### 关键架构差异

**1. 依赖注入方式**

Java/Spring 使用注解 + 容器：
```java
@Service
public class MyService {
    @Autowired
    private OtherService otherService;
}
```

QwenPaw 使用显式 setter 注入：
```python
def set_chat_manager(self, chat_manager):
    self._chat_manager = chat_manager
```

**2. 热重载策略**

Spring 需要配合 `@RefreshScope` 或 Actuator 才能实现配置热重载。QwenPaw 的做法是**每次请求新建 Agent 实例**，天然支持热重载，但代价是创建开销。

**3. 会话状态**

Java 通常使用 `HttpSession`（内存）或数据库存储。QwenPaw 的 `SafeJSONSession` 使用文件存储 + 原子写入，适合多进程环境，但性能不如内存存储。

**4. 异步响应**

Spring 通过 `SseEmitter` 或 `WebFlux` 实现 SSE。QwenPaw 通过 `TaskTracker` + `asyncio.Queue` 实现，核心是 `AsyncGenerator`，这是 Python 特有的协程机制。

### 迁移建议

如果你从 Java Spring 迁移到 QwenPaw：
- 忘掉 `@Autowired`，关注**显式依赖注入**
- 忘掉 `@SessionScope`，理解 **SafeJSONSession 的文件持久化**
- 使用 `asyncio.Queue` 而不是 `BlockingQueue`
- 使用 Python 的 `async/await` 而不是 Spring 的 `@Async`

---

## 练习题

### 基础练习

1. **理解 12 阶段请求生命周期**
   在 `runner.py` 中，`query_handler` 方法包含 12 个处理阶段。如果用户在工具审批流程中超时，代码会进入哪个 stage？请写出完整的 stage 名称和对应的行号范围。

2. **命令路由优先级**
   `_is_command` 函数实现了 `daemon > control > conversation` 的三层优先级。请分析 `command_dispatch.py` 中，当用户发送 `/daemon status` 时，代码是如何快速判断并跳过的？`parse_daemon_query` 在其中的作用是什么？

3. **SafeJSONSession 的损坏恢复**
   `session.py` 中的 `_safe_json_loads` 函数包含 JSON 损坏恢复逻辑。请说明：当 JSON 文件出现部分损坏时，`raw_decode` 是如何提取有效内容的？这种设计在并发写入场景下会有什么风险？

4. **TaskTracker 断线重连机制**
   `TaskTracker.attach()` 方法返回的队列会被预填充 `buffer` 内容。请说明：新连接调用 `attach()` 后，buffer 中的 SSE 事件是如何被重新发送的？丢失事件的上界是多少？

### 进阶练习

1. **实现可中断的流式输出**
   `_stream_printing_messages_interruptible` 使用 `asyncio.Queue` 和 `task.add_done_callback` 实现可中断的流式输出。请设计一个简化版本：支持外部调用者通过 `cancel()` 方法立即取消正在运行的 Agent 任务，并说明如何确保 `asyncio.CancelledError` 被正确传播。

2. **添加新的 Control 命令**
   假设需要添加 `/history <session_id>` 命令，显示指定会话的消息历史。请参照 `control_commands/` 的现有结构，设计新增命令的完整流程，包括：
   - `__init__.py` 中的 `register_command` 调用
   - `BaseControlCommandHandler` 子类的实现
   - 命令如何从 `runner.query_handler` 传递到处理器

3. **Session 状态版本迁移**
   当 `SafeJSONSession` 的状态 schema 发生升级时（如新增字段），旧版本保存的 JSON 文件可能导致 `KeyError`。请设计一个状态版本迁移方案，在 `load_session_state` 中自动检测并升级旧格式，同时保持向后兼容。

### 实战练习

**综合项目：实现一个调试面板命令**

设计并实现 `/debug` 命令，用于实时诊断 Runner 状态。该命令需要：
- 在 `control_commands/` 下新增 `DebugCommandHandler`
- 实现以下子命令：
  - `/debug sessions`：列出所有活跃 session 及其状态
  - `/debug task <run_key>`：显示指定任务的队列长度和 buffer 内容
  - `/debug memory <session_id>`：输出该 session 的内存摘要
- 通过 `runner` 参数访问 `AgentRunner` 的内部状态（`_task_tracker`、`session` 等）
- 返回结构化的诊断报告（文本格式即可）

**提示**：
- 参考 `StopCommandHandler` 的上下文获取方式
- `runner._task_tracker._runs` 包含所有运行状态
- 使用 `runner.session.get_session_state_dict()` 获取会话状态

---

## 15. 相关章节

- [智能体钩子系统](./23-智能体钩子系统.md) -- 钩子机制与 Agent 核心流程
- [Provider系统深度解析](./82-Provider系统深度解析.md) -- 模型管理与路由
- [消息渠道系统](./08-消息渠道系统.md) -- 渠道与 Runner 的交互
- [Workspace隔离机制](./28-Workspace隔离机制.md) -- Workspace 管理

---

## 实战演练

### 基础练习（⭐）
**目标**: 在源码中找到 Runner 的入口函数，说明它接收什么参数
**提示**: 在 `src/qwenpaw/app/runner/runner.py` 中搜索 `query_handler` 方法定义
**参考思路**: `query_handler` 是 `AgentRunner` 的核心异步生成器方法，它接收 `request`（包含 `session_id`、`user_id`、`channel`、消息列表等字段）。方法是 `AsyncGenerator[tuple[Msg, bool], None]` 类型——每次 `yield` 一个消息和一个 `last` 标志（`True` 表示最终响应）。理解这个签名是追踪整个请求流程的起点。

### 进阶练习（⭐⭐⭐）
**目标**: 追踪一次包含 MCP 工具调用的完整请求：Runner → Agent → Tool → MCP Client → Response
**提示**: 从 `query_handler` 的 Stage 6（Agent 实例化）开始，Agent 构建时通过 `register_mcp_clients()` 注册 MCP 工具，然后在 ReAct 循环中通过 `_acting()` 调用
**参考思路**: 请求流程为：(1) `query_handler` Stage 4 获取 `mcp_clients` 列表；(2) Stage 6 创建 `QwenPawAgent` 并调用 `agent.register_mcp_clients()` 将 MCP 工具注册到 `Toolkit`；(3) Agent 的 ReAct 循环中，`_reasoning()` 返回包含 `tool_use` 的消息，决定调用某个 MCP 工具；(4) `_acting()` 经过 ToolGuard 安全检查后，通过 `Toolkit` 路由到对应的 MCP Client；(5) MCP Client 通过 `session.call_tool()` 发送 JSON-RPC 请求到 MCP Server；(6) 结果沿原路返回，经过 `_stream_printing_messages_interruptible` 流式输出给用户。

### 挑战练习（⭐⭐⭐⭐⭐）
**目标**: 分析审批系统在请求流程中的拦截点，画出完整的审批决策树
**提示**: 从 `query_handler` Stage 1 的 `_resolve_pending_approval()` 开始，结合 `ToolGuardMixin._acting()` 中的 `_decide_guard_action()` 分析
**参考思路**: 审批系统有两个拦截点：(1) **请求入口拦截**（Stage 1）：`_resolve_pending_approval()` 检查当前 session 是否有待审批的工具调用。如果用户发送 "approve" 则批准执行，如果超时则自动拒绝；(2) **工具执行拦截**（`ToolGuardMixin._acting()`）：每次工具调用前执行 `_decide_guard_action()`，决策路径为：是否在拒绝列表 → 自动拒绝；是否已预批准 → 直接执行；守卫规则检查发现问题 → 暂停执行等待用户审批；无问题 → 正常执行。将这两个拦截点以及 `_consume_preapproval()`、`_acting_with_approval()`、`_acting_auto_denied()` 等方法画出完整的决策树。

---

## 知识检查

1. `query_handler` 的 12 个处理阶段中，Stage 6 为什么选择"每次请求新建 Agent 实例"而非复用？这一设计如何实现配置的热重载即时生效？

2. 三层命令路由的优先级是 `daemon > control > conversation`。请说明 `/daemon status` 和 `/stop` 命令分别被哪一层处理，以及这种优先级设计的理由。

3. `TaskTracker` 的 `attach()` 方法如何实现断线重连？`buffer` 字段在重连过程中起什么作用？

## 延伸阅读

- [33-任务追踪系统](./33-任务追踪系统.md) -- TaskTracker 的 SSE 流式输出与断线重连详细设计
- [29-Mission模式详解](./29-Mission模式详解.md) -- Mission 模式的两阶段执行与上下文管理
- [64-消息系统详解](./64-消息系统详解.md) -- 消息模型与 SafeJSONSession 的损坏恢复机制

---

## 16. 总结

AgentRunner 是 QwenPaw 请求处理的核心引擎，通过 12 个阶段的清晰分离实现了：

1. **安全性**: 工具守卫审批机制
2. **灵活性**: 三层命令路由覆盖所有交互模式
3. **热重载**: 每次请求新建 Agent 实例
4. **可靠性**: SafeJSONSession 的损坏恢复
5. **可追踪性**: TaskTracker 支持断线重连

理解 Runner 的架构对于调试问题、扩展功能和优化性能至关重要。

