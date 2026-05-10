# 31 ACP 智能体通信协议

## 本章导读

| 项目 | 内容 |
|------|------|
| 学习目标 | 解释 ACP 协议的消息格式；理解智能体间的委托和协作机制；分析权限管理和错误处理 |
| 前置知识 | [25-多智能体协作](../level-3-agent-core/25-多智能体协作.md)、[18-智能体架构](../level-3-agent-core/18-智能体架构.md) |
| 预计时长 | 40 分钟 |
| 难度等级 | ⭐⭐⭐⭐ |
| 核心关键词 | `ACP` `通信` `委托` `权限` |

本章详解 QwenPaw 的 ACP 智能体通信协议，包括 Server/Tool 双重角色、JSON-RPC over stdio 消息格式、会话管理、流式追踪机制，以及挂起权限的安全模型。

## 概述

QwenPaw 支持两种 ACP 模式：**ACP Server**（外部客户端连接 QwenPaw）和 **ACP Tool**（QwenPaw 连接外部 ACP 智能体），通过 JSON-RPC over stdio 实现智能体间通信。

本章节详细解析 ACP 协议的双重角色、消息格式、会话管理、流式追踪机制，以及完整的通信流程。

---

## 1. ACP 协议概述

### 1.1 双重角色

```
┌─────────────────────────────────────────────────────────────────┐
│                        ACP 协议架构                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ACP Server 模式                    ACP Tool 模式              │
│   ┌──────────────┐                 ┌──────────────┐             │
│   │  外部客户端   │ ←─── stdio ──→ │  QwenPaw    │             │
│   │  (如 ReAct)  │                 │  (连接者)    │             │
│   └──────────────┘                 └──────────────┘             │
│                                                                 │
│   QwenPaw 作为服务器               QwenPaw 作为客户端           │
│   接收 prompt，返回响应            连接外部 ACP 智能体           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| 模式 | 角色 | 说明 |
|------|------|------|
| ACP Server | 服务器 | 外部客户端连接 QwenPaw，QwenPaw 提供智能体能力 |
| ACP Tool | 客户端 | QwenPaw 连接外部 ACP 智能体，使用其工具 |

### 1.2 传输机制

- **协议**：JSON-RPC over stdio
- **用途**：智能体间通信、工具调用、状态同步

---

## 2. ACP Server 模式

源码路径：`src/qwenpaw/agents/acp/server.py`

### 2.1 QwenPawACPAgent

```python
# src/qwenpaw/agents/acp/server.py:327
class QwenPawACPAgent:
    """QwenPaw 作为 ACP 服务器

    处理来自外部客户端的请求，将 QwenPaw 的智能体能力暴露给外部。
    """
    async def prompt(self, prompt: PromptBlocks, session_id: str) -> PromptResponse:
        # 1. 确保 Workspace 就绪
        runner = await self._ensure_workspace()

        # 2. 转换 ACP 提示块为内部 Msg 格式
        msgs = _blocks_to_msgs(prompt)

        # 3. 处理查询，返回流式响应
        async for msg, _is_last in runner.query_handler(msgs):
            # 4. 转换消息为 ACP 更新
            updates = _msg_to_updates(msg, tracker)
            for upd in updates:
                # 5. 发送会话更新
                await self._conn.session_update(session_id=session_id, update=upd)
```

### 2.2 支持的方法

| 方法 | 行号 | 请求 | 响应 | 用途 |
|------|------|------|------|------|
| `initialize` | 308-327 | `InitializeRequest` | `InitializeResponse` | 握手，返回能力版本 |
| `new_session` | 468 | `NewSessionRequest` | `SessionInfo` | 创建新会话 |
| `load_session` | 348-366 | `LoadSessionRequest` | `SessionInfo` | 加载/附加到现有会话 |
| `resume_session` | 429-449 | `ResumeSessionRequest` | `SessionInfo` | 恢复已关闭会话 |
| `prompt` | 513 | `PromptRequest` | `stream PromptResponse` | 发送用户消息并流式返回 |
| `cancel` | 506-517 | `CancelRequest` | `CancelResponse` | 取消进行中的 prompt |

### 2.3 初始化流程

```python
# 客户端与服务器握手
{
    "jsonrpc": "2.0",
    "method": "initialize",
    "params": {
        "protocol_version": "1.0",
        "capabilities": {
            "streaming": true,
            "sessions": true
        },
        "client_info": {
            "name": "react-agent",
            "version": "1.0"
        }
    },
    "id": 1
}

