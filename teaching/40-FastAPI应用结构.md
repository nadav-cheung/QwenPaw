# FastAPI 应用结构

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 理解两阶段启动架构的设计意图与实现方式 2) 掌握中间件注册顺序与执行顺序的关系 3) 分析多 Agent 动态路由与作用域路由工厂模式 |
| **前置知识** | [06-Python基础教程](./06-Python基础教程.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 40 分钟（阅读 25 分钟 + 练习 15 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `两阶段启动` `中间件` `路由系统` `动态路由` |

> **一句话概述**：本章讲解 FastAPI 应用的两阶段启动架构、中间件链、路由系统和多 Agent 动态路由机制。

## 概述

QwenPaw 的 Web 应用基于 FastAPI 构建，采用**两阶段启动**架构（<100ms 快速响应 + 后台重型初始化），中间件按顺序执行，提供完整的 REST API 路由系统。

---

### 🐍 来自 Java 的你

| Java | Python FastAPI | 说明 |
|------|----------------|------|
| `@SpringBootApplication` | `FastAPI()` | 应用入口类 |
| `@RestController` | `@app.get/post/put/delete()` | REST 控制器 |
| `@RequestMapping("/api")` | `APIRouter(prefix="/api")` | 路由分组 |
| `@PathVariable` | `/{item_id}` 路径参数 | URL 路径变量 |
| `@RequestParam` | `?name=value` 查询参数 | URL 查询参数 |
| `@RequestBody` | `Body(...)` | 请求体绑定 |
| `@ResponseBody` | 默认返回值 JSON | 响应自动序列化 |
| `WebMvcConfigurer` | `app.add_middleware()` | 中间件配置 |
| `@Component` / `@Bean` | 直接实例化或依赖注入 | Bean 注册 |
| `ApplicationContext` | `app.state` | 应用状态存储 |
| `Filter` | `BaseHTTPMiddleware` | 过滤器/中间件 |

**Spring MVC 对比示例**：

```java
// Java Spring MVC
@RestController
@RequestMapping("/api/users")
public class UserController {
    @GetMapping("/{id}")
    public User getUser(@PathVariable Long id) {
        return userService.findById(id);
    }
}
```

```python
# Python FastAPI
@router.get("/{user_id}")
async def get_user(user_id: int):
    return await user_service.find_by_id(user_id)
```

---

## 1. 应用入口 — _app.py

源码路径：`src/qwenpaw/app/_app.py`

### 1.1 两阶段启动架构

```
Phase 1: 同步快速设置 (< 100ms)
  ├─ 认证初始化
  ├─ 遥测收集
  ├─ 遗留配置迁移
  └─ 核心管理器实例化（无 I/O）
         ↓
  app.state 暴露管理器
         ↓
Phase 2: 后台重型初始化
  ├─ 启动所有配置的 agents
  ├─ 恢复本地模型
  ├─ 初始化插件系统
  │    ├─ PluginLoader.load_all_plugins()
  │    ├─ 注册插件 providers
  │    ├─ 注册控制命令 (/plugin-cmd)
  │    └─ 执行启动钩子
  ├─ 设置审批服务
  └─ 打印启动横幅
```

### 1.2 Lifespan 上下文管理器

```python
# src/qwenpaw/app/_app.py:218
async with lifespan(app):
    # Phase 1: 快速同步设置
    auto_register_from_env()
    migrate_legacy_workspace_to_default_agent()
    ensure_default_agent_exists()
    multi_agent_manager = MultiAgentManager()
    app.state.multi_agent_manager = multi_agent_manager

    # Phase 2: 后台重型初始化
    _bg_task = asyncio.create_task(_background_startup(...))

    yield  # 服务器运行中

    # Shutdown
    if not _bg_task.done():
        _bg_task.cancel()
```

### 1.3 DynamicMultiAgentRunner

源码路径：`src/qwenpaw/app/_app.py:60`

```python
class DynamicMultiAgentRunner:
    """Runner wrapper that dynamically routes to the correct workspace runner.

    This allows AgentApp to work with multiple agents by inspecting
    the X-Agent-Id header on each request.
    """

    def __init__(self):
        self.framework_type = "agentscope"
        self._multi_agent_manager = None

    def set_multi_agent_manager(self, manager):
        """Set the MultiAgentManager instance after initialization."""
        self._multi_agent_manager = manager
```

**动态路由机制**：

```python
async def _get_workspace(self, request):
    """Get the correct workspace based on request."""
    from ..agent_context import get_current_agent_id

    # Get agent_id from context (set by middleware or header)
    agent_id = get_current_agent_id()
    logger.debug(f"_get_workspace: agent_id={agent_id}")

    # Get the correct workspace
    workspace = await self._multi_agent_manager.get_agent(agent_id)
    return workspace

async def stream_query(self, request, *args, **kwargs):
    """Dynamically route to the correct workspace runner."""
    workspace = await self._get_workspace(request)
    runner = workspace.runner

    # Register task with workspace's TaskTracker for graceful shutdown
    run_key = f"ext-{uuid.uuid4().hex}"
    await workspace.task_tracker.register_external_task(run_key)

    try:
        # Delegate to the actual runner's stream_query generator
        async for item in runner.stream_query(request, *args, **kwargs):
            yield item
    finally:
        # Always unregister the task when done
        await workspace.task_tracker.unregister_external_task(run_key)
```

**TaskTracker 注册机制**：
- 外部请求注册到 workspace 的 TaskTracker
- Agent 重载时 `_graceful_stop_old_instance()` 可检测进行中的任务
- 解决 Issue #3275：Agent 重载期间的优雅关闭问题

---

## 2. 中间件配置

### 2.1 中间件顺序

FastAPI 中间件按**注册顺序反向执行**（最后注册的最先处理请求）：

```python
# src/qwenpaw/app/_app.py:518
# 1. AgentContextMiddleware（最先注册，最后执行）
app.add_middleware(AgentContextMiddleware)

# 2. AuthMiddleware
app.add_middleware(AuthMiddleware)

# 3. CORSMiddleware（最后注册，最先处理）
if CORS_ORIGINS:
    app.add_middleware(CORSMiddleware, ...)
```

### 2.2 请求流程

```
请求 ──► CORSMiddleware ──► AuthMiddleware ──► AgentContextMiddleware ──► 路由
                                                                                    │
响应 ◄────────────────────────────────────────────────────────────────────┘
      (CORSMiddleware 最后注册，最先处理响应)
```

### 2.3 AgentContextMiddleware

```python
# src/qwenpaw/app/routers/agent_scoped.py:9
class AgentContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # 优先级 1: 从路径提取 /api/agents/{agentId}/...
        path_parts = request.url.path.split("/")
        if len(path_parts) >= 4 and path_parts[2] == "agents":
            agent_id = path_parts[3]
            request.state.agent_id = agent_id

        # 优先级 2: X-Agent-Id header
        if not agent_id:
            agent_id = request.headers.get("X-Agent-Id")

        set_current_agent_id(agent_id)
        return await call_next(request)
```

### 2.4 AuthMiddleware

```python
# src/qwenpaw/app/auth.py:567
class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if self._should_skip_auth(request):
            return await call_next(request)

        token = self._extract_token(request)
        if not token:
            return Response(status_code=401)

        user = verify_token(token)
        if user is None:
            return Response(status_code=401)

        request.state.user = user
        return await call_next(request)
```

**跳过认证的路径**：
```python
# src/qwenpaw/app/auth.py:51
_PUBLIC_PATHS = frozenset({
    "/api/auth/login",
    "/api/auth/status",
    "/api/auth/register",
    "/api/version",
    "/api/settings/language",
    "/api/plugins",
})
```

---

## 3. 路由系统

### 3.1 路由目录结构

```
src/qwenpaw/app/routers/
├── __init__.py          # 主路由聚合
├── agent.py             # /agent 端点
├── agent_scoped.py      # AgentContextMiddleware + 作用域路由工厂
├── agents.py            # /agents 端点
├── auth.py              # /auth 端点
├── backup.py            # /backup 端点
├── config.py            # /config 端点
├── console.py           # /console 端点
├── cron.py              # /cron 端点
├── envs.py              # /envs 端点
├── files.py            # /files 端点
├── local_models.py      # /local_models 端点
├── mcp.py              # /mcp 端点
├── messages.py          # /messages 端点
├── plugins.py           # /plugins 端点
├── providers.py         # /providers 端点
├── skills.py            # /skills 端点
├── tools.py            # /tools 端点
├── voice.py            # /voice 端点
└── workspace.py        # /workspace 端点
```

### 3.2 路由聚合

```python
# src/qwenpaw/app/routers/__init__.py
router = APIRouter()
router.include_router(agents_router)        # /agents
router.include_router(agent_router)         # /agent
router.include_router(config_router)         # /config
router.include_router(console_router)       # /console
router.include_router(cron_router)           # /cron
# ... 更多路由
```

### 3.3 主 API 前缀

```python
# src/qwenpaw/app/_app.py:610
app.include_router(api_router, prefix="/api")
```

### 3.4 Agent 作用域路由

```python
# src/qwenpaw/app/routers/agent_scoped.py:49
def create_agent_scoped_router() -> APIRouter:
    router = APIRouter(prefix="/agents/{agentId}", tags=["agent-scoped"])
    router.include_router(agent_router)      # /agents/{agentId}/agent/*
    router.include_router(chats_router)      # /agents/{agentId}/chats/*
    router.include_router(config_router)     # /agents/{agentId}/config/*
    # ...
    return router
```

---

## 4. 服务初始化顺序

源码路径：`src/qwenpaw/app/workspace/service_manager.py:173`

在两阶段启动的第二阶段，每个 Agent 的工作区按**优先级分组**启动内部服务。同优先级的服务并发启动，不同优先级串行执行。

### 4.1 服务优先级表

| 优先级 | 服务 | 并发 | 说明 |
|--------|------|------|------|
| 10 | Runner | 否 | AgentRunner，必须首先就绪 |
| 20 | memory_manager | 是 | 记忆管理器（可复用） |
| 20 | mcp_manager | 是 | MCP 管理器 |
| 20 | chat_manager | 是 | 聊天管理器 |
| 25 | runner_start | 否 | Runner 启动（依赖 Runner 就绪） |
| 30 | channel_manager | 否 | 渠道管理器 |
| 40 | cron_manager | 否 | 定时任务管理器 |
| 50 | agent_config_watcher | 否 | Agent 配置监听（热重载） |

### 4.2 并发初始化执行图解

```
Priority 10: Runner [串行]
    ↓
Priority 20: memory_manager || mcp_manager || chat_manager [三者并发]
    ↓
Priority 25: runner_start [串行]
    ↓
Priority 30: channel_manager [串行]
    ↓
Priority 40: cron_manager [串行]
    ↓
Priority 50: agent_config_watcher [串行]
```

**设计要点**：Priority 20 的三个服务互相独立，可以安全地并发启动以减少总启动时间。Runner 必须最先就绪（P10），因为后续的 `runner_start`（P25）和渠道管理器（P30）都依赖它。

### 4.3 Agent 并行启动

源码路径：`src/qwenpaw/app/multi_agent_manager.py:454`

```python
async def start_all_configured_agents():
    # 并行启动所有已启用 Agent
    await asyncio.gather(*[start_one_agent(id) for id in enabled_ids])
```

每个 Agent 的工作区独立初始化，多个 Agent 之间也通过 `asyncio.gather` 并行启动。

### 4.4 完整启动序列图

```
python -m qwenpaw app
         ↓
uvicorn.run("qwenpaw.app._app:app")
         ↓
FastAPI(lifespan=lifespan)
         ↓
=== Phase 1 (同步, <100ms) ===
创建 MultiAgentManager / ProviderManager / LocalModelManager
         ↓
服务器开始接收 HTTP 请求 ← 此时 Agent 尚未启动
         ↓
=== Phase 2 (后台) ===
start_all_configured_agents()
         ↓
对每个 Agent:
    Workspace.start() → ServiceManager.start_all()
         ↓
服务按优先级启动:
    Runner (P10) →
    Memory/MCP/Chat (P20, 并发) →
    RunnerStart (P25) →
    ChannelManager (P30) →
    CronManager (P40) →
    ConfigWatcher (P50)
         ↓
print_ready_banner()
```

**注意**：`workers=1` 是硬编码的，不支持多进程。原因：QwenPaw 的多 Agent 共享状态在单进程内通过内存管理，多进程会破坏这一设计。如需多实例，应使用容器层面负载均衡而非进程内多 worker。

---

## 5. 特殊路由

### 4.1 根路由

```python
# src/qwenpaw/app/_app.py:578
@app.get("/")
def read_root():
    if _CONSOLE_INDEX and _CONSOLE_INDEX.exists():
        return FileResponse(_CONSOLE_INDEX)
    return {"message": "QwenPaw API"}
```

### 4.2 API 版本

```python
# src/qwenpaw/app/_app.py:593
@app.get("/api/version")
def get_version():
    return {"version": __version__}
```

### 4.3 Voice 路由（根级）

```python
# src/qwenpaw/app/_app.py:625
app.include_router(voice_router, tags=["voice"])
```

注意：Voice 端点在根级而非 `/api/` 下：
- `POST /voice/incoming`
- `WS /voice/ws`
- `POST /voice/status-callback`

---

## 6. 应用场景

### 6.1 多 Agent 路由

**场景**：通过 URL 路径区分不同 Agent。

**实现**：
- `/api/agents/agent1/chats`
- `/api/agents/agent2/chats`

`AgentContextMiddleware` 从路径提取 `agentId` 并设置到 `request.state`。

### 6.2 认证与授权

**场景**：保护 API 端点，需要 JWT Token 认证。

**流程**：
1. `AuthMiddleware` 从请求提取 Token
2. 验证 Token 有效性
3. 将用户信息设置到 `request.state.user`
4. 路由处理器可通过 `request.state.user` 访问用户信息

### 6.3 静态文件服务

**场景**：提供 Web UI 静态文件。

**实现**：
```python
# 根路径返回静态文件
@app.get("/")
def read_root():
    if _CONSOLE_INDEX and _CONSOLE_INDEX.exists():
        return FileResponse(_CONSOLE_INDEX)
```

### 6.4 WebSocket 实时通信

**场景**：Voice 渠道需要 WebSocket 双向通信。

**端点**：`WS /voice/ws`

### 6.5 滚动更新

```
新请求 → FastAPI 处理（Phase 1 已就绪）
               ↓
        Agent 仍在启动中
               ↓
        请求进入队列或返回 503（取决于配置）
```

### 6.6 插件热加载

```python
# 插件的 on_startup 钩子在 Phase 2 执行
class MyPlugin:
    async def on_startup(self, app):
        # 注册自定义路由
        app.include_router(my_router)
        # 初始化资源
        await self.init_resources()
```

### 6.7 健康检查前置

```bash
# 在 Agent 完全启动前，健康检查已可用
curl http://localhost:8000/api/version
# 返回 {"version": "1.0.0"}

# 但 Agent 相关 API 可能返回 503
curl http://localhost:8000/api/agents
# 返回 {"error": "agents not ready"}
```

---

## 7. 健康检查端点

| 端点 | 说明 |
|------|------|
| `GET /api/config/channels/{name}/health` | 频道健康状态 |
| `GET /api/auth/status` | 认证状态 |
| `GET /api/version` | 应用版本 |
| `GET /api/doctor/runtime` | 运行时诊断 |

**健康检查响应示例**：

```json
{
  "status": "healthy",
  "timestamp": "2026-04-30T10:00:00Z",
  "channels": {
    "console": "healthy",
    "telegram": "healthy"
  }
}
```

---

## 8. 最佳实践

### 8.1 两阶段启动

```python
# Phase 1: 快速（< 100ms）
managers = create_managers_without_io()

# Phase 2: 后台（重型 I/O）
bg_task = asyncio.create_task(heavy_initialization())
```

**优势**：服务器快速响应，用户无需等待所有初始化完成。

### 8.2 中间件顺序

```python
# 后注册先执行
app.add_middleware(Third)  # 请求时最先
app.add_middleware(Second)
app.add_middleware(First)   # 请求时最后
```

### 8.3 作用域路由工厂

```python
def create_agent_scoped_router() -> APIRouter:
    router = APIRouter(prefix="/agents/{agentId}")
    router.include_router(agent_router)
    return router
```

### 8.4 跳过认证路径配置

```python
# 将公开端点添加到 _PUBLIC_PATHS
_PUBLIC_PATHS = frozenset({
    "/api/auth/login",
    "/api/version",
    ...
})
```

---

## 9. 常见问题

### Q1: 中间件顺序不正确导致问题？

**原因**：FastAPI 中间件按注册顺序**反向**执行。

**解决**：确认注册顺序与预期执行顺序匹配：
```python
# 想要：CORSMiddleware → AuthMiddleware → AgentContextMiddleware
# 注册顺序应该是：
app.add_middleware(AgentContextMiddleware)  # 最后注册，最先执行
app.add_middleware(AuthMiddleware)
app.add_middleware(CORSMiddleware)         # 最先注册，最后执行
```

### Q2: 认证失败但不知道原因？

**排查**：
1. 检查 Token 是否正确传递（Authorization header）
2. 确认 Token 未过期
3. 查看 `AuthMiddleware` 日志

### Q3: 路径参数冲突？

**场景**：同时有 `/agents` 和 `/agents/{agentId}`。

**解决**：FastAPI 按定义顺序匹配，先定义的优先。

### Q4: 静态文件未加载？

**排查**：
1. 确认 `_CONSOLE_INDEX` 路径正确
2. 检查文件是否存在
3. 确认文件权限

### Q5: AgentContextMiddleware 未生效？

**排查**：
1. 确认请求路径包含 `/agents/{agentId}/`
2. 或请求包含 `X-Agent-Id` header
3. 检查 `set_current_agent_id()` 是否正确设置

---

## 10. 设计模式

### 10.1 两阶段启动

```python
# Phase 1: 快速（< 100ms）
managers = create_managers_without_io()

# Phase 2: 后台（重型 I/O）
bg_task = asyncio.create_task(heavy_initialization())
```

### 10.2 中间件顺序

```python
# 后注册先执行
app.add_middleware(Third)  # 请求时最先
app.add_middleware(Second)
app.add_middleware(First)   # 请求时最后
```

### 10.3 作用域路由工厂

```python
def create_agent_scoped_router() -> APIRouter:
    router = APIRouter(prefix="/agents/{agentId}")
    router.include_router(agent_router)
    return router
```

---

## 练习题

### 基础练习

1. **中间件顺序推理**
   假设中间件按以下顺序注册：
   ```python
   app.add_middleware(CORSMiddleware)
   app.add_middleware(AuthMiddleware)
   app.add_middleware(AgentContextMiddleware)
   ```
   请求 `GET /api/agents/agent1/chats` 时，CORSMiddleware、AuthMiddleware、AgentContextMiddleware 三个中间件的处理顺序是什么？（请求时和响应时的顺序分别回答）

2. **AgentContextMiddleware 的 agentId 提取**
   `AgentContextMiddleware` 支持两种方式设置 `agent_id`：从 URL 路径提取和从 `X-Agent-Id` Header 读取。请列出当请求为 `GET /api/agents/my-agent/chats` 且 Header 包含 `X-Agent-Id: header-agent` 时，`set_current_agent_id()` 最终收到的是哪个 agentId，为什么？

3. **两阶段启动的阶段划分**
   在 QwenPaw 的 `lifespan` 上下文管理器中，哪些初始化操作属于 Phase 1（同步快速设置），哪些属于 Phase 2（后台重型初始化）？请列举 Phase 1 和 Phase 2 各包含的具体步骤。

### 进阶练习

1. **新增公开端点**
   假设你要在 QwenPaw 中新增一个 `/api/health` 端点，用于无认证的健康检查。请描述需要修改哪些文件，以及如何在 `_PUBLIC_PATHS` 中注册该路径，使 `AuthMiddleware` 跳过认证检查。

2. **作用域路由工厂分析**
   `create_agent_scoped_router()` 创建的路由前缀是 `/agents/{agentId}`。请分析：当请求 `GET /agents/agent1/config` 到达时，哪个路由处理器会处理它？路由参数 `{agentId}` 的值是什么？

### 实战练习

- **多 Agent 动态路由实现**
  在 QwenPaw 中，`DynamicMultiAgentRunner` 通过检查请求 Header 中的 `X-Agent-Id` 来动态路由到不同 workspace 的 Runner。请参考源码 `src/qwenpaw/app/_app.py:60` 中的 `_get_workspace` 方法，描述其完整的工作流程：如何从请求中获取 agentId，如何根据 agentId 找到对应的 workspace，以及 `TaskTracker` 在这个过程中扮演什么角色。

---

## 11. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| _app.py | `src/qwenpaw/app/_app.py` |
| AgentContextMiddleware | `src/qwenpaw/app/routers/agent_scoped.py:9` |
| AuthMiddleware | `src/qwenpaw/app/auth.py:567` |
| 路由聚合 | `src/qwenpaw/app/routers/__init__.py` |
| Agent 作用域路由 | `src/qwenpaw/app/routers/agent_scoped.py:49` |
| 多 Agent 管理 | `src/qwenpaw/app/multi_agent_manager.py` |
| 服务管理 | `src/qwenpaw/app/workspace/service_manager.py` |

---

## 附录：FastAPI 2025 最新特性

### Lifespan 事件（替代废弃的 startup/shutdown）

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动逻辑 - 应用开始接收请求前执行
    ml_models = {}
    ml_models["model_a"] = load_model("model_a.pkl")
    yield
    # 关闭逻辑 - 应用处理完请求后执行
    ml_models.clear()

app = FastAPI(lifespan=lifespan)
```

> **注意**：FastAPI 0.93+ 推荐使用 `lifespan` 替代独立的 `startup`/`shutdown` 事件。

### OAuth2 依赖注入（类似 Spring Security）

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    user = get_user_from_token(token)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="无效的认证凭证",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
```

### 中间件与 Filter 对比（Java EE vs FastAPI）

| Java EE | FastAPI | 说明 |
|---------|---------|------|
| `Filter.doFilter()` | `middleware.dispatch()` | 过滤方法 |
| `FilterChain` | `call_next` | 链式调用 |
| `@WebFilter` | `app.add_middleware()` | 注册方式 |
| `HttpServletRequest` | `Request` | 请求对象 |
| `HttpServletResponse` | `Response` | 响应对象 |
| `request.setAttribute()` | `request.state.xxx` | 状态传递 |

---

## 实战演练

### 基础练习（⭐）
**目标**: 找到 FastAPI 应用的两阶段启动流程，说明每阶段的作用
**提示**: 查看 `src/qwenpaw/app/_app.py` 中的 `lifespan` 上下文管理器
**参考思路**: Phase 1（同步，<100ms）负责认证初始化、配置迁移、创建 MultiAgentManager 等核心管理器实例；Phase 2（后台异步）负责启动所有 Agent 的 Workspace、初始化插件系统、设置审批服务等重型 I/O 操作

### 进阶练习（⭐⭐⭐）
**目标**: 追踪一个 HTTP 请求通过中间件链的完整路径
**提示**: 以 `GET /api/agents/agent1/chats` 为例，按实际执行顺序分析 CORSMiddleware → AuthMiddleware → AgentContextMiddleware 的处理
**参考思路**: 请求先经过 CORSMiddleware（最后注册最先处理）处理跨域头 → AuthMiddleware 提取 JWT Token 并验证用户身份 → AgentContextMiddleware 从 URL 路径提取 agentId 并设置到 context → 最终到达路由处理器

### 挑战练习（⭐⭐⭐⭐⭐）
**目标**: 实现一个新的 API 路由模块，包含 CRUD 操作和认证中间件
**提示**: 在 `src/qwenpaw/app/routers/` 下创建新模块，使用 `APIRouter` 并在 `__init__.py` 中注册
**参考思路**: 创建 `routers/bookmarks.py`，用 `APIRouter(prefix="/bookmarks")` 定义 GET/POST/PUT/DELETE 四个端点；在 `routers/__init__.py` 中 include 该路由；AuthMiddleware 自动保护非 `_PUBLIC_PATHS` 的路径；如需公开访问则将路径添加到 `_PUBLIC_PATHS` 集合

## 知识检查

1. **FastAPI 中间件按注册顺序反向执行，如果希望请求处理顺序为 CORS -> Auth -> AgentContext，应该如何注册？如果注册错误会导致什么问题？**

2. **两阶段启动架构中，Phase 1 为什么必须在 <100ms 内完成？如果 Phase 2 的后台初始化失败，对已接收的请求会有什么影响？**

3. **`DynamicMultiAgentRunner` 通过 `TaskTracker` 注册外部请求的目的是什么？如果不注册，Agent 热重载时可能出现什么问题？**

---

## 延伸阅读

| 章节 | 说明 |
|------|------|
| [67-API路由系统详解](./67-API路由系统详解.md) | API 路由系统的完整设计 |
| [50-认证授权系统详解](./50-认证授权系统详解.md) | 认证与授权中间件的实现细节 |
| [72-错误处理与日志记录](./72-错误处理与日志记录.md) | 全局错误处理与日志记录机制 |

