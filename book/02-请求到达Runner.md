# 第二章 请求到达 Runner

```
浏览器 ─→ HTTP ─→ [Runner 调度] ─→ Agent ─→ Prompt ─→ ReAct ─→ LLM ─→ Tool ─→ 响应
                         |
                      你在这里
```

## 问题：请求到了 Python 代码之后，怎么找到正确的 Agent？

上一章，我们跟着一条 HTTP 请求穿过了中间件和路由，最后到达了 `post_console_chat()` 函数。但那个函数并不是"干活的"——它只是个入口。真正处理你的消息、调用 AI 模型、生成回答的，是藏在更深处的一个叫"Agent"的东西。

问题来了：系统里可能同时有好几个 Agent 在运行（比如一个帮你写代码的"编程助手"，一个帮你查资料的"研究助手"）。你的请求进来之后，系统怎么知道该把它交给哪个 Agent？又是谁在负责这个"分发"的工作？

答案就是这一章的主角：**Runner**。

Runner 就像一个快递分拣中心的调度员。每个请求到了它手里，它要先弄清楚"这个包裹该送到哪个站点"，然后把请求准确地送过去。如果对应站点的 Agent 还没上班（还没启动），Runner 还得负责把它叫醒。

准备好了吗？让我们走进分拣中心，看看一条请求是怎么被"分发"出去的。

---

## 术语其实很简单

> **术语：Runner**
> 想象一家大公司里的"总调度台"。客户打来电话（请求），总调度台不直接处理业务，而是根据客户要办的事情（agent_id），把电话转接到对应的业务部门（Agent）。Runner 就是这个总调度台——它自己不"思考"，只负责"找到正确的人"。

> **术语：Session（会话状态）**
> 想象你去理发店——理发师会记住你上次剪的发型、聊到一半的话题。Session 就是 Agent 的"记事本"，它把每次对话的上下文保存下来。下次你来的时候，Agent 翻开记事本，就知道之前聊过什么。没有 Session，每次对话都是失忆的——Agent 不知道你是谁，也不知道之前说过什么。

> **术语：命令分发**
> 想象你在聊天框里输入了 `/help`——这不是一条普通消息，而是一条"指令"。命令分发就像手机上的快捷指令：系统看到以 `/` 开头的消息，就知道这不是要跟 AI 聊天，而是要执行某个特定的操作（比如重启、压缩记忆、查看技能列表）。普通消息走"AI 对话"通道，命令走"直接执行"通道——两条路，一个入口。

---

## 探索：追踪 Runner 的调度过程

### 第一步：从路由函数到 DynamicMultiAgentRunner

上一章我们看到，`post_console_chat()` 会在处理请求时调用 `get_agent_for_request()` 来找到对应的 Agent 工作区。但这只是其中一条路径。对于 `/api/agent` 路径下的请求（由 agentscope 框架的 AgentApp 管理），走的是另一条路。

让我们打开 `src/qwenpaw/app/_app.py`，看看这条路是怎么开始的：

```python
# 全局唯一的"动态 Runner"
runner = DynamicMultiAgentRunner()

agent_app = AgentApp(
    app_name="Friday",
    runner=runner,          # 把动态 Runner 传给框架
    enable_stream_task=True,
    stream_task_queue="stream_query",
)
```

这里有个关键的类：`DynamicMultiAgentRunner`。它的名字就告诉我们它干什么——动态地、根据请求的内容，把任务"分发"给正确的 Agent。

在 agentscope 框架里，`AgentApp` 处理的请求最终都会调用 `runner.stream_query()` 方法。QwenPaw 把这个 `runner` 替换成了自己的 `DynamicMultiAgentRunner`，这样就能在框架调用时"拦截"请求，先做分发，再交给真正的 Runner。

### 第二步：stream_query——分发入口

下面是 `DynamicMultiAgentRunner.stream_query()` 的核心逻辑（`_app.py` 第 126 行），我用伪代码展示：

```python
async def stream_query(self, request, *args, **kwargs):
    # 1. 找到正确的工作区（Workspace）
    workspace = await self._get_workspace(request)
    runner = workspace.runner

    # 2. 在 TaskTracker 上登记这个任务
    run_key = f"ext-{uuid.uuid4().hex}"
    await workspace.task_tracker.register_external_task(run_key)

    # 3. 把请求转给真正的 Runner
    async for item in runner.stream_query(request, *args, **kwargs):
        yield item

    # 4. 任务完成，取消登记
    await workspace.task_tracker.unregister_external_task(run_key)
```