# 服务器响应
{
    "jsonrpc": "2.0",
    "result": {
        "protocol_version": "1.0",
        "server_info": {
            "name": "qwenpaw",
            "version": "1.0.0"
        },
        "capabilities": {...}
    },
    "id": 1
}
```

---

## 3. ACP Tool 模式

源码路径：`src/qwenpaw/agents/acp/service.py`

### 3.1 ACPService

```python
# src/qwenpaw/agents/acp/service.py:38
class ACPService:
    """QwenPaw 作为 ACP 客户端

    连接外部 ACP 智能体，将其工具暴露给 QwenPaw 使用。
    """
    async def run_turn(
        self,
        *,
        chat_id: str,
        agent: str,
        prompt_blocks: PromptBlocks,
        cwd: Path,
        on_message: Callable,
        ...
    ):
        # 1. 获取或创建会话
        conversation = await self._get_or_create_session(
            chat_id=chat_id,
            agent=agent
        )

        # 2. 获取 turn lock，防止并发
        async with conversation.turn_lock:
            # 3. 启动 prompt
            conversation.client.start_prompt(on_message)

            # 4. 创建 prompt 任务
            conversation.prompt_task = asyncio.create_task(
                conversation.conn.prompt(
                    session_id=conversation.session_id,
                    prompt=prompt_blocks
                )
            )
```

### 3.2 会话管理

```python
# 会话状态追踪
class Conversation:
    session_id: str
    turn_lock: asyncio.Lock      # 防止并发 prompt
    prompt_task: asyncio.Task   # 当前 prompt 任务
    client: ACPClient          # ACP 客户端连接
```

---

## 4. 消息格式

源码路径：`src/qwenpaw/agents/acp/core.py`

### 4.1 PromptBlocks

```python
# src/qwenpaw/agents/acp/core.py:63
PromptBlocks = list[
    TextContentBlock | ImageContentBlock | AudioContentBlock |
    ResourceContentBlock | EmbeddedResourceContentBlock
]
```

| 类型 | 结构 | 说明 |
|------|------|------|
| `TextContentBlock` | `{type: "text", text: str}` | 文本内容 |
| `ImageContentBlock` | `{type: "image", url: str}` | 图片（URL 或 base64） |
| `AudioContentBlock` | `{type: "audio", url: str}` | 音频 |
| `ResourceContentBlock` | `{type: "resource", uri: str}` | 资源引用 |
| `EmbeddedResourceContentBlock` | `{type: "embedded", content: Any}` | 内嵌资源 |

### 4.2 会话更新类型

| 类型 | 函数 | 含义 | 数据结构 |
|------|------|------|----------|
| `AgentMessageChunk` | `update_agent_message()` | 智能体文本响应（流式） | `{content: str, role: "assistant"}` |
| `AgentThoughtChunk` | `update_agent_thought()` | 智能体内部推理 | `{thought: str}` |
| `ToolCallStart` | `start_tool_call()` | 工具调用开始 | `{id, name, input: {...}}` |
| `ToolCallProgress` | `update_tool_call()` | 工具执行完成 | `{id, result: {...}}` |
| `Error` | `error()` | 错误 | `{message: str, code: int}` |

---

## 5. 消息转换

源码路径：`src/qwenpaw/agents/acp/core.py:140`

### 5.1 QwenPaw Msg → ACP 更新

```python
# src/qwenpaw/agents/acp/core.py:140
def _msg_to_updates(msg: Any, tracker: _StreamTracker | None = None) -> list[Any]:
    """将 QwenPaw Msg 转换为 ACP 会话更新

    处理多种消息类型：
    - 文本消息 → AgentMessageChunk
    - 工具调用 → ToolCallStart/Progress
    """
    updates: list[Any] = []
    metadata = msg.metadata or {}

    # 1. 处理文本内容
    if msg.content:
        updates.append(update_agent_message(msg.content))

    # 2. 处理工具调用
    tool_calls = metadata.get("tool_calls")
    if isinstance(tool_calls, list):
        for tc in tool_calls:
            tc_id = tc.get("id")
            tc_name = tc.get("name")

            # 新工具调用开始
            if not tracker or tracker.is_new_tool_call(tc_id):
                updates.append(start_tool_call(
                    tc_id, tc_name, status="in_progress"
                ))

            # 工具调用完成
            if tc.get("status") == "completed":
                updates.append(update_tool_call(
                    tc_id, result=tc.get("result")
                ))

    return updates
