# Workspace 隔离机制

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 解释 Workspace 隔离的设计原理 2) 分析 ServiceManager 的服务编排机制 3) 理解多 Agent 环境下的资源隔离 |
| **前置知识** | [项目架构](./03-项目架构.md)、[智能体核心架构](./07-智能体核心架构.md) |
| **预计时长** | 40 分钟（阅读 25 + 练习 15） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `Workspace` `ServiceManager` `隔离` |

> **一句话概述**：每个 Agent 运行在独立的 Workspace 中，通过目录隔离、服务隔离和声明式 ServiceManager 实现多租户资源隔离与零停机热重载。

## 概述

QwenPaw 支持多智能体（Multi-Agent），每个 Agent 运行在独立的 **Workspace** 中，实现资源隔离、热重载和零停机重配置。本章解析 Workspace 的目录隔离、服务隔离、热重载机制和完整的组件关系图。

**源码路径**: `src/qwenpaw/app/workspace/`

---

## 1. Workspace 类的结构

源码路径：`src/qwenpaw/app/workspace/workspace.py`

### 1.1 核心属性

```python
# src/qwenpaw/app/workspace/workspace.py:49
class Workspace:
    """Single agent workspace with complete runtime components."""

    def __init__(self, agent_id: str, workspace_dir: str):
        self.agent_id = agent_id
        self.workspace_dir = Path(workspace_dir).expanduser()
        self.workspace_dir.mkdir(parents=True, exist_ok=True)

        # Service manager (统一组件生命周期管理)
        self._service_manager = ServiceManager(self)

        # 非服务状态
        self._config = None          # 延迟加载
        self._started = False
        self._manager = None         # MultiAgentManager 引用
        self._task_tracker = TaskTracker()

        # 注册所有服务
        self._register_services()
```

### 1.2 服务属性（通过 ServiceManager 委托）

```python
# src/qwenpaw/app/workspace/workspace.py:90
@property
def runner(self) -> Optional[AgentRunner]:
    return self._service_manager.services.get("runner")

@property
def memory_manager(self):
    return self._service_manager.services.get("memory_manager")

@property
def mcp_manager(self):
    return self._service_manager.services.get("mcp_manager")

@property
def chat_manager(self):
    return self._service_manager.services.get("chat_manager")

@property
def channel_manager(self):
    return self._service_manager.services.get("channel_manager")

@property
def cron_manager(self):
    return self._service_manager.services.get("cron_manager")
```

---

## 2. 隔离层次

### 2.1 目录级隔离

每个 Agent 拥有独立的工作空间目录：

```
~/.qwenpaw/
├── config.json                    # 根配置
├── default/                       # default agent workspace
│   ├── agent.json                # Agent 配置
│   ├── chats.json                # 聊天记录
│   ├── jobs.json                 # 定时任务
│   └── sessions/                 # 会话状态文件
│       └── *.json
├── agent-2/                      # agent-2 workspace
│   ├── agent.json
│   ├── chats.json
│   ├── jobs.json
│   └── sessions/
└── agent-3/                     # agent-3 workspace
    └── ...
```

### 2.2 服务级隔离

每个 Workspace 有独立的服务实例：

| 服务 | 隔离意义 |
|------|---------|
| `AgentRunner` | 每个 Agent 有独立的请求处理器 |
| `BaseMemoryManager` | 每个 Agent 有独立的记忆存储 |
| `MCPClientManager` | 每个 Agent 有独立的 MCP 客户端 |
| `ChatManager` | 每个 Agent 有独立的聊天记录管理 |
| `ChannelManager` | 每个 Agent 有独立的频道连接 |
| `CronManager` | 每个 Agent 有独立的定时任务调度器 |

### 2.3 ServiceManager — 声明式服务配置

源码路径：`src/qwenpaw/app/workspace/service_manager.py:32`

```python
@dataclass
class ServiceDescriptor:
    """服务描述符 — 声明式服务配置"""
    name: str                      # 服务唯一标识
    service_class: type             # 服务类
    init_args: Callable            # 初始化参数函数
    post_init: Callable            # 创建后钩子
    start_method: str             # 启动方法名
    stop_method: str               # 停止方法名
    reusable: bool                # 是否可在重载时复用
    priority: int                 # 启动优先级
    concurrent_init: bool         # 是否可并发初始化
```