四步，非常清晰。让我们逐一看。

**第 1 步**是核心——`_get_workspace(request)` 负责找到正确的 Workspace。这是我们追踪的重点。

**第 2 步**的 TaskTracker 是个安全网——它记录"现在有一个请求正在处理中"。为什么需要这个？想象你正在和 Agent 聊天，突然有人发了 `/restart` 命令要重启 Agent。TaskTracker 会告诉重启逻辑："等一下，还有人在用呢！"这样就能做到零停机重启。后面我们会再看到它。

**第 3 步**把请求转给了真正的 Runner（`AgentRunner`），我们稍后会深入看它。

### 第三步：找到正确的 Workspace——_get_workspace

让我们看看 `_get_workspace` 是怎么工作的（`_app.py` 第 86 行）：

```python
async def _get_workspace(self, request):
    # 从上下文中获取 agent_id
    agent_id = get_current_agent_id()

    # 通过 MultiAgentManager 拿到 Workspace
    workspace = await self._multi_agent_manager.get_agent(agent_id)
    return workspace
```

短短几行，但背后藏着一个精巧的设计。首先，`get_current_agent_id()` 从"上下文变量"中读取 agent_id——这个值是上一章讲的 `AgentContextMiddleware` 在中间件阶段设置好的。所以请求还没到 Runner，中间件就已经帮它贴好了"我要找 default 这个 Agent"的标签。

然后，关键来了：`MultiAgentManager.get_agent(agent_id)`。这个方法负责根据 agent_id 找到或创建对应的 Workspace。

### 第四步：MultiAgentManager——懒加载的艺术

打开 `src/qwenpaw/app/multi_agent_manager.py`，找到 `get_agent` 方法（第 42 行）。这是整个调度系统最精巧的部分：

```python
async def get_agent(self, agent_id: str) -> Workspace:
    # 快速路径：已经加载过了（无需加锁）
    if agent_id in self.agents:
        return self.agents[agent_id]

    should_start = False
    event = None

    async with self._lock:
        # 锁内再检查一次（可能其他协程刚加载完）
        if agent_id in self.agents:
            return self.agents[agent_id]

        if agent_id in self._pending_starts:
            # 别人正在启动这个 Agent，我等它就好
            event = self._pending_starts[agent_id]
        else:
            # 我是第一个请求者，我来启动
            event = asyncio.Event()
            self._pending_starts[agent_id] = event
            should_start = True

    if not should_start:
        await event.wait()          # 等别人启动完
        return self.agents[agent_id]

    # 在锁外面做耗时的启动工作
    instance = Workspace(agent_id=agent_id, ...)
    await instance.start()

    async with self._lock:
        self.agents[agent_id] = instance  # 放入缓存
    event.set()                     # 通知等待的人
    return instance
```

这个方法的精妙之处在于一种叫做**"双重检查锁定 + 事件协调"**的模式。让我们一步步拆解。

**第一次检查（锁外快速路径）**：如果 Agent 已经在内存里了，直接返回。绝大多数请求会走这条路——毕竟 Agent 只需启动一次，之后成千上万的请求都只是查字典。而且这一步连锁都不加，速度极快。

**第二次检查（锁内）**：如果第一次没命中，就得加锁了。但加锁后又检查一遍——为什么？因为可能有多个请求同时到达，在你等锁的时候，别人可能已经把 Agent 加载好了。

**事件协调**：如果锁内检查发现别人已经在启动这个 Agent 了（`_pending_starts` 里有记录），就不重复启动了，而是等一个"事件"（`asyncio.Event`）。事件就像一个信号灯——第一个请求者在启动完成后会"亮灯"（`event.set()`），其他等待的请求看到灯亮了就知道可以继续了。

**锁外启动**：最精妙的一步——创建和启动 Workspace 是很耗时的（可能需要好几秒），但这段代码放在锁的外面。这意味着在启动一个 Agent 的同时，其他 Agent 的请求完全不受影响。

让我们用一个时间线图来看清楚整个过程：

