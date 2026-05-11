# 第 2 章：请求到达 Runner

```
Browser -> HTTP -> FastAPI -> [Runner] -> Agent -> Prompt -> ReAct -> LLM -> Tool -> Response
                              ^
                          you are here
```

上一章我们跟请求走到了 `post_console_chat()`——它做了六步准备工作，其中最关键的一步是 `get_agent_for_request(request)`，根据请求找到对应的 Agent 工作空间。这一章，我们跟着这条路往里走，看看"找 Agent"这件事到底有多复杂——涉及 Runner 调度、工作空间管理、命令分发、会话持久化。

---

## 问题

FastAPI 收到请求后，怎么找到正确的 Agent 来处理？如果两个用户同时发消息，它们会不会打架？你发的消息，为什么关掉浏览器再打开还能看到历史记录？

## 术语其实很简单

> **术语：Runner（运行器）**
> 想象一个餐厅的传菜员——前台（FastAPI）把客人点的菜（请求）交给传菜员，传菜员负责协调厨师（Agent）、记住客人坐哪桌（Session）、管理上菜进度（TaskTracker）。Runner 就是这个传菜员。

> **术语：Session（会话）**
> 想象你去常去的理发店——理发师记住了你上次剪什么发型、聊到哪了。Session 就是这种"记忆"——它把你和 Agent 之间的对话历史、上下文状态保存下来，下次来能接着聊。

> **术语：命令分发（Command Dispatch）**
> 想象公司前台接电话——如果对方说"转接销售部"，前台就把电话转过去；如果是普通咨询，就让值班经理接。命令分发就是这种"判断请求类型再路由"的机制——`/` 开头的是命令（如 `/new` 开新对话），其他的是普通消息。

## 探索

### 从 FastAPI 到 Runner——谁来跑这一趟？

上一章结尾，请求被路由到了 `post_console_chat()`。这个函数的第一步是找 Agent 工作空间：

```python
# console.py 中的关键调用
workspace = await get_agent_for_request(request)
```

`get_agent_for_request()` 做了什么？它从请求上下文中取出 Agent ID（上一章的 `AgentContextMiddleware` 设置好的），然后调用 `MultiAgentManager.get_agent(agent_id)`。

`MultiAgentManager` 是整个调度层的"总调度室"。它维护着一个字典：`agent_id → Workspace`。

### Agent 的延迟加载

一个关键设计：**Agent 不是启动时全部加载的，而是第一次被请求时才加载**。

`get_agent()` 的核心逻辑（伪代码）：

```python
async def get_agent(self, agent_id: str) -> Workspace:
    # 快速路径：已经加载过了，直接返回
    if agent_id in self.agents:
        return self.agents[agent_id]

    # 加锁，防止并发重复加载
    async with self._lock:
        # 再次检查（可能别的协程刚加载完）
        if agent_id in self.agents:
            return self.agents[agent_id]

        # 检查是否有其他协程正在加载
        if agent_id in self._pending_starts:
            await self._pending_starts[agent_id].wait()  # 等它加载完
            return self.agents[agent_id]

        # 我来加载
        event = asyncio.Event()
        self._pending_starts[agent_id] = event

    # 在锁外面做慢操作（创建工作空间、启动服务）
    workspace = Workspace(agent_id, workspace_dir)
    await workspace.start()

    # 原子交换
    async with self._lock:
        self.agents[agent_id] = workspace
        event.set()  # 通知等待的人

    return workspace
```

为什么这么复杂？因为 QwenPaw 是异步的——两个请求可能同时到达，同时都要 `get_agent("default")`。如果没有锁和去重，会创建两个相同的工作空间。这个"双重检查锁 + 事件等待"模式确保同一个 Agent 只被加载一次。

### Workspace 里有什么？

`Workspace` 是一个 Agent 的完整工作环境，包含：

```
Workspace
  |-- AgentRunner        # 处理请求的核心对象
  |-- SafeJSONSession    # 会话状态持久化
  |-- ChatManager        # 聊天记录管理
  |-- TaskTracker        # SSE 流式输出协调
  |-- MemoryManager      # 对话记忆管理
  |-- ChannelManager     # 通信频道管理
  +-- MCPClientManager   # MCP 工具客户端
```

每个 Workspace 都有自己的 `AgentRunner`——也就是本章标题说的"Runner"。

### AgentRunner.query_handler——请求处理的核心

`query_handler()` 是 Runner 的核心方法。当请求到达时，它执行以下流程：

```python
async def query_handler(self, msgs, request=None, **kwargs):
    # 1. 检查是否有待审批的工具调用
    if 有待审批的请求:
        return 审批结果

    # 2. 命令分发：如果是 / 开头的命令，走专门的命令处理
    if query.startswith("/") and is_command(query):
        return await run_command_path(request, msgs, self)

    # 3. 加载 Agent 配置和环境上下文
    agent_config = load_agent_config(self.agent_id)

    # 4. 创建 Agent 实例（每次请求都创建新的！）
    agent = QwenPawAgent(agent_config, env_context, ...)

    # 5. 恢复会话状态
    self.session.load_session_state(session_id, user_id, agent=agent)

    # 6. 执行 Agent（流式输出）
    async for msg in agent(msgs):
        yield msg

    # 7. 保存会话状态
    self.session.save_session_state(session_id, user_id, agent=agent)
```

