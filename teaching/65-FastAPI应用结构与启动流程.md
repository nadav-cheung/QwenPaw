# FastAPI 应用结构与启动流程

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 追踪 FastAPI 应用从创建到就绪的完整流程 2) 理解两阶段启动的优先级排序 3) 分析服务依赖和并发初始化 |
| **前置知识** | [40-FastAPI应用结构](./40-FastAPI应用结构.md)、[27-应用启动与插件系统](./27-应用启动与插件系统.md) |
| **预计时长** | 40 分钟（阅读 30 分钟 + 练习 10 分钟） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `两阶段启动` `服务依赖` `并发初始化` |

> **一句话概述**：本章追踪 FastAPI 应用从创建到完全就绪的全过程，重点分析两阶段启动架构的设计意图和服务优先级排序机制。

## 概述

QwenPaw 基于 FastAPI 实现，采用两阶段启动架构：第一阶段同步初始化（<100ms），第二阶段后台初始化，支持在启动过程中响应 HTTP 请求。

`★ Insight ─────────────────────────────────────`
- **两阶段启动**是现代 Web 应用的经典模式：快速响应 HTTP + 后台完成重型初始化
- **lifespan 上下文管理器**替代旧的 `on_event` API，提供更清晰的启动/关闭语义
- **后台任务取消**使用 `asyncio.create_task` + `task.cancel()` 实现优雅关闭
`─────────────────────────────────────────────────`

---

## 1. 应用入口

源码路径：`src/qwenpaw/__main__.py:1`

```python
# python -m qwenpaw 入口
from .cli.main import cli
if __name__ == "__main__":
    cli()
```

### 1.1 CLI 命令

源码路径：`src/qwenpaw/cli/app_cmd.py:55`

```python
# qwenpaw app 命令
uvicorn.run(
    "qwenpaw.app._app:app",
    host=host,
    port=port,
    reload=reload,
    workers=1,
)
```

**注意**：`workers=1` 是硬编码的，不支持多进程。原因：QwenPaw 的多 Agent 共享状态在单进程内通过内存管理，多进程会破坏这一设计。

---

## 2. FastAPI 应用创建

源码路径：`src/qwenpaw/app/_app.py:511`

```python
# src/qwenpaw/app/_app.py:511
app = FastAPI(
    lifespan=lifespan,
    docs_url="/docs" if DOCS_ENABLED else None,
    openapi_url="/openapi.json" if DOCS_ENABLED else None,
)
```

**参数说明**：

| 参数 | 说明 |
|------|------|
| `lifespan` | 生命周期管理器，控制启动和关闭逻辑 |
| `docs_url` | Swagger UI 路径（默认 `/docs`） |
| `openapi_url` | OpenAPI schema 路径（默认 `/openapi.json`） |

---

## 3. 两阶段启动

源码路径：`src/qwenpaw/app/_app.py:219`

### 3.1 第一阶段（同步，<100ms）

```python
# src/qwenpaw/app/_app.py:226
async def lifespan(app: FastAPI):
    # === Phase 1: Fast synchronous setup ===
    # 自动注册
    # 遥测收集
    # 遗留配置迁移
    # 创建核心管理器
    app.state.multi_agent_manager = MultiAgentManager()
    app.state.provider_manager = ProviderManager()
    app.state.local_model_manager = LocalModelManager.get_instance()
    yield  # 服务器接收 HTTP 请求
```

**Phase 1 完成的工作**：

| 步骤 | 组件 | 说明 |
|------|------|------|
| 1 | 自动模块注册 | 扫描并注册所有内置组件 |
| 2 | 遥测初始化 | 设置 Telemetry 收集器 |
| 3 | 遗留配置迁移 | 检测并迁移旧版配置 |
| 4 | 创建管理器 | MultiAgentManager / ProviderManager / LocalModelManager |

**关键设计**：Phase 1 必须在 100ms 内完成，否则影响 `qwenpaw app` 的启动体验。

### 3.2 第二阶段（后台）

```python
# src/qwenpaw/app/_app.py:288
_bg_task = asyncio.create_task(_background_startup())
# 后台执行：
# - 启动所有配置的 Agent
# - 恢复本地模型服务
# - 插件系统初始化
# - 插件启动钩子
```

**后台启动任务内容**：

1. **Agent 启动**：`start_all_configured_agents()` 并行启动所有已启用 Agent
2. **本地模型恢复**：检查并启动本地模型服务（Ollama 等）
3. **插件初始化**：扫描并初始化所有插件
4. **插件启动钩子**：调用各插件的 `on_startup` 钩子

---

## 4. 服务初始化顺序

源码路径：`src/qwenpaw/app/workspace/service_manager.py:173`

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

**优先级分组执行**：同优先级并发，不同优先级串行。

**执行图解**：

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

---

## 5. Agent 初始化

源码路径：`src/qwenpaw/app/multi_agent_manager.py:454`

```python
# src/qwenpaw/app/multi_agent_manager.py:454
async def start_all_configured_agents():
    # 并行启动所有已启用 Agent
    await asyncio.gather(*[start_one_agent(id) for id in enabled_ids])
```

**每个 Agent 的工作区按优先级启动服务。**

### 5.1 单个 Agent 启动流程

```python
async def start_one_agent(agent_id: str):
    # 1. 加载 Agent 配置
    config = load_agent_config(agent_id)

    # 2. 创建 Workspace
    workspace = Workspace(agent_id=agent_id, config=config)

    # 3. 注入可复用组件（如 memory_manager）
    await workspace.set_reusable_components(...)

    # 4. 启动 Workspace（按优先级启动所有服务）
    await workspace.start()

    # 5. 注册到 MultiAgentManager
    manager.register(agent_id, workspace)
```