```
                    时间 ──→

请求 A (agent_id=default)
  │ get_agent("default")
  │ 第一次检查: 缓存没有
  │ 加锁 → 第二次检查: 没有 → 标记"我来启动"
  │ 释放锁
  │ 创建 Workspace...  (耗时 3 秒)
  │ 加锁 → 放入缓存
  │ 释放锁
  │ event.set() ←── 通知等待者
  │ 返回 Workspace
  │
请求 B (agent_id=default)       请求 C (agent_id=qa)
  │ get_agent("default")          │ get_agent("qa")
  │ 第一次检查: 缓存没有          │ 第一次检查: 缓存没有
  │ 加锁 → 发现 pending           │ 加锁 → 没有 → 标记"我来启动"
  │ 释放锁                        │ 释放锁
  │ await event.wait()            │ 创建 Workspace... (耗时 2 秒)
  │   ... 等待 ...                │ 加锁 → 放入缓存
  │   ... 等待 ...                │ 释放锁
  │ ← 被唤醒                      │ event.set()
  │ 返回 Workspace                │ 返回 Workspace
```

注意看：请求 B 在等待 A 的同时，请求 C 完全独立地启动了自己的 Agent。这就是"锁外启动"的好处——不同的 Agent 可以并行启动，互不阻塞。

### 第五步：Workspace——Agent 的"工作间"

`get_agent` 返回的是一个 `Workspace` 对象。Workspace 是什么？它就是一个 Agent 的"工作间"——里面住着 Agent 运行所需的所有组件。

打开 `src/qwenpaw/app/workspace/workspace.py`（第 49 行），可以看到 Workspace 的"居民清单"：

```python
class Workspace:
    # Runner：处理请求
    runner: AgentRunner
    # ChannelManager：管理通信频道（控制台、钉钉、Telegram 等）
    channel_manager: ChannelManager
    # MemoryManager：管理对话记忆
    memory_manager: BaseMemoryManager
    # MCPManager：管理外部工具连接
    mcp_manager: MCPClientManager
    # CronManager：管理定时任务
    cron_manager: CronManager
    # TaskTracker：追踪正在运行的任务
    task_tracker: TaskTracker
```

每个 Workspace 都是独立的——一个 Agent 的记忆不会和另一个 Agent 混在一起，一个 Agent 的定时任务不会影响另一个 Agent。这就是为什么 `get_agent` 必须准确地找到正确的 Workspace——找错了，你就跟错误的 Agent 聊天了。

### 第六步：请求到达 AgentRunner

回到 `stream_query`，拿到 Workspace 后，请求被转给了 `workspace.runner`——也就是 `AgentRunner` 的实例。

`AgentRunner`（`src/qwenpaw/app/runner/runner.py` 第 130 行）继承自 agentscope 框架的 `Runner` 基类。它的核心方法是 `query_handler`（第 408 行），这是所有请求最终到达的地方。

`query_handler` 把一次请求分成 12 个阶段按顺序执行：

```
Stage 1:  工具守卫审批检查    ← 有待审批的工具调用？处理它
Stage 2:  命令路由            ← /command？走命令路径
Stage 3:  Agent 上下文设置    ← 设置 contextvars（agent_id, session_id）
Stage 4:  Agent 构建准备      ← 环境上下文、MCP 客户端、加载配置
Stage 5:  Mission Mode 检测   ← /mission 命令或活跃任务？
Stage 6:  Agent 实例化        ← 每次请求新建 QwenPawAgent（热重载关键）
Stage 7:  聊天自动注册        ← ChatManager 创建/更新会话记录
Stage 8:  技能注入            ← /skillname [input] 格式？
Stage 9:  会话状态加载        ← 从 JSON 文件恢复记忆
Stage 10: 执行               ← 流式调用 Agent
Stage 11: 错误处理            ← 异常转换、写错误转储
Stage 12: 清理               ← 保存会话状态、更新时间戳
```

Stage 6 最值得关注：**每次请求都新建一个 Agent 实例**。这意味着你改了配置文件，下一次对话立刻生效——不需要重启服务器。代价是每次请求都有初始化开销，但因为大部分时间花在等 LLM 响应上，这个代价可以接受。

让我用伪代码展示主干逻辑：