**优先级驱动的启动顺序**：

```
Priority 10:  Runner
Priority 20:  Core services (memory_manager, mcp_manager, chat_manager) — 并发
Priority 25:  Runner.start()
Priority 30:  Channel manager
Priority 40:  Cron manager
Priority 50:  Agent Config Watcher (条件)
Priority 51:  MCP Config Watcher (条件)
```

---

## 3. Workspace 与 Runner 的关系

### 3.1 组件关系图

```
Workspace
  └── _service_manager.services["runner"] = AgentRunner
        ├── agent_id: str
        ├── workspace_dir: Path
        ├── memory_manager
        ├── _chat_manager
        ├── _mcp_manager
        └── _workspace = Workspace  ← 反向引用
```

### 3.2 双向引用链

```python
# workspace.py — Workspace 创建并注册 Runner
sm.register(ServiceDescriptor(
    name="runner",
    service_class=AgentRunner,
    init_args=lambda ws: {
        "agent_id": ws.agent_id,
        "workspace_dir": ws.workspace_dir,
        "task_tracker": ws._task_tracker,
    },
    stop_method="stop",
    priority=10,
))

# runner.py — Runner 持有 Workspace 引用
def set_workspace(self, workspace):
    self._workspace = workspace
```

---

## 4. Workspace 与 ChannelManager 的关系

### 4.1 注入机制

源码路径：`src/qwenpaw/app/workspace/service_factories.py`

```python
async def create_channel_service(ws: "Workspace", _):
    if not ws._config.channels:
        return None

    cm = ChannelManager.from_config(
        process=make_process_from_runner(runner),
        config=temp_config,
        on_last_dispatch=on_last_dispatch,
        workspace_dir=ws.workspace_dir,
    )

    # 注入 workspace 到 ChannelManager 和所有 channels
    cm.set_workspace(ws)

    # 注入 workspace 到 runner 用于控制命令处理
    runner.set_workspace(ws)
    return cm
```

### 4.2 ChannelManager 使用 Workspace 的场景

1. **task_tracker 访问**：通过 `workspace.task_tracker`
2. **配置重载**：在 `restart_channel` 中加载最新 agent 配置

---

## 5. MultiAgentManager — 多 Workspace 全局管理

源码路径：`src/qwenpaw/app/multi_agent_manager.py:34`

```python
class MultiAgentManager:
    def __init__(self):
        self.agents: Dict[str, Workspace] = {}   # 所有已加载的 workspace
        self._lock = asyncio.Lock()               # 线程锁
        self._pending_starts: Dict[str, asyncio.Event] = {}  # 等待中的启动

    async def get_agent(self, agent_id: str) -> Workspace:
        """获取 Workspace — 懒加载 + 双重检查锁定"""
        if agent_id in self.agents:
            return self.agents[agent_id]

        async with self._lock:
            if agent_id in self.agents:
                return self.agents[agent_id]
            if agent_id in self._pending_starts:
                event = self._pending_starts[agent_id]
                await event.wait()  # 等待其他请求的启动完成

        # 我们是启动者：在锁外创建（允许并行启动）
        instance = Workspace(agent_id, workspace_dir)
        await instance.start()

        async with self._lock:
            self.agents[agent_id] = instance
        return instance
```

---

## 6. 热重载 — 零停机重载

源码路径：`src/qwenpaw/app/multi_agent_manager.py:244`

### 6.1 核心流程

```python
async def reload_agent(self, agent_id: str) -> bool:
    """零停机重载 — 新旧实例平滑切换"""

    # Step 1: 获取旧实例（快速检查）
    old_instance = self.agents[agent_id]

    # Step 2: 创建新实例（关键：先创建再停止旧的）
    new_instance = Workspace(agent_id, workspace_dir)

    # Step 3: 复用可迁移组件
    reusable = old_instance._service_manager.get_reusable_services()
    await new_instance.set_reusable_components(reusable)

    # Step 4: 启动新实例
    await new_instance.start()

    # Step 5: 原子替换
    self.agents[agent_id] = new_instance

    # Step 6: 优雅停止旧实例
    await self._graceful_stop_old_instance(old_instance, agent_id)
```