这里有一个反直觉的设计：**Agent 在每次请求时都是全新创建的**。不是复用同一个 Agent 对象。那对话历史怎么保持？靠 Session。

### Session——对话连续性的秘密

`SafeJSONSession` 把每个会话的状态存成一个 JSON 文件：`<workspace>/sessions/<user_id>_<session_id>.json`。

请求处理流程是：

```
请求到达
  -> load_session_state()  # 从 JSON 文件恢复 Agent 状态（记忆、上下文）
  -> 执行 Agent            # Agent 用恢复的状态处理新消息
  -> save_session_state()  # 把新状态写回 JSON 文件
```

这就是为什么你关掉浏览器再打开，Agent 还能"记得"你之前说了什么——状态被持久化到了磁盘上。

### 命令分发——`/` 开头的不走寻常路

如果你发的是 `/new`（开新对话）、`/compact`（压缩记忆）这样的命令，它不会经过 Agent 的正常推理流程。`query_handler` 在第 2 步就会拦截：

```python
if query.startswith("/") and is_command(query):
    return await run_command_path(request, msgs, self)
```

命令分发的优先级：
1. **守护命令**（`/daemon restart` 等）——管理级命令
2. **控制命令**（`/stop` 等）——控制当前会话
3. **对话命令**（`/new`、`/compact` 等）——操作对话状态

普通消息不匹配任何命令，才会走到第 3 步创建 Agent 并执行推理。

### TaskTracker——并发请求的协调员

当多个用户同时给同一个 Agent 发消息时，`TaskTracker` 负责协调。它为每个运行中的任务维护一个"订阅者列表"：

```
TaskTracker
  +-- run_key (chat_id)
        |-- asyncio.Task     # 后台运行的任务
        |-- queues: [Q1, Q2] # 多个 SSE 订阅者
        +-- buffer: [...]    # 已发送的事件缓冲
```

`attach_or_start()` 是它的核心方法：
- 如果这个聊天已经在运行（比如用户刷新了页面），创建一个新的订阅队列，回放缓冲，继续接收
- 如果没运行，启动新任务

这就是第 1 章提到的"断线重连"的具体实现——`buffer` 里存着所有已发送的事件，新订阅者先看回放再看直播。

## 实验

启动 QwenPaw，发一条消息，然后在终端观察 Runner 的行为：

```bash
# 用 debug 级别启动，能看到更详细的调度日志
qwenpaw app --log-level debug
```

然后在浏览器发一条消息。在终端中观察类似这样的日志：

预期输出：

```
DEBUG: DynamicMultiAgentRunner.stream_query called
DEBUG: Got workspace: default, runner: <AgentRunner ...>
DEBUG: _get_workspace: agent_id=default
```

能看到请求从 `DynamicMultiAgentRunner` 路由到 `AgentRunner` 的完整日志链。

## 工程权衡

### 为什么用延迟加载而不是启动时全部加载？

QwenPaw 支持配置多个 Agent，但不是每个都会被用到。如果启动时全部加载，一个配置了 10 个 Agent 但只用了 2 个的系统会浪费大量内存和初始化时间。延迟加载让系统"按需启动"——启动速度快，资源占用少。代价是第一次请求某个 Agent 时会有短暂的初始化延迟。

### 为什么每次请求都创建新的 Agent 实例？

复用 Agent 对象看似更高效，但 Agent 在推理过程中会修改内部状态（消息历史、工具调用结果等）。如果多个请求共享同一个 Agent，状态会互相污染。每次创建新实例 + Session 持久化/恢复，确保了请求之间的完全隔离——不用担心并发问题。

## 常见误区

> **误区：Agent 实例是常驻内存、被所有请求共享的吗？**
>
> 有人以为系统启动时创建一个 Agent 对象，然后所有请求排队使用它。实际上 `AgentRunner` 在每次请求时都创建一个全新的 `QwenPawAgent`。对话历史不是靠"Agent 一直活着"来维持的，而是靠 `SafeJSONSession` 把状态存到 JSON 文件里，每次请求前加载、请求后保存。这种设计避免了并发状态污染的问题。

## 动手环节

**任务**：追踪一个请求从 FastAPI 到 AgentRunner 的完整调度路径。

**步骤**：
1. 用 `qwenpaw app --log-level debug` 启动 QwenPaw
2. 在浏览器发一条消息
3. 在终端日志中找到包含 `DynamicMultiAgentRunner`、`AgentRunner`、`query_handler` 的行
4. 打开 `src/qwenpaw/app/runner/runner.py`，在 IDE 中搜索 `query_handler` 方法

**预期输出**：
终端日志中能看到请求经过的调度路径：`stream_query → _get_workspace → query_handler`

**自检**：
- [ ] 能在 `runner.py` 中找到 `query_handler` 方法的定义
- [ ] 理解 Agent 不是复用的，而是每次请求创建新的
- [ ] 知道 Session 的作用是把状态持久化到 JSON 文件

---

请求现在到达了 `AgentRunner`，它创建了一个全新的 `QwenPawAgent`。这个 Agent 是怎么被创建出来的？为什么它继承了一个叫 `ToolGuardMixin` 的东西？下一章我们走进 Agent 的诞生过程。