```

### 5.2 流式追踪

```python
# _StreamTracker 避免重复发送
class _StreamTracker:
    def __init__(self):
        self._seen_tool_calls: set[str] = set()

    def is_new_tool_call(self, tc_id: str) -> bool:
        if tc_id in self._seen_tool_calls:
            return False
        self._seen_tool_calls.add(tc_id)
        return True
```

---

## 6. 挂起权限

源码路径：`src/qwenpaw/agents/acp/core.py:72`

```python
# src/qwenpaw/agents/acp/core.py:72
@dataclass
class SuspendedPermission:
    """需要用户确认的权限请求"""
    payload: dict[str, Any]           # 权限详情
    options: list[dict[str, Any]]      # 用户可选的操作
    agent: str                         # 发起请求的智能体
    tool_name: str                     # 工具名称
    tool_kind: str                     # 工具类型
    requires_user_confirmation: bool = True
```

**使用场景：**
- 危险操作（如删除文件）需要用户确认
- 敏感操作（如访问外部 API）需要授权

---

## 7. ACP 配置

源码路径：`src/qwenpaw/config/config.py:56`

### 7.1 ACPAgentConfig

```python
# src/qwenpaw/config/config.py:56
class ACPAgentConfig(BaseModel):
    enabled: bool = False                  # 是否启用
    command: str = ""                      # ACP 服务器命令
    args: list[str] = Field(default_factory=list)
    env: Dict[str, str] = Field(default_factory=dict)
    trusted: bool = True                   # 是否信任该智能体
    tool_parse_mode: str = "call_title"   # 工具调用解析模式
```

### 7.2 配置示例

```json
{
  "acp_agents": [
    {
      "name": "claude",
      "enabled": true,
      "command": "npx",
      "args": ["-y", "@anthropic/claude-code"],
      "env": {
        "ANTHROPIC_API_KEY": "os.environ.get('ANTHROPIC_API_KEY')"
      },
      "trusted": true
    }
  ]
}
```

---

## 8. 高级特性

### 8.1 ACP 异常体系

ACP 协议定义了统一的异常层次结构，便于精确定位通信过程中的故障类型：

```python
# src/qwenpaw/agents/acp/core.py:16
class ACPErrors(Exception):
    def __init__(self, message: str, *, agent: Optional[str] = None):
        super().__init__(message)
        self.agent = agent  # 关联的智能体 ID

class ACPConfigurationError(ACPErrors): pass  # 配置错误
class ACPTransportError(ACPErrors): pass      # 传输错误（网络/连接）
class ACPProtocolError(ACPErrors): pass       # 协议错误（格式/版本）
class ACPSessionError(ACPErrors): pass        # 会话错误（超时/状态）
```

| 异常类型 | 典型原因 | 恢复策略 |
|----------|----------|----------|
| `ACPConfigurationError` | 配置文件缺失、字段非法 | 修正配置后重启 |
| `ACPTransportError` | 网络中断、目标服务不可达 | 指数退避重试 |
| `ACPProtocolError` | 消息格式不兼容、版本不匹配 | 检查两端 ACP 版本 |
| `ACPSessionError` | 会话超时、会话状态非法 | 创建新会话重试 |

### 8.2 完整权限挂起流程

第 6 节介绍了 `SuspendedPermission` 数据结构，这里展示其完整的交互流程：

**权限检查流程：**

```python
async def handle_tool_request(tool_request: ToolRequest):
    """处理工具调用请求"""

    # 1. 检查工具是否需要权限
    if not tool.requires_permission:
        return await tool.execute()

    # 2. 检查权限策略
    decision = await permission_checker.check(tool_request)

    if decision.allowed:
        return await tool.execute()
    elif decision.suspended:
        # 3. 权限挂起，等待用户确认
        return SuspendedPermission(...)
    else:
        raise ACPProtocolError("Permission denied")