### 6.2 延迟清理机制

```python
async def _graceful_stop_old_instance(self, old_instance, agent_id):
    has_active = await old_instance.task_tracker.has_active_tasks()

    if has_active:
        # 有活跃任务：后台延迟清理
        async def delayed_cleanup():
            await old_instance.task_tracker.wait_all_done(timeout=60.0)
            await old_instance.stop(final=False)

        cleanup_task = asyncio.create_task(delayed_cleanup())
    else:
        # 无活跃任务：立即停止
        await old_instance.stop(final=False)
```

### 6.3 可复用组件

```python
# src/qwenpaw/app/workspace/service_manager.py
class ServiceDescriptor:
    reusable: bool = True  # memory_manager, chat_manager 可复用

# 重载时不重建，直接转移
async def set_reusable_components(self, reusable: dict):
    for name, service in reusable.items():
        self._service_manager.services[name] = service
```

---

## 7. 生命周期管理

### 7.1 Workspace 启动 — start

```python
async def start(self):
    """启动 workspace 并初始化所有组件"""
    if self._started:
        return

    # 1. 加载代理配置
    self._config = load_agent_config(self.agent_id)

    # 2. 通过 ServiceManager 启动所有服务
    await self._service_manager.start_all()

    self._started = True
```

### 7.2 ServiceManager.start_all — 优先级分组并发启动

```python
async def start_all(self) -> None:
    # 按优先级分组
    priority_groups = self._group_by_priority()

    for priority in sorted(priority_groups.keys()):
        descriptors = priority_groups[priority]

        # 分离并发和顺序服务
        concurrent = [d for d in descriptors if d.concurrent_init]
        sequential = [d for d in descriptors if not d.concurrent_init]

        # 并发启动
        if concurrent:
            await asyncio.gather(*[self._start_service(desc) for desc in concurrent])

        # 顺序启动
        for desc in sequential:
            await self._start_service(desc)

        # 优先级组之间让出事件循环
        await asyncio.sleep(0)
```

---

## 8. 完整组件关系图

```
MultiAgentManager (全局单一实例)
  │
  ├── agents: Dict[agent_id, Workspace]
  │     │
  │     └── Workspace (每个 agent 一个)
  │           │
  │           ├── agent_id
  │           ├── workspace_dir (隔离的目录)
  │           ├── task_tracker (TaskTracker)
  │           │
  │           └── _service_manager (ServiceManager)
  │                 │
  │                 └── services: Dict[str, Any]
  │                       │
  │                       ├── "runner": AgentRunner
  │                       ├── "memory_manager": BaseMemoryManager
  │                       ├── "mcp_manager": MCPClientManager
  │                       ├── "chat_manager": ChatManager
  │                       ├── "channel_manager": ChannelManager
  │                       └── "cron_manager": CronManager
  │
  └── DynamicMultiAgentRunner (FastAPI Runner)
        │
        └── _multi_agent_manager = MultiAgentManager
```

---

## 9. ContextVar 异步隔离

除了文件系统和服务实例级别的隔离外，QwenPaw 还在 HTTP 请求层面使用 Python 的 `ContextVar` 实现协程级别的上下文隔离，确保多 Agent 并发请求时每个请求能正确路由到对应的 Workspace。

### 9.1 核心定义

源码路径：`src/qwenpaw/app/agent_context.py`

```python
# src/qwenpaw/app/agent_context.py
_current_agent_id: ContextVar[Optional[str]] = ContextVar("current_agent_id", default=None)
_current_session_id: ContextVar[Optional[str]] = ContextVar("current_session_id", default=None)
```

**ContextVar 的优势**：
- **协程安全**：每个协程有独立的值副本，无需加锁
- **自动传递**：在 `async with` 块中自动继承外层值
- **无锁开销**：比 `threading.local` 更轻量，适合 asyncio 单线程模型

### 9.2 AgentContextMiddleware — 请求级隔离

源码路径：`src/qwenpaw/app/routers/agent_scoped.py:14`