```python
async def query_handler(self, msgs, request=None, **kwargs):
    query = 提取最后一条用户消息文本
    session_id = request.session_id

    # 检查是否有待处理的工具审批
    if 有待审批的工具调用(session_id):
        yield 审批结果
        return

    # 检查是否是命令（以 / 开头）
    if query and _is_command(query):
        async for msg in run_command_path(request, msgs, self):
            yield msg
        return

    # 否则：正常对话流程
    agent = 创建 QwenPawAgent(...)
    加载 Session 状态到 agent
    agent.rebuild_sys_prompt()

    async for msg in agent(msgs):   # 调用 Agent
        yield msg

    保存 Session 状态
```

这里有一条清晰的三岔路口：

1. **审批路径**：如果之前有一个工具调用在等你批准（比如 Agent 想执行一条 Shell 命令），你的回复会直接走到审批逻辑。

2. **命令路径**：如果你的消息以 `/` 开头（比如 `/compact`、`/restart`），它会走命令分发——不经过 AI，直接执行对应的操作。

3. **对话路径**：普通的聊天消息走这条路——创建 Agent、加载记忆、调用 LLM。

让我们重点看看命令分发，因为它是 Runner 层最有趣的设计之一。

### 第七步：命令分发——消息的分岔口

打开 `src/qwenpaw/app/runner/command_dispatch.py`，看看命令是怎么被识别和分发的。

首先是识别。`_is_command` 函数（第 65 行）检查一条消息是不是命令：

```python
def _is_command(query: str | None) -> bool:
    if not query or not query.startswith("/"):
        return False
    if parse_daemon_query(query) is not None:  # /daemon 命令
        return True
    if _is_control_command(query):              # /stop 等控制命令
        return True
    return _is_conversation_command(query)      # /compact、/new 等
```

命令有三层优先级：

```
/daemon restart     →  守护进程命令（最高优先级）
/stop               →  控制命令
/compact            →  对话命令
普通文字             →  不是命令，走 AI 对话
```

识别出命令后，`run_command_path` 函数负责执行。它的逻辑也很清晰：

```python
async def run_command_path(request, msgs, runner):
    query = 提取最后一条用户消息

    if 是守护进程命令(query):
        yield 执行守护进程命令(query)
        return

    if 是控制命令(query):
        yield 执行控制命令(query)
        return

    # 对话命令（/compact、/new 等）
    yield 执行对话命令(query)
```

每一类命令有自己的处理逻辑，但共同点是：**它们都不会创建 Agent，不会调用 LLM**。命令分发是"轻量级"的——直接执行操作，然后返回结果。这比每次都让 AI 处理要快得多，也省得多花 Token 费用。

### 第八步：Session——Agent 的记事本

当请求走的是"对话路径"时，一个关键步骤是加载和保存 Session 状态。让我们看看 Session 是什么。

打开 `src/qwenpaw/app/runner/session.py`，你会看到 `SafeJSONSession` 类（第 78 行）。它的核心工作就是把 Agent 的状态保存到 JSON 文件中：

```python
class SafeJSONSession(SessionBase):
    save_dir = "./"

    def _get_save_path(self, session_id, user_id):
        # 文件名格式: {user_id}_{session_id}.json
        safe_sid = sanitize_filename(session_id)
        safe_uid = sanitize_filename(user_id)
        return os.path.join(self.save_dir, f"{safe_uid}_{safe_sid}.json")

    async def save_session_state(self, session_id, user_id, **state):
        # 把状态序列化为 JSON 写入文件
        state_dicts = {name: m.state_dict() for name, m in state.items()}
        写入 JSON 文件

    async def load_session_state(self, session_id, user_id, **state):
        # 从 JSON 文件恢复状态
        states = _safe_json_loads(读取文件内容)
        for name, m in state.items():
            m.load_state_dict(states[name])
```

每个对话都有一个对应的 JSON 文件，存放在工作目录的 `sessions/` 文件夹下。文件名由 `user_id` 和 `session_id` 组合而成。它的生命周期是这样的：

```
Session 生命周期：

用户发送第一条消息
  │
  ├── Runner 初始化 Session (init_handler)
  │     session = SafeJSONSession(save_dir="sessions/")
  │
  ├── query_handler 被调用
  │     │
  │     ├── load_session_state()  ← 从文件恢复记忆
  │     │     如果文件存在：读取 JSON，恢复到 agent 的 memory
  │     │     如果文件不存在：从空状态开始
  │     │
  │     ├── Agent 处理对话（可能产生新的记忆）
  │     │
  │     └── save_session_state()  ← 保存到文件
  │           把 agent 当前状态写入 JSON
  │
  ├── 用户发送第二条消息
  │     └── 重复上述过程
  │
  ...（持续整个对话生命周期）
```