```

**用户确认处理（approve / deny / modify 三种操作）：**

```python
async def handle_permission_response(
    suspended: SuspendedPermission,
    action: str,  # "approve" | "deny" | "modify"
    options: dict | None = None,
):
    """处理用户对挂起权限的响应"""

    if action == "approve":
        # 执行原请求
        return await tool.execute(suspended.payload)

    elif action == "modify":
        # 用户修改了参数
        modified_payload = options.get("payload")
        return await tool.execute(modified_payload)

    else:  # deny
        raise ACPSessionError("Permission denied by user")
```

**挂起超时处理：**

```python
# 设置挂起超时
suspended.timeout = 300  # 5 分钟超时

# 超时后自动取消
if time.time() > suspended.created_at + suspended.timeout:
    raise ACPSessionError("Permission response timeout")

# 主动取消挂起
await acp_service.cancel_suspended(suspended_id)
```

### 8.3 ACP 请求与响应消息格式

除了底层 JSON-RPC 消息外，ACP 还定义了应用层的请求-响应模型：

```python
# ACP 请求消息
class ACPRequest(BaseModel):
    id: str                    # 请求唯一 ID
    agent_id: str              # 目标智能体 ID
    message: str               # 发送给智能体的消息
    tools: list[str] | None   # 允许使用的工具（可选）
    timeout: float = 30.0      # 超时时间

# ACP 响应消息
class ACPResponse(BaseModel):
    id: str                    # 请求 ID
    status: str                # success | error | permission_required
    result: Any | None         # 执行结果
    error: str | None          # 错误信息
    suspended: SuspendedPermission | None  # 权限挂起信息
```

### 8.4 Server/Tool 模式架构图

**Server 模式架构：**

```
┌─────────────────────────────────────────────────────────────┐
│                      远程智能体                              │
│  ┌─────────────┐                                           │
│  │ ACPService  │                                           │
│  └──────┬──────┘                                           │
└─────────┼───────────────────────────────────────────────────┘
          │ HTTP/REST
          │ call_agent(agent_id, message)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                   QwenPaw ACP Server                        │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │ QwenPawACPAgent │───▶│  Tool Registry  │               │
│  └────────┬────────┘    └─────────────────┘               │
│           │                                                │
│           ▼                                                │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │  Request        │───▶│  Permission     │               │
│  │  Handler        │    │  Checker        │               │
│  └────────┬────────┘    └─────────────────┘               │
│           │                                                │
│           ▼ (if permission suspended)                       │
│  ┌─────────────────┐                                       │
│  │ SuspendedPermission│ ──── 等待用户确认 ────▶ 执行      │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

**Tool 模式架构：**

```
┌─────────────────────────────────────────────────────────────┐
│                   QwenPaw 本地 Agent                        │
│  ┌─────────────┐                                           │
│  │ ReActAgent  │                                           │
│  └──────┬──────┘                                           │
│         │ Tool Call (acp_call_agent)                       │
└─────────┼───────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│  ACPService.call_agent()                                   │
│  ┌─────────────┐                                           │
│  │ HTTP Client │                                           │
│  └──────┬──────┘                                           │
└─────────┼───────────────────────────────────────────────────┘
          │ HTTP/REST
          ▼
┌─────────────────────────────────────────────────────────────┐
│                   远程 ACP 智能体                           │
│  ┌─────────────────┐                                       │
│  │ QwenPawACPAgent │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

### 8.5 服务初始化与生命周期管理

```python
# src/qwenpaw/agents/acp/service.py
async def init_acp_service(config: ACPConfig) -> ACPService:
    """初始化 ACP 服务客户端"""
    return ACPService(config=config)

async def get_acp_service() -> ACPService:
    """获取全局 ACP 服务单例"""

async def close_acp_service() -> None:
    """关闭 ACP 服务客户端，清理连接"""