```python
class AgentContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        agent_id = None

        # 优先级 1: 路径提取 /api/agents/{agentId}/...
        path_parts = request.url.path.split("/")
        if len(path_parts) >= 4 and path_parts[2] == "agents":
            agent_id = path_parts[3]

        # 优先级 2: X-Agent-Id header
        if not agent_id:
            agent_id = request.headers.get("X-Agent-Id")

        # 优先级 3: 查询参数
        if not agent_id:
            agent_id = request.query_params.get("agent_id")

        # 设置上下文变量
        token = set_current_agent_id(agent_id)
        try:
            response = await call_next(request)
        finally:
            reset_current_agent_id(token)

        return response
```

**多层回退机制**确保在各种客户端场景下都能正确识别目标 Agent：
1. **URL 路径**（如 `/api/agents/agent-123/chats`）—— 最可靠，RESTful 风格
2. **HTTP Header**（`X-Agent-Id`）—— 适合代理/网关场景
3. **查询参数**（`?agent_id=agent-123`）—— 适合简单客户端

### 9.3 ContextVar vs threading.local

| 维度 | ContextVar | threading.local |
|------|------------|-----------------|
| 协程安全 | 每个 asyncio Task 有独立副本 | 基于线程 ID，同一线程的所有协程共享 |
| 开销 | 无锁，协程切换时自动保存/恢复 | 线程级隔离，异步场景不适用 |
| 传递方式 | 自动继承外层值 | 需要手动传递 |
| 适用场景 | asyncio 单线程事件循环 | 多线程环境 |

**为什么 QwenPaw 选择 ContextVar**：在 asyncio 协程场景下，`threading.local` 无法区分同一线程中的不同协程。多个 HTTP 请求可能在同一线程中交替执行，`threading.local` 会导致 Agent 上下文串扰。`ContextVar` 通过协程级别的隔离，确保每个请求始终路由到正确的 Workspace。

---

## 10. 服务工厂模式

Workspace 中的某些服务（如 ChannelManager）需要复杂的初始化逻辑，不适合直接通过 `ServiceDescriptor.service_class` 实例化。QwenPaw 使用工厂函数模式处理这类场景。

源码路径：`src/qwenpaw/app/workspace/service_factories.py`

```python
# src/qwenpaw/app/workspace/service_factories.py:67
async def create_channel_service(ws: "Workspace", _) -> Optional[ChannelManager]:
    """根据配置创建渠道管理器"""
    if not ws._config.channels:
        return None  # 无渠道配置时不创建实例

    cm = ChannelManager.from_config(
        process=make_process_from_runner(runner),
        config=temp_config,
        on_last_dispatch=on_last_dispatch,
        workspace_dir=ws.workspace_dir,
    )

    # 注入 workspace 到 ChannelManager 和所有 channels
    cm.set_workspace(ws)

    # 注入 workspace 到 runner 用于控制命令处理
    runner.set_workspace(ws)
    return cm
```

**工厂模式的优势**：
- **延迟实例化**：配置不存在时不创建无用实例，节省资源
- **配置驱动**：通过 JSON/YAML 配置即可定制服务行为，无需修改代码
- **依赖注入**：Workspace 通过参数传递依赖的服务实例（如将 Runner 注入 ChannelManager）

---

## 11. 设计模式总结

### 11.1 隔离层次

| 层次 | 机制 | 说明 |
|------|------|------|
| **目录隔离** | 每个 agent 独立 `workspace_dir` | 文件系统级别 |
| **进程隔离** | 每个 Workspace 独立的服务实例 | 内存级别 |
| **线程安全** | `asyncio.Lock` | 并发访问保护 |
| **服务隔离** | `ServiceManager` + `ServiceDescriptor` | 声明式生命周期 |
| **请求隔离** | `ContextVar` + `AgentContextMiddleware` | 协程级上下文隔离 |

### 11.2 关键设计模式

1. **声明式服务配置** — 使用 `ServiceDescriptor` 替代硬编码初始化
2. **优先级驱动启动** — 确保依赖顺序正确
3. **可复用组件** — 支持热重载而不丢失状态
4. **零停机重载** — 新旧实例平滑切换
5. **延迟清理** — 后台任务完成后再清理旧实例
6. **懒加载 + 双重检查** — 并行启动加速，只初始化需要的 Agent
7. **锁外并行初始化** — 快速释放锁，多个 Agent 同时初始化，锁只保护字典写操作

