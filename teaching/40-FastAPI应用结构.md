# FastAPI 应用结构

## 概述

QwenPaw 的 Web 应用基于 FastAPI 构建，采用**两阶段启动**架构（<100ms 快速响应 + 后台重型初始化），中间件按顺序执行，提供完整的 REST API 路由系统。

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

## 4. 特殊路由

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

## 5. 应用场景

### 5.1 多 Agent 路由

**场景**：通过 URL 路径区分不同 Agent。

**实现**：
- `/api/agents/agent1/chats`
- `/api/agents/agent2/chats`

`AgentContextMiddleware` 从路径提取 `agentId` 并设置到 `request.state`。

### 5.2 认证与授权

**场景**：保护 API 端点，需要 JWT Token 认证。

**流程**：
1. `AuthMiddleware` 从请求提取 Token
2. 验证 Token 有效性
3. 将用户信息设置到 `request.state.user`
4. 路由处理器可通过 `request.state.user` 访问用户信息

### 5.3 静态文件服务

**场景**：提供 Web UI 静态文件。

**实现**：
```python
# 根路径返回静态文件
@app.get("/")
def read_root():
    if _CONSOLE_INDEX and _CONSOLE_INDEX.exists():
        return FileResponse(_CONSOLE_INDEX)
```

### 5.4 WebSocket 实时通信

**场景**：Voice 渠道需要 WebSocket 双向通信。

**端点**：`WS /voice/ws`

---

## 6. 最佳实践

### 6.1 两阶段启动

```python
# Phase 1: 快速（< 100ms）
managers = create_managers_without_io()

# Phase 2: 后台（重型 I/O）
bg_task = asyncio.create_task(heavy_initialization())
```

**优势**：服务器快速响应，用户无需等待所有初始化完成。

### 6.2 中间件顺序

```python
# 后注册先执行
app.add_middleware(Third)  # 请求时最先
app.add_middleware(Second)
app.add_middleware(First)   # 请求时最后
```

### 6.3 作用域路由工厂

```python
def create_agent_scoped_router() -> APIRouter:
    router = APIRouter(prefix="/agents/{agentId}")
    router.include_router(agent_router)
    return router
```

### 6.4 跳过认证路径配置

```python
# 将公开端点添加到 _PUBLIC_PATHS
_PUBLIC_PATHS = frozenset({
    "/api/auth/login",
    "/api/version",
    ...
})
```

---

## 7. 常见问题

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

## 8. 设计模式

### 8.1 两阶段启动

```python
# Phase 1: 快速（< 100ms）
managers = create_managers_without_io()

# Phase 2: 后台（重型 I/O）
bg_task = asyncio.create_task(heavy_initialization())
```

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

---

## 9. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| _app.py | `src/qwenpaw/app/_app.py` |
| AgentContextMiddleware | `src/qwenpaw/app/routers/agent_scoped.py:9` |
| AuthMiddleware | `src/qwenpaw/app/auth.py:567` |
| 路由聚合 | `src/qwenpaw/app/routers/__init__.py` |
| Agent 作用域路由 | `src/qwenpaw/app/routers/agent_scoped.py:49` |