这里有个细节值得注意：`_safe_json_loads` 函数做了容错处理。它的三层恢复策略是这样的：

```
第 1 层: json.loads()           ← 正常解析，绝大多数情况走这条路
第 2 层: raw_decode()           ← JSON 末尾有垃圾？提取第一个有效对象
第 3 层: 返回空字典 {}           ← 完全救不回来，从头开始
```

第 2 层特别有用——并发写入（两个协程同时写同一个文件）或进程异常终止（写了一半被 kill）是 JSON 损坏的常见原因。`raw_decode` 能从 `"{"a":1}{"b":2}"` 或 `"{"messages": [{"content": "hello` 这样的残缺内容中抢救出第一个有效对象。这个设计很实用——你不会因为一个损坏的文件而丢失整个对话。

另外，文件名用到了 `sanitize_filename` 函数，把 Windows 不允许的字符（`: * ? " < > |`）替换成 `--`。这样同一个代码在 Windows、macOS、Linux 上都能正常运行。

### 补充：query_handler 的 12 阶段管道

前面用伪代码展示了 `query_handler` 的主干逻辑（审批、命令或对话三岔路口），但实际的请求处理要精细得多——它分为 12 个阶段：

| 阶段 | 名称 | 要点 |
|------|------|------|
| 1 | 工具守卫审批 | 检查是否有待审批的工具调用，超时自动拒绝 |
| 2 | 命令路由 | `_is_command()` 检测 `/` 开头的消息 |
| 3 | Agent 上下文 | 通过 contextvars 设置 agent_id、session_id |
| 4 | Agent 构建 | 加载配置、MCP 客户端、环境上下文 |
| 5 | Mission 检测 | 检查 `/mission` 命令或活跃的 mission phase |
| 6 | Agent 实例化 | **每次请求新建 QwenPawAgent**（保证热重载即时生效） |
| 7 | 聊天注册 | ChatManager 自动创建/更新会话记录 |
| 8 | 技能注入 | `/<skill_name>` 格式解析，合并技能体到用户消息 |
| 9 | Session 加载 | 从 JSON 文件恢复历史，然后 `rebuild_sys_prompt()` |
| 10 | 执行 | 标准 ReAct 循环或 Mission 分阶段执行 |
| 11 | 错误处理 | 异常分类转换，写入 error dump 文件 |
| 12 | 清理 | finally 块保存 Session、更新 chat 时间戳 |

阶段 6 是一个关键的设计决策：每次请求都创建新的 Agent 实例，而不是复用。这看起来有开销，但保证了配置变更（系统提示词、工具集、MCP 客户端）的即时生效——不需要重启或重建实例。会话状态通过 SafeJSONSession 持久化，不依赖 Agent 实例的生命周期。

### 补充：ServiceManager 优先级启动

前面提到的 Workspace 包含 Runner、ChannelManager、MemoryManager 等多个组件。这些组件不是随意启动的——Workspace 内部的 `ServiceManager` 按优先级分组管理启动顺序：

| 优先级 | 服务 | 说明 |
|--------|------|------|
| 10 | Runner | AgentRunner，请求处理核心 |
| 20 | MemoryManager、MCPManager、ChatManager | 可并发启动，支持热重载复用 |
| 25 | Runner 启动 | 依赖 P20 的服务就绪后才能开始处理 |
| 30 | ChannelManager | 消息渠道管理 |
| 40 | CronManager | 定时任务（依赖 Runner 和 Channel） |
| 50-51 | 配置监听器 | Agent 和 MCP 配置变更监控 |

同优先级的服务并发启动（用 `asyncio.gather`），不同优先级串行等待。这保证了 Runner 在 MemoryManager 之前就绪，而 CronManager 在 Runner 和 ChannelManager 之后才启动——因为定时任务的执行依赖它们。

### 第九步：TaskTracker——并发请求的调度员