---

## 6. 频道初始化

源码路径：`src/qwenpaw/app/channels/manager.py:462`

```python
# src/qwenpaw/app/channels/manager.py:462
async def start_all(self):
    # 初始化 UnifiedQueueManager
    # 为每个频道设置 enqueue 回调
    # 依次启动每个频道
    for g in snapshot:
        await g.start()
```

---

## 7. 健康检查端点

| 端点 | 说明 |
|------|------|
| `GET /api/config/channels/{name}/health` | 频道健康状态 |
| `GET /api/auth/status` | 认证状态 |
| `GET /api/version` | 应用版本 |
| `GET /api/doctor/runtime` | 运行时诊断 |

### 7.1 健康检查响应示例

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

## 8. 启动序列图

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

**两阶段启动的优势**：

1. **快速响应**：HTTP 请求在 Phase 1 后即可响应，不需要等待所有 Agent 就绪
2. **优雅降级**：部分 Agent 启动失败不影响其他 Agent 和 HTTP 服务
3. **开发体验**：`qwenpaw app` 命令返回快，开发者无需等待

---

## 9. 应用场景

### 场景一：滚动更新

```
新请求 → FastAPI 处理（Phase 1 已就绪）
               ↓
        Agent 仍在启动中
               ↓
        请求进入队列或返回 503（取决于配置）
```

### 场景二：插件热加载

```python
# 插件的 on_startup 钩子在 Phase 2 执行
class MyPlugin:
    async def on_startup(self, app):
        # 注册自定义路由
        app.include_router(my_router)
        # 初始化资源
        await self.init_resources()
```

### 场景三：健康检查前置

```bash
# 在 Agent 完全启动前，健康检查已可用
curl http://localhost:8000/api/version
# 返回 {"version": "1.0.0"}

# 但 Agent 相关 API 可能返回 503
curl http://localhost:8000/api/agents
# 返回 {"error": "agents not ready"}
```

---

## 10. 最佳实践

### 10.1 健康检查实现

```python
@app.get("/api/health")
async def health_check():
    return {
        "status": "ok",
        "phase": "ready" if _startup_complete else "starting"
    }
```

### 10.2 启动依赖检查

```python
# 自定义路由中检查 Agent 是否就绪
@app.get("/api/agents/{agent_id}/status")
async def agent_status(agent_id: str):
    manager = request.app.state.multi_agent_manager
    if not manager.is_agent_ready(agent_id):
        raise HTTPException(503, "Agent not ready")
    return {"status": "ready"}
```

### 10.3 优雅关闭

```bash
# 使用 qwenpaw shutdown 优雅关闭
qwenpaw shutdown
# 等价于发送 SIGTERM，让 uvicorn 优雅关闭
```

---

## 11. 常见问题

### Q1: 启动后立即请求返回 503

**原因**：Phase 1 完成但 Phase 2 尚未完成，Agent 未就绪。

**解决**：
```python
# 前端轮询健康状态
while True:
    r = requests.get("/api/version")
    if r.status_code == 200:
        break
    await asyncio.sleep(1)
```

### Q2: 多 Worker 模式不支持

**原因**：`workers=1` 硬编码，多进程会破坏共享状态。

**解决**：如需多实例，使用容器层面负载均衡而非进程内多 worker。

### Q3: 插件启动钩子执行慢

**原因**：插件 `on_startup` 在 Phase 2 串行执行。

**解决**：
```python
# 将耗时操作移到后台线程
class MyPlugin:
    async def on_startup(self, app):
        asyncio.create_task(self._slow_init())
```

### Q4: 遗留配置迁移失败

**原因**：旧版配置格式不完整或权限不足。

**解决**：
```bash
# 查看迁移日志
qwenpaw app --log-level DEBUG
# 或手动执行迁移
python -c "from qwenpaw.config.config import migrate_legacy_config_to_multi_agent; migrate_legacy_config_to_multi_agent()"
```

---

## 知识检查

1. 两阶段启动中，Phase 1 为什么必须在 100ms 内完成？如果 Phase 1 耗时过长，对用户体验和系统行为有什么影响？
2. ServiceManager 的优先级分组中，Priority 20 的三个服务（memory_manager、mcp_manager、chat_manager）为什么可以并发启动？它们之间存在依赖关系吗？
3. 为什么 `workers=1` 是硬编码的？如果改为多 worker 模式，会破坏哪些共享状态？

---

## 12. 总结

### 核心要点

1. **两阶段启动**：Phase 1 同步快速（<100ms），Phase 2 后台异步
2. **快速响应**：HTTP 请求在 Phase 1 后即可处理
3. **服务优先级**：Runner > Memory/MCP/Chat（并发）> Channel > Cron > Watcher
4. **单 Worker 设计**：多 Agent 共享状态在单进程内管理
5. **优雅关闭**：SIGTERM 触发 lifespan shutdown 清理

### 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| FastAPI 应用 | `src/qwenpaw/app/_app.py:511` |
| 生命周期管理 | `src/qwenpaw/app/_app.py:219` |
| 多 Agent 管理 | `src/qwenpaw/app/multi_agent_manager.py` |
| 工作区 | `src/qwenpaw/app/workspace/workspace.py` |
| 服务管理 | `src/qwenpaw/app/workspace/service_manager.py` |
| 频道管理 | `src/qwenpaw/app/channels/manager.py` |
| 启动横幅 | `src/qwenpaw/utils/startup_display.py` |

---

## 延伸阅读

- [94-生命周期管理](./94-生命周期管理.md) -- 深入了解 lifespan 上下文管理器和优雅关闭机制
- [27-应用启动与插件系统](./27-应用启动与插件系统.md) -- 理解插件系统在启动流程中的初始化时序