```

> **提示**：ACP 客户端采用单例模式，通过 `get_acp_service()` 获取全局实例。应用退出时应调用 `close_acp_service()` 清理所有连接。

---

## 9. CLI 入口

```bash
# 启动 QwenPaw 作为 ACP 智能体
qwenpaw acp --agent <agent_id> --workspace <workspace_dir>

# 参数说明
# --agent: Agent ID
# --workspace: 工作区目录
```

---

## 10. 设计模式

### 10.1 双重角色

```python
# ACP Server: 被动接收请求
class QwenPawACPAgent:
    async def handle_request(self, method, params):
        if method == "prompt":
            return await self.prompt(params)
        elif method == "new_session":
            return await self.new_session(params)

# ACP Tool: 主动发起请求
class ACPService:
    async def run_turn(self, prompt_blocks, ...):
        # 主动连接外部智能体
        await self.conn.prompt(session_id=..., prompt=prompt_blocks)
```

### 10.2 流式追踪

```python
# 增量更新 vs 完整快照
# 问题：每次调用返回完整消息历史，造成重复

# 解决：_StreamTracker 追踪已发送的 ID
# 只发送新的增量
updates = []
for tc in tool_calls:
    if tracker.is_new_tool_call(tc_id):  # 跳过已发送
        updates.append(start_tool_call(...))
```

### 10.3 会话锁定

```python
# turn_lock 防止同一会话并发 prompt
async with conversation.turn_lock:
    # 在锁内执行 prompt
    # 第二个 prompt 必须等待第一个完成
    await conn.prompt(...)
```

---

## 11. 应用场景

### 11.1 外部智能体调用 QwenPaw

**场景：** ReAct 智能体通过 ACP 协议调用 QwenPaw 作为工具。

```python
# 在 ReAct 智能体中
from acp import Client

client = Client("qwenpaw")

# 创建会话
session = await client.new_session()

# 发送 prompt
async for update in client.prompt(
    session_id=session.id,
    prompt=[{"type": "text", "text": "分析这个代码库"}]
):
    print(update)
```

### 11.2 QwenPaw 调用外部智能体工具

**场景：** QwenPaw 通过 ACP Tool 调用 Claude Code 的工具。

```json
// 配置
{
  "acp_agents": [
    {
      "name": "claude",
      "command": "npx",
      "args": ["-y", "@anthropic/claude-code"]
    }
  ]
}
```

```python
# QwenPaw 内部
acp_service = ACPService()

# 调用外部智能体
result = await acp_service.run_turn(
    chat_id="chat-123",
    agent="claude",
    prompt_blocks=[{"type": "text", "text": "写一个排序算法"}]
)
```

### 11.3 智能体间通信

**场景：** 多个智能体协作完成任务。

```
用户 → Agent A (规划) → Agent B (执行) → Agent C (验证)
           ↓              ↓              ↓
         ACP           ACP            ACP
```

---

## 12. 常见问题

### Q1: 会话建立失败？

**排查步骤：**

```bash
# 1. 检查外部智能体是否运行
ps aux | grep claude-code

# 2. 测试 stdio 连接
echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | npx -y @anthropic/claude-code

# 3. 检查配置
# agent.json 中 acp_agents 配置是否正确
```

### Q2: 流式响应中断？

**原因：** 网络中断、外部智能体崩溃。

**解决：**

```python
# 使用重试机制
async def prompt_with_retry(conn, session_id, prompt, max_retries=3):
    for attempt in range(max_retries):
        try:
            async for update in conn.prompt(session_id, prompt):
                yield update
            return
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            await asyncio.sleep(1 * (attempt + 1))
```

### Q3: 工具调用无响应？

**原因：** 外部智能体不支持该工具，或权限不足。

**排查：**

```python
# 检查工具列表
tools = await conn.list_tools()
print([t.name for t in tools])

# 检查权限配置
# trusted=True 允许所有操作
# trusted=False 需要用户确认
```

### Q4: 如何调试 ACP 通信？

**方法：**

```bash
# 开启 QwenPaw debug 日志
export QWENPAW_LOG_LEVEL=debug