**锁外并行初始化的性能收益**：

```python
# 快速释放锁，允许其他 Agent 并行启动
instance = Workspace(...)      # 锁外：创建实例
await instance.start()        # 锁外：初始化（可能耗时）
async with self._lock:        # 锁内：快速交换
    self.agents[agent_id] = instance
```

多个 Agent 同时启动时，初始化并行化，锁只保护字典写操作，持有时间极短。

---

## 12. 应用场景

### 场景1: 多租户隔离

为不同客户/团队创建独立的 Agent：

```python
# 客户 A
workspace_a = await multi_agent_manager.get_agent("customer-a")

# 客户 B
workspace_b = await multi_agent_manager.get_agent("customer-b")

# 两者完全隔离，有独立的配置、记忆、渠道
```

**隔离保证**：
- **文件系统隔离**：租户 A 无法读写租户 B 的工作区文件
- **内存隔离**：ContextVar 确保请求路由到正确的租户上下文
- **配置隔离**：每个租户有独立的 agent.json

### 场景2: 开发/生产环境隔离

```python
# 开发环境
dev_workspace = await multi_agent_manager.get_agent("dev")

# 生产环境
prod_workspace = await multi_agent_manager.get_agent("prod")
```

### 场景3: 热重载配置

管理员修改 `agent.json` 后无需重启：

```python
# 触发热重载
await multi_agent_manager.reload_agent("default")
```

---

## 13. 常见问题

### Q1: Workspace 隔离的开销有多大？

**A**: 每个 Workspace 都会创建独立的服务实例：
- **内存开销**：每个 Agent 约增加 50-100MB（取决于配置）
- **服务开销**：ChannelManager、CronManager 等持续运行

对于资源受限场景，可以考虑池化重型服务。

### Q2: 为什么需要双向引用（Workspace → Runner，Runner → Workspace）？

**A**: 各有用途：
- **Workspace → Runner**：Workspace 管理 Runner 的生命周期
- **Runner → Workspace**：Runner 需要访问 Workspace 的组件（如 TaskTracker）

这解耦了管理职责和依赖使用。

### Q3: 热重载时哪些组件会被复用？

**A**: 标记为 `reusable=True` 的服务：
- `memory_manager`
- `chat_manager`

这些服务保存了用户数据，重建会丢失对话历史。

### Q4: 如何调试 Workspace 问题？

**A**: 方法：
1. 检查 Workspace 日志
2. 查看 `workspace_dir/sessions/` 中的会话状态
3. 使用 `MultiAgentManager.get_agent()` 获取 Workspace 实例检查状态
4. 查看服务启动顺序日志

### Q5: 可以动态创建新的 Workspace 吗？

**A**: 可以。通过 API 或代码：

```python
# 动态创建 agent
await multi_agent_manager.create_agent("new-agent-id")
```

但需要确保 `agents/` 目录下有对应的配置文件。

### Q6: 如何解决 ContextVar 值丢失问题？

**原因**：中间件未正确设置上下文，或异步调用链断裂。

**解决**：
```python
# 确保所有入口都通过 AgentContextMiddleware
app.add_middleware(AgentContextMiddleware)

# 手动传递 context（如果需要跨线程）
token = set_current_agent_id(agent_id)
# ... 在同一协程内使用
reset_current_agent_id(token)
```

### Q7: 多个 Agent 并发启动时性能下降？

**原因**：锁竞争严重，或服务初始化串行化。

**优化**：
```python
# 确保同类服务使用 concurrent_init=True
sm.register(ServiceDescriptor(
    name="mcp_manager",
    concurrent_init=True,  # 允许多个 MCP Manager 并发初始化
    ...
))
```

### Q8: 重载后内存占用增加如何处理？

**原因**：旧 Workspace 实例未完全释放。

**解决**：
```python
# 确保 stop() 被调用且无引用
import gc
gc.collect()  # 强制垃圾回收
```

---

## 14. 最佳实践