最后让我们看看 `TaskTracker`（`src/qwenpaw/app/runner/task_tracker.py` 第 34 行）。它的职责是管理"正在运行的任务"。

前面我们提到，`DynamicMultiAgentRunner.stream_query` 会在 TaskTracker 上登记每个请求。它的核心方法是 `attach_or_start`（第 198 行），让我用伪代码展示：

```python
async def attach_or_start(self, run_key, payload, stream_fn):
    async with self._lock:
        # 如果已经有在跑的任务
        if 有运行中的任务(run_key):
            q = 创建新队列()
            把已发送的事件缓冲复制到 q    # 回放
            挂接 q 到任务
            return q, False               # 不是新任务

        # 否则，启动新任务
        my_queue = 创建新队列()
        异步启动:
            async for event in stream_fn(payload):
                把 event 放入所有订阅者的队列
                同时存入事件缓冲          # 供后来的订阅者回放
        return my_queue, True              # 是新任务
```

这个方法解决了两个问题：

1. **断线重连**：如果你刷新了页面，新请求会带着同一个 `run_key`（即 chat_id）进来。`attach_or_start` 发现任务还在跑，就不再启动新的了，而是把已有的事件缓冲回放给你，然后让你继续接收后续事件。

2. **多订阅者**：理论上可以有多个客户端同时观看同一个对话的输出（比如你同时在电脑和手机上打开同一个聊天窗口）。每个客户端都有自己的队列，但共享同一个后台任务。

### 全景：Runner 调度流程图

让我们把整个过程画成一张完整的流程图：

```
请求到达
  │
  v
DynamicMultiAgentRunner.stream_query()
  │
  ├── _get_workspace(request)
  │     │
  │     ├── get_current_agent_id()  ← 从上下文变量取 agent_id
  │     │
  │     └── MultiAgentManager.get_agent(agent_id)
  │           │
  │           ├── 缓存命中？ → 直接返回 Workspace
  │           │
  │           └── 缓存未命中？ → 创建并启动 Workspace
  │                 │
  │                 ├── 加锁 → 检查 pending → 标记启动
  │                 ├── 释放锁 → 创建 Workspace（耗时）
  │                 ├── 加锁 → 放入缓存
  │                 └── event.set() → 通知等待者
  │
  ├── TaskTracker.register_external_task(run_key)
  │
  └── workspace.runner.stream_query(request)
        │
        └── AgentRunner.query_handler(msgs, request)
              │
              ├── 有待审批的工具调用？ → 审批路径
              │
              ├── _is_command(query)？ → 命令分发
              │     ├── /daemon 命令 → 守护进程处理
              │     ├── /stop 等命令 → 控制命令处理
              │     └── /compact 等 → 对话命令处理
              │
              └── 普通消息 → 对话路径
                    ├── 创建 QwenPawAgent
                    ├── load_session_state()  ← 恢复记忆
                    ├── rebuild_sys_prompt()
                    ├── Agent 处理对话
                    └── save_session_state()  ← 保存记忆
```

---

## 实验：启动 QwenPaw，发送消息，观察 Runner 日志

让我们亲手验证一下上面讲的内容。

### 准备工作

确保 QwenPaw 正在运行，并且日志级别设为 DEBUG（在 `.env` 文件中设置 `QWENPAW_LOG_LEVEL=debug`，然后重启）。DEBUG 级别的日志会显示 Runner 调度的详细过程。

### 观察 Runner 日志

启动 QwenPaw 时，你会看到类似这样的日志（简化版）：

```
DEBUG: MultiAgentManager initialized
INFO:  Server ready in 0.052s (agents loading in background)
DEBUG: Starting agent: default
DEBUG: Creating new workspace: default
DEBUG: Workspace created and started: default (2.341s)
INFO:  Background startup completed in 2.512 seconds
```

注意看时间线：服务器在 0.052 秒就"准备好"了，但 Agent 的加载是在后台进行的，总共花了 2.5 秒。如果在服务器刚启动的 0.052 秒内就有请求进来，`get_agent` 会等待直到 Agent 启动完成。

现在，发送一条消息：

```bash
curl -N -X POST http://127.0.0.1:8088/api/console/chat \
  -H "Content-Type: application/json" \
  -d '{"session_id":"runner-test-1","user_id":"default",\
"input":[{"content":[{"text":"你好","type":"text"}]}]}'
```