# 查看 ACP 消息
# qwenpaw.log 中会显示 JSON-RPC 消息
grep "ACP\|jsonrpc" qwenpaw.log
```

---

## 13. 最佳实践

### 13.1 会话管理

```python
# 推荐：复用会话
session_id = await client.new_session()
for query in queries:
    async for update in client.prompt(session_id, query):
        process(update)

# 避免：每个请求新建会话
# 每次新建会话有连接开销
```

### 13.2 错误处理

```python
# 推荐：完整的错误处理
async for update in client.prompt(session_id, prompt):
    if isinstance(update, Error):
        logger.error(f"ACP error: {update.message}")
        break

# 避免：忽略错误
# async for update in client.prompt(...):
#     print(update)  # 不处理 Error 类型
```

### 13.3 权限安全

```python
# 推荐：非信任智能体限制权限
{
    "name": "external-agent",
    "trusted": false,  # 需要用户确认
    "allowed_tools": ["read_file", "grep_search"]  # 白名单
}

# 避免：过度信任
# "trusted": true  # 允许所有操作
```

### 13.4 流式处理

```python
# 推荐：增量处理
async for update in client.prompt(session_id, prompt):
    await process_update(update)  # 立即处理
    # 不等待完整响应

# 避免：缓冲完整响应
# updates = [u async for u in client.prompt(...)]  # 内存占用高
```

---

## 14. 总结

### 核心要点

| 要点 | 说明 |
|------|------|
| **双重角色** | ACP Server（服务器）+ ACP Tool（客户端） |
| **JSON-RPC over stdio** | 轻量级智能体间通信协议 |
| **流式响应** | 通过 `session_update` 实现实时推送 |
| **会话管理** | new_session/load_session/resume_session |
| **工具调用** | ToolCallStart/Progress 追踪工具执行 |
| **流式追踪** | `_StreamTracker` 避免重复发送 |
| **会话锁定** | `turn_lock` 防止并发 prompt |
| **异常体系** | 4 类异常精确区分 Configuration/Transport/Protocol/Session 错误 |
| **权限挂起** | SuspendedPermission 支持 approve/deny/modify 三种用户操作 |

### 消息流

```
ACP Server 模式：
外部客户端 → initialize() → 服务器
           → new_session() → session_id
           → prompt() → 流式响应

ACP Tool 模式：
QwenPaw → run_turn() → ACPService
       → conn.prompt() → 外部智能体
       → 流式更新 → QwenPaw 处理