### 实践1: 合理设计 Agent ID

```python
# 使用有意义的 ID
await multi_agent_manager.get_agent("customer-123")
await multi_agent_manager.get_agent("prod-backend")
```

### 实践2: 及时清理不需要的 Workspace

```python
# 停止并移除 Workspace
await multi_agent_manager.stop_agent("unused-agent")
```

### 实践3: 使用 reusable 服务保存重要状态

```python
# memory_manager 和 chat_manager 是 reusable
# 可以在热重载时保留用户数据
```

### 实践4: 配置变更使用热重载而非重启

```python
# 修改 agent.json 后
await multi_agent_manager.reload_agent("agent-id")
# 而非停止再启动
```

### 实践5: 服务注册规范

```python
# 推荐：明确的优先级声明
sm.register(ServiceDescriptor(
    name="my_service",
    service_class=MyService,
    init_args=lambda ws: {"config": ws._config.my_service},
    start_method="start",
    stop_method="stop",
    priority=35,           # 明确数字，避免魔法值
    concurrent_init=False, # 有依赖时设为 False
))

# 避免：模糊的优先级
priority=100  # 不推荐，未表明意图
```

### 实践6: 避免循环依赖

```python
# 错误：循环依赖
# Service A (priority=10) imports Service B
# Service B (priority=20) imports Service A

# 正确：单向依赖
# A 启动后，B 在更高优先级时启动
```

### 实践7: 确保 ContextVar 正确设置

```python
# 确保所有入口都通过 AgentContextMiddleware
app.add_middleware(AgentContextMiddleware)

# 手动传递 context（如果需要跨线程）
token = set_current_agent_id(agent_id)
# ... 在同一协程内使用
reset_current_agent_id(token)
```

---

## 如果你来自 Java...

Java 生态中有多种多租户/隔离架构的实现方式：

### Spring Cloud — 多实例隔离模式

```java
// Java 的 Spring Cloud Contract 类似 Workspace 的隔离概念
@Configuration
public class AgentContextConfig {
    @Bean
    @Scope(value = "agent", proxyMode = ScopedProxyMode.TARGET_CLASS)
    public AgentContext agentContext() {
        return new AgentContext();
    }
}

// 抽象工厂模式创建隔离的 Agent
public interface AgentFactory {
    Agent createAgent(String agentId);
}

@Service
public class DefaultAgentFactory implements AgentFactory {
    @Override
    public Agent createAgent(String agentId) {
        // 每个 Agent 独立的组件
        return new Agent(
            new AgentConfig(agentId),
            new MemoryManager(),
            new ChatManager(),
            new ChannelManager()
        );
    }
}
```

### Java 9 Module System — 模块隔离

```java
// Java 9 Module System 实现模块级隔离
// module-info.java
module com.qwenpaw.agent {
    requires com.qwenpaw.core;
    exports com.qwenpaw.agent.api;
}

// 类加载器隔离
public class AgentClassLoader extends URLClassLoader {
    // 每个 Workspace 使用独立的 ClassLoader
}
```

### 关键概念对应

| QwenPaw 概念 | Java 对应 | 说明 |
|--------------|-----------|------|
| `Workspace` | `Agent` / `TenantContext` | 隔离执行单元 |
| `ServiceManager` | `BeanFactory` / `ApplicationContext` | 服务生命周期 |
| `MultiAgentManager` | `AgentFactory` / `TenantRegistry` | 全局管理 |
| `reusable=True` | `@RefreshScope` | 热重载保持状态 |
| `ServiceDescriptor` | `@Bean` 定义 | 声明式服务 |
| `workspace_dir` | `ClassLoader` + `FileSystem` | 资源隔离 |

### Java 实现特点

1. **依赖注入**：Spring 的 IoC 容器自动管理组件依赖
2. **作用域代理**：`@Scope("agent")` 动态代理实现租户隔离
3. **配置刷新**：`@RefreshScope` 支持配置变更后重建 Bean
4. **类加载器隔离**：每个租户使用独立的 `ClassLoader`

---

## 知识检查