在 DEBUG 日志中，你会看到这样一系列输出（简化版）：

```
DEBUG: _get_workspace: agent_id=default
DEBUG: Returning cached agent: default
DEBUG: Got workspace: default, runner: <AgentRunner ...>
DEBUG: DynamicMultiAgentRunner.stream_query called
INFO:  Handle agent query:
       {"session_id": "runner-test-1", "user_id": "default", ...}
```

看——"Returning cached agent: default"说明第二次请求走了快速路径，直接从缓存中拿到了 Workspace。

### 观察命令分发

试试发一条命令：

```bash
curl -N -X POST http://127.0.0.1:8088/api/console/chat \
  -H "Content-Type: application/json" \
  -d '{"session_id":"cmd-test-1","user_id":"default",\
"input":[{"content":[{"text":"/new","type":"text"}]}]}'
```

日志中会出现：

```
INFO:  Command path: /new
```

注意，这条消息不会触发 LLM 调用——它被命令分发直接处理了。

---

## 补充：Workspace 的启动顺序

前面我们看了 Workspace 是怎么被懒加载创建的，但没说它内部是怎么启动的。Workspace 启动时，它内部的各个组件（Runner、MemoryManager、ChannelManager 等）不是一股脑全开的——它们通过 `ServiceManager` 按优先级分组启动：

```
Priority 10: runner           ← 先创建 AgentRunner
Priority 20: memory_manager   ← 然后并发启动记忆、MCP、聊天管理器
            |  mcp_manager    ←  （同优先级用 asyncio.gather 并发）
            |  chat_manager   ←
Priority 25: runner_start     ← 再正式启动 Runner（依赖上面的管理器）
Priority 30: channel_manager  ← 然后启动频道（依赖 Runner）
Priority 40: cron_manager     ← 定时任务（依赖频道）
Priority 50+: 配置监听器      ← 最后启动配置热更新监听
```

核心规则是"同优先级并发，不同优先级串行"。Priority 20 的三个管理器互不依赖，所以并发启动；但 Priority 25 的 runner_start 必须等 Priority 20 的管理器都就绪。这比全部串行启动快，同时保证了依赖关系的正确性。

---

## 工程权衡：为什么这样设计？

### 为什么用懒加载而不是启动时加载所有 Agent？

`MultiAgentManager.get_agent()` 采用了"懒加载"（Lazy Loading）策略——只有在第一次请求到达时才创建和启动 Agent。与之相对的是"急切加载"（Eager Loading）——在服务器启动时就把所有配置的 Agent 都创建好。

懒加载的好处：

1. **启动快**：服务器不需要等所有 Agent 都准备好才能接受请求。如果你配置了 10 个 Agent，每个启动需要 3 秒，急切加载就要等 30 秒。懒加载只启动被用到的 Agent，启动时间几乎为零。

2. **省资源**：如果有些 Agent 很少被用到（比如只在特定场景才需要的"翻译助手"），懒加载就不会浪费内存和 CPU 去维持一个没人用的 Agent。

3. **容错好**：如果某个 Agent 的配置有问题导致启动失败，不会影响其他 Agent。急切加载中，一个 Agent 启动失败可能导致整个服务器无法启动。

懒加载的代价：

1. **首次延迟**：第一个请求到达一个未启动的 Agent 时，需要等它启动完成。不过 QwenPaw 用 `asyncio.Event` 的方式让同一时刻到达的多个请求只需等一次。

2. **复杂度增加**：双重检查锁定、事件协调、pending 状态管理——这些代码比简单的"启动时全加载"要复杂得多。

但综合来看，懒加载是更好的选择。特别是 QwenPaw 支持多 Agent 场景——你可能配置了 5 个 Agent，但常用只有 1 个。懒加载让系统"按需服务"。

QwenPaw 实际上结合了两种策略：服务器启动时会在后台"预加载"所有 enabled 的 Agent（`start_all_configured_agents`），但如果后台加载还没完成就有请求进来了，懒加载机制会确保请求能正确等待或触发加载。

### 为什么 Session 要持久化到文件？

你可能会想：对话记忆为什么不直接放在内存里，而要费劲写入 JSON 文件？