```

### 相关章节

- [Workspace 隔离机制](../level-6-config-plugins/40-插件系统.md) — Workspace 提供 ACP Server 的运行环境
- [22-技能系统](../level-3-agent-core/22-技能系统.md) — MCP 是另一种工具调用协议
- [41-CLI命令系统](../level-7-cli-ops/41-CLI命令系统.md) — ACP CLI 入口

---

## 关键文件索引

| 组件 | 文件路径 | 核心职责 |
|------|----------|----------|
| ACP 异常类 | `src/qwenpaw/agents/acp/core.py:16` | 异常体系定义 |
| ACP Server | `src/qwenpaw/agents/acp/server.py` | 服务器模式实现 |
| ACP Service | `src/qwenpaw/agents/acp/service.py` | 客户端模式实现 |
| ACP Core | `src/qwenpaw/agents/acp/core.py` | 消息格式定义 |
| ACP 权限 | `src/qwenpaw/agents/acp/permissions.py` | 权限管理 |
| ACP Client | `src/qwenpaw/agents/acp/client.py` | HTTP 客户端 |
| CLI 入口 | `src/qwenpaw/cli/acp_cmd.py` | 命令行接口 |
| ACP 配置 | `src/qwenpaw/config/config.py:56` | 配置模型 |

---

## 来自 Java 的你

### 核心概念对照

| Java | Python / QwenPaw | 说明 |
|------|-------------------|------|
| RMI / IIOP | ACP Protocol (JSON-RPC over stdio) | Java 用 RMI/IIOP 做远程方法调用，ACP 用 JSON-RPC over stdio 做智能体间通信 |
| gRPC Stub | ACP Client (`ACPService`) | gRPC 通过自动生成的 Stub 调用远程服务，ACP 通过 ACPService 发起智能体交互 |
| EJB Remote Interface | ACP Server mode (`QwenPawACPAgent`) | EJB 通过 Remote Interface 暴露业务方法，ACP Server 模式通过 prompt/new_session 暴露智能体能力 |
| `@Remote` 注解 | ACP Tool 模式 | `@Remote` 标记可远程调用的 EJB 接口，ACP Tool 模式让 QwenPaw 调用外部智能体的工具 |
| JNDI Lookup | Service Registry / `get_acp_service()` | JNDI 通过名字查找远程对象，ACP 通过全局单例 `get_acp_service()` 获取服务实例 |

### 关键差异

Java RMI 要求接口必须继承 `Remote`、方法必须声明 `RemoteException`，且依赖 Java 序列化；ACP 使用 JSON-RPC over stdio，语言无关且无需预定义接口。此外，ACP 内置了 `SuspendedPermission` 权限挂起机制（approve/deny/modify），这在 Java RMI 中没有对应概念，需要开发者自行实现安全拦截。

---

## 知识检查

1. **双重角色**：QwenPaw 在 ACP 协议中可以扮演哪两种角色？请分别描述 ACP Server 模式和 ACP Tool 模式下，QwenPaw 是请求的发起方还是接收方。

2. **流式追踪**：`_StreamTracker` 通过 `_seen_tool_calls` 集合追踪已发送的工具调用 ID。如果不使用追踪器，在流式响应场景下会出现什么问题？请举例说明重复发送的后果。

3. **会话锁定**：`Conversation` 类中的 `turn_lock` 防止同一会话的并发 prompt。如果去掉这个锁，两个并发请求同时调用 `run_turn()` 会发生什么？

---

## 10. Contributor 指南

### 10.1 适合新手修改的文件

| 文件 | 难度 | 原因 |
|------|------|------|
| `app/acp/core.py` 的消息格式定义 | ⭐ | 稳定的协议定义 |
| `app/acp/permissions.py` 的权限检查 | ⭐ | 规则式逻辑 |
| `app/acp/client.py` 的 HTTP 客户端 | ⭐⭐ | 需要理解异步HTTP |

### 10.2 危险区域（绝对不要轻易修改）

| 文件/模块 | 危险原因 |
|-----------|----------|
| `app/acp/core.py` 的消息序列化格式 | 错误会导致跨语言通信失败 |
| `app/acp/permissions.py` 的 SuspendedPermission | 错误会导致安全机制失效 |
| `app/acp/conversation.py` 的 `turn_lock` | 错误会导致会话数据错乱 |

### 10.3 调试方法

**测试 ACP 消息发送**
```python
from qwenpaw.app.acp import ACPService, get_acp_service

service = get_acp_service()
result = await service.send_message(
    target="agent-1",
    message={"type": "ping", "content": "test"}
)
print(f"Response: {result}")
```

**测试会话锁定**
```python
from qwenpaw.app.acp.conversation import Conversation

conv = Conversation("session-1")
async with conv.turn_lock:
    # 同期会话访问
    result = await conv.run_turn("user-1", "hello")
```

**测试权限检查**
```python
from qwenpaw.app.acp.permissions import SuspendedPermission

perm = SuspendedPermission(
    tool_name="write_file",
    tool_args={"path": "/tmp/test"}
)
print(f"Permission suspended: {perm}")
```

### 10.4 如何避免破坏架构

**ACP 协议原则**：
- 消息格式必须向后兼容，升级协议要考虑老版本客户端
- JSON-RPC over stdio 是核心协议，不能随意修改
- 消息必须有唯一 ID，用于追踪和去重

**权限管理原则**：
- SuspendedPermission 机制不能被绕过
- 权限检查必须在每次工具调用前执行
- 超时后的权限必须自动撤销

**会话管理原则**：
- 同一会话的并发 prompt 必须被锁保护
- 流式响应必须追踪已发送的 tool_call_id
- 会话状态必须持久化以支持重连

**测试要求**：
- ACP 协议必须测试消息丢失、重复、乱序场景
- 权限管理必须测试各种边界情况
- 会话必须测试并发访问和断线重连

---

## 延伸阅读

- [14-多智能体协作](./14-多智能体协作.md) -- 多智能体协作的整体架构与设计模式