1. **Workspace 的多层隔离（目录、服务、线程安全、请求级 ContextVar）分别解决什么问题？**
2. **ServiceManager 的优先级分组启动中，为什么 Runner (priority=10) 必须先于 ChannelManager (priority=30) 启动？**
3. **热重载时为什么采用「先建后停」策略，而不是先停止旧实例再创建新实例？**
4. **ContextVar vs threading.local**：QwenPaw 使用 ContextVar 而非 threading.local 实现请求上下文隔离。请解释在 asyncio 协程场景下，threading.local 存在什么问题，而 ContextVar 如何解决。

## 练习题

### 基础练习

1. **Workspace 启动顺序分析**
   `ServiceManager.start_all()` 按优先级分组并发启动服务。请分析：Runner (priority=10) 和 Channel manager (priority=30) 之间为什么要留有空隙？`asyncio.sleep(0)` 的作用是什么？

2. **可复用组件设计**
   `memory_manager` 和 `chat_manager` 被标记为 `reusable=True`，而 `runner` 不是。请分析：为什么对话历史需要保留而 Runner 不需要？如果把 Runner 也标记为 reusable，会有什么问题？

3. **热重载的双实例切换**
   `reload_agent` 方法先创建新实例，再原子替换，最后才停止旧实例。请分析：为什么要用「先建后停」的策略，而不是「先停后建」？如果旧实例停止失败，会出现什么问题？

4. **懒加载 + 双重检查锁**
   `MultiAgentManager.get_agent()` 使用懒加载和双重检查锁。请画出时序图，说明为什么需要双重检查？如果去掉外层锁，只保留内层锁，能正常工作吗？

### 进阶练习

1. **实现 Workspace 资源限制**
   当前 Workspace 没有资源限制。请设计一个机制，限制每个 Workspace 的：
   - 最大内存使用量
   - 最大并发任务数
   - 磁盘存储配额

   **提示**：使用 Python 的 `resource` 模块或 `psutil` 库。

2. **跨 Workspace 消息通信**
   如果 Agent A 需要向 Agent B 发送消息，当前需要通过外部消息队列。请设计一个 Workspace 间的直接通信机制：
   - Workspace 如何发现其他 Workspace？
   - 如何避免循环依赖？
   - 如何处理 Workspace 不存在的情况？

3. **Workspace 模板功能**
   设计一个「Workspace 模板」功能，支持从预定义模板快速创建新 Agent：
   - 模板包含默认配置、服务组合、技能池
   - 新 Agent 可以基于模板创建并覆盖特定配置

### 实战练习

**综合项目：Workspace 监控面板**

创建一个 Web 监控界面，展示所有 Workspace 的运行状态：

- **后端 API**：
  - `GET /api/workspaces` - 列出所有 Workspace
  - `GET /api/workspaces/{id}/stats` - 获取资源使用统计
  - `POST /api/workspaces/{id}/reload` - 触发热重载
  - `POST /api/workspaces/{id}/stop` - 停止 Workspace

- **前端界面**：
  - Workspace 列表卡片（显示状态、健康检查、内存使用）
  - 热重载按钮
  - 日志查看器
  - 实时更新（轮询或 WebSocket）

**提示**：
- 参考 `MultiAgentManager` 的 API 设计
- 使用 `ServiceDescriptor` 获取服务优先级信息
- 考虑添加资源监控（CPU、内存、任务数）

---

## 15. 相关章节

- [请求处理与Runner](./21-请求处理与Runner.md) — Runner 在 Workspace 中的角色
- [消息渠道系统](./08-消息渠道系统.md) — ChannelManager 与 Workspace 交互
- [定时任务与心跳](./25-定时任务与心跳.md) — CronManager 与 Workspace 交互
- [MCP系统详解](./29-MCP系统详解.md) — MCPClientManager 与 Workspace 交互

---

## 延伸阅读

- [生命周期管理](./94-生命周期管理.md) — 全局生命周期与 Workspace 的关系
- [多智能体协作](./14-多智能体协作.md) — 多 Agent 协作场景下的隔离与通信
- [请求处理与Runner](./21-请求处理与Runner.md) — Runner 与 Workspace 的双向引用机制

---

*本文档基于 QwenPaw v0.x 源码编写，源码位置：`src/qwenpaw/app/workspace/`*