原因很简单：**内存是不可靠的**。如果服务器重启了（比如部署更新、系统维护、或者意外崩溃），内存里的数据就全丢了。如果没有持久化，重启之后 Agent 就会"失忆"——忘了你之前说过什么。

文件持久化的好处是简单、可靠、不需要额外的数据库服务。对于大多数场景（单机部署），这完全够用。

当然，这个选择也有代价：每次对话都要读写文件，如果同时有很多用户在聊天，文件 I/O 可能成为瓶颈。但对于 QwenPaw 目前的使用场景（个人或小团队使用），这不成问题。如果将来需要支持大规模并发，可以考虑换用 Redis 或数据库。

### 为什么命令要单独处理，而不是让 AI 来理解？

你可能会想：让 AI 自己判断 "用户输入 `/compact` 是想压缩记忆" 不就行了吗？为什么要在 Runner 层就拦截下来？

几个原因：

1. **确定性**：命令必须是 100% 可靠的。`/stop` 就是停止，不应该有"AI 理解错了"的情况。把命令放在 Runner 层，用普通代码处理，结果是完全确定的。

2. **速度**：命令处理不需要调用 LLM，响应几乎是瞬时的。如果让 AI 处理，每次执行 `/compact` 都要等好几秒的 LLM 响应。

3. **成本**：每次调用 LLM 都要花钱（Token 费用）。命令是很频繁的操作，如果每次都走 AI，费用会明显增加。

4. **安全性**：`/restart` 这种命令涉及系统操作，不能让 AI 来决定是否执行。必须在代码层面严格控制。

---

## 动手环节：观察 Runner 启动日志

这个练习帮你亲眼看到本章讲的 Runner 调度过程。

### 练习 1：观察 Agent 的懒加载

1. 启动 QwenPaw（确保日志级别为 DEBUG）。
2. 注意看启动日志中的时间线——服务器什么时候开始接受请求？Agent 什么时候加载完成？
3. 如果你配置了多个 Agent，观察它们是并行启动还是串行启动。

### 练习 2：观察 Session 文件

1. 发送一条消息给 Agent，随便聊几句。
2. 找到工作目录下的 `sessions/` 文件夹，打开对应的 JSON 文件（文件名是 `{user_id}_{session_id}.json`）。
3. 看看里面的内容——你能找到你刚才说的话吗？Agent 的回答呢？

### 练习 3：在源码中找到关键代码行

尝试在源码中找到以下内容：

1. 打开 `src/qwenpaw/app/_app.py`，找到第 71 行，看看 `DynamicMultiAgentRunner` 类的定义。
2. 打开 `src/qwenpaw/app/multi_agent_manager.py`，找到第 62 行的快速路径——这就是绝大多数请求走的"缓存命中"分支。
3. 打开 `src/qwenpaw/app/runner/command_dispatch.py`，找到第 65 行的 `_is_command` 函数——这是命令分发的"分拣窗口"。数一数它检查了几种命令类型。

---

## 小结

这一章，我们跟着请求走过了 Runner 调度层，看到了它是怎么"分发"请求的：

```
请求到达 Python
  │
  v
DynamicMultiAgentRunner.stream_query()
  │
  ├── 找到 agent_id（由中间件提前设置）
  │
  ├── MultiAgentManager.get_agent(agent_id)
  │     ├── 缓存命中？ → 直接返回
  │     └── 未命中？ → 懒加载创建 Workspace
  │           （双重检查锁定 + 事件协调）
  │
  ├── TaskTracker 登记任务
  │
  └── AgentRunner.query_handler()
        │
        ├── 工具审批？ → 审批路径
        ├── /command？ → 命令分发路径
        └── 普通消息？ → 创建 Agent、加载 Session、调用 LLM
```

你学到了：

- **Runner 的角色**：它是请求的"总调度台"，负责把请求路由到正确的 Agent
- **懒加载模式**：Agent 只在第一次被请求时才创建，用双重检查锁定和事件协调保证并发安全
- **命令分发**：以 `/` 开头的消息走专用路径，不经过 LLM，更快更确定
- **Session 持久化**：把对话状态保存到文件，让 Agent 重启后不"失忆"
- **TaskTracker**：追踪正在运行的任务，支持断线重连和零停机重启

下一章，请求已经到达了正确的 Agent。但 Agent 本身是什么？它是怎么被创建出来的？让我们走进 Agent 的"诞生"过程。
