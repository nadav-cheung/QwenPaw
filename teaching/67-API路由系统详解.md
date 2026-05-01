# API 路由系统详解

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 分析 REST API 的路由注册模式 2) 理解路由工厂和中间件链 3) 使用 API 进行集成开发 |
| **前置知识** | [40-FastAPI应用结构](./40-FastAPI应用结构.md) |
| **预计时长** | 35 分钟（阅读 25 分钟 + 练习 10 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `REST API` `路由` `中间件` |

> **一句话概述**：本章解析 QwenPaw 的分层路由架构，涵盖全局路由、Agent 作用域路由、认证中间件以及自定义路由注册的完整模式。

## 概述

QwenPaw 的 API 采用分层路由结构：全局路由 `/api/*`、Agent 作用域路由 `/api/agents/{agentId}/*`、专用路由（voice）独立于 `/api` 前缀。

---

## 1. 路由组织

源码路径：`src/qwenpaw/app/routers/__init__.py:29`

```python
# src/qwenpaw/app/routers/__init__.py:29
router = APIRouter()
router.include_router(agents_router)       # /api/agents
router.include_router(agent_router)        # /api/agent
router.include_router(config_router)        # /api/config
router.include_router(messages_router)     # /api/messages
router.include_router(auth_router)         # /api/auth
router.include_router(skills_router)       # /api/skills
router.include_router(cron_router)         # /api/cron
router.include_router(local_models_router) # /api/local-models
router.include_router(voice_router)        # /voice（根路径）
```

### 1.1 路由分组说明

| 路由 | 前缀 | 作用域 | 说明 |
|------|------|--------|------|
| agents_router | `/api/agents` | 全局 | Agent CRUD |
| agent_router | `/api/agent` | 全局 | 当前 Agent 操作 |
| config_router | `/api/config` | 全局 | 配置管理 |
| messages_router | `/api/messages` | 全局 | 消息收发 |
| auth_router | `/api/auth` | 全局 | 认证 |
| skills_router | `/api/skills` | 全局 | 技能管理 |
| cron_router | `/api/cron` | 全局 | 定时任务 |
| local_models_router | `/api/local-models` | 全局 | 本地模型 |
| voice_router | `/voice` | 全局 | 语音（无 `/api` 前缀） |

---

## 2. 路由注册

源码路径：`src/qwenpaw/app/_app.py:610`

```python
# src/qwenpaw/app/_app.py:610
app.include_router(api_router, prefix="/api")

# Agent 作用域路由
agent_scoped_router = create_agent_scoped_router()
app.include_router(agent_scoped_router, prefix="/api")

# Voice 路由（根路径）
app.include_router(voice_router, tags=["voice"])
```

### 2.1 Agent 作用域路由

源码路径：`src/qwenpaw/app/routers/agent_scoped.py:53`

```python
# /api/agents/{agentId}/* 下的所有路由
router = APIRouter(prefix="/agents/{agentId}")
router.include_router(agent_router)     # /agent/*
router.include_router(chats_router)      # /chats/*
router.include_router(config_router)      # /config/*
router.include_router(cron_router)       # /cron/*
router.include_router(mcp_router)        # /mcp/*
router.include_router(skills_router)      # /skills/*
router.include_router(tools_router)      # /tools/*
router.include_router(workspace_router)   # /workspace/*
```

**Agent 作用域路由结构**：

```
/api/agents/{agentId}/agent/*      # Agent 操作
/api/agents/{agentId}/chats/*      # 聊天历史
/api/agents/{agentId}/config/*    # Agent 配置
/api/agents/{agentId}/cron/*      # 定时任务
/api/agents/{agentId}/mcp/*       # MCP 工具
/api/agents/{agentId}/skills/*    # 技能
/api/agents/{agentId}/tools/*     # 工具
/api/agents/{agentId}/workspace/*  # 工作区
```

---

## 3. 核心端点

### 3.1 Agent 管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/agents` | 列出所有 Agent |
| POST | `/api/agents` | 创建新 Agent |
| GET | `/api/agents/{agentId}` | 获取详情 |
| PUT | `/api/agents/{agentId}` | 更新配置 |
| DELETE | `/api/agents/{agentId}` | 删除 Agent |
| PATCH | `/api/agents/{agentId}/toggle` | 切换启用状态 |

### 3.2 消息发送

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/messages/send` | 发送消息到渠道 |

```python
# src/qwenpaw/app/routers/messages.py:40
class SendMessageRequest(BaseModel):
    channel: str        # console, dingtalk, feishu, discord...
    target_user: str
    target_session: str
    text: str
```

### 3.3 配置管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/config/channels` | 列出所有频道 |
| PUT | `/api/config/channels` | 更新频道配置 |
| GET | `/api/config/channels/{name}/health` | 健康检查 |
| POST | `/api/config/channels/{name}/restart` | 重启频道 |
| GET/PUT | `/api/config/security/tool-guard` | 工具 Guard |
| GET/PUT | `/api/config/security/file-guard` | 文件 Guard |

### 3.4 认证

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/auth/login` | 登录 |
| POST | `/api/auth/register` | 注册 |
| GET | `/api/auth/status` | 认证状态 |
| POST | `/api/auth/revoke-token` | 撤销令牌 |

### 3.5 定时任务

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/cron` | 列出定时任务 |
| POST | `/api/cron` | 创建定时任务 |
| DELETE | `/api/cron/{task_id}` | 删除定时任务 |

### 3.6 本地模型

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/local-models` | 列出可用模型 |
| POST | `/api/local-models/pull` | 拉取模型 |
| DELETE | `/api/local-models/{model}` | 删除模型 |

---

## 4. 中间件

源码路径：`src/qwenpaw/app/_app.py:518`

```python
# Agent 上下文中间件（从路径提取 agentId）
app.add_middleware(AgentContextMiddleware)
# 认证中间件
app.add_middleware(AuthMiddleware)
```

### 4.1 AgentContextMiddleware

```python
# 从 /api/agents/{agentId}/* 路径提取 agentId
# 存入 request.state.agent_id
# 后续处理器可直接从 request.state.agent_id 获取当前 Agent ID
```

### 4.2 AuthMiddleware

```python
# 公开路径（无需认证）
_PUBLIC_PATHS = {
    "/api/auth/login",
    "/api/auth/register",
    "/api/auth/status",
    "/api/version",
    "/api/settings/language",
    "/api/plugins",
}
# 本地请求（127.0.0.1, ::1）跳过认证
```

**认证跳过条件**：
1. 路径在 `_PUBLIC_PATHS` 中
2. 请求来自本地回环地址（127.0.0.1 或 ::1）

---

## 5. WebSocket 处理

### 5.1 语音通话 WebSocket

源码路径：`src/qwenpaw/app/routers/voice.py:125`

```python
@voice_router.websocket("/voice/ws")
async def voice_ws(websocket: WebSocket):
    token = websocket.query_params.get("token", "")
    if not voice_ch.validate_ws_token(token):
        await websocket.close(code=1008)
        return
    await websocket.accept()
    handler = ConversationRelayHandler(ws=websocket, ...)
    await handler.handle()
```

**WebSocket 端点**：`ws://host:port/voice/ws?token=xxx`

### 5.2 SSE 流式端点

```python
# 任务流式输出
GET /api/agents/{agentId}/tasks/{taskId}/stream
```

---

## 6. 自定义路由注册

### 6.1 自定义渠道路由

```python
# custom_channels/my_channel/__init__.py
from fastapi import APIRouter

router = APIRouter()

@router.post("/webhook")
async def webhook_handler(data: dict):
    ...

def register_app_routes(app):
    # 注意：必须使用 /api/ 前缀
    app.include_router(router, prefix="/api/my-channel")
```

### 6.2 全局中间件注册

```python
# app/_app.py 中
app.add_middleware(MyCustomMiddleware)
```

---

## 7. 应用场景

### 场景一：多渠道消息聚合

```bash
# 通过统一 API 发送消息到任意渠道
curl -X POST http://localhost:8000/api/messages/send \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "telegram",
    "target_user": "user123",
    "target_session": "session456",
    "text": "Hello from API!"
  }'
```

### 场景二：多 Agent 管理

```bash
# 创建新 Agent
curl -X POST http://localhost:8000/api/agents \
  -d '{"id": "my-agent", "name": "My Agent"}'

# 切换 Agent 启用状态
curl -X PATCH http://localhost:8000/api/agents/my-agent/toggle

# 获取 Agent 状态
curl http://localhost:8000/api/agents/my-agent
```

### 场景三：热重载配置

```bash
# 修改频道配置后热重载
curl -X PUT http://localhost:8000/api/config/channels \
  -d '{"telegram": {"enabled": true, "bot_token": "xxx"}}'

# 单独重启某渠道
curl -X POST http://localhost:8000/api/config/channels/telegram/restart
```

---

## 8. 最佳实践

### 8.1 路径命名规范

```python
# 正确：RESTful 风格
router.get("/agents/{agent_id}")
router.post("/agents")
router.delete("/agents/{agent_id}")

# 错误：动词在路径中
router.get("/getAgent")
router.post("/createAgent")
```

### 8.2 中间件顺序

```python
# 中间件按添加顺序执行（从外到内）
app.add_middleware(AuthMiddleware)      # 1. 认证（最外层）
app.add_middleware(AgentContextMiddleware) # 2. 上下文（在内层）
# 请求处理...
```

### 8.3 错误处理

```python
# 统一的错误响应格式
@app.exception_handler(ValueError)
async def value_error_handler(request, exc):
    return JSONResponse(
        status_code=400,
        content={"error": str(exc), "type": "validation_error"}
    )
```

### 8.4 路由前缀一致性

```python
# 全局路由用 /api/ 前缀
app.include_router(router, prefix="/api")

# Agent 作用域路由也用 /api/ 前缀
app.include_router(agent_router, prefix="/api")

# Voice 等特殊路由可不用 /api/ 前缀
app.include_router(voice_router, prefix="/voice")  # 无 /api/
```

---

## 9. 常见问题

### Q1: 自定义路由不生效

**原因**：路由未加 `/api/` 前缀，被 SPA catch-all 拦截。

**解决**：
```python
# 正确
app.include_router(router, prefix="/api/my-channel")
# 错误 - 会被 SPA 路由拦截
app.include_router(router, prefix="/my-channel")
```

### Q2: 认证中间件误拦本地请求

**原因**：本地回环检查逻辑有误。

**解决**：
```python
# 检查请求源 IP
if request.client.host in ("127.0.0.1", "::1", "localhost"):
    # 跳过认证
    pass
```

### Q3: Agent 作用域路由获取不到 agentId

**原因**：中间件未正确设置 `request.state.agent_id`。

**解决**：
```python
# 在路由处理器中显式获取
agent_id = request.path_params.get("agentId")
if not agent_id:
    agent_id = request.state.agent_id
```

### Q4: WebSocket 连接被拒绝

**原因**：token 验证失败或跨域问题。

**解决**：
```bash
# 检查 token 有效性
curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:8000/voice/ws?token=invalid"
# 返回 1008 (Policy Violation)

# 使用有效 token
wss://localhost:8000/voice/ws?token=VALID_TOKEN
```

---

## 知识检查

1. 全局路由 `/api/*` 和 Agent 作用域路由 `/api/agents/{agentId}/*` 的区别是什么？为什么需要两套路由体系？
2. `AuthMiddleware` 跳过认证的两个条件分别是什么？本地回环地址跳过认证的设计在什么场景下可能带来安全风险？
3. 自定义渠道路由为什么必须使用 `/api/` 前缀？如果不加前缀会被什么机制拦截？

---

## 10. 总结

### 核心要点

1. **分层路由**：全局路由 + Agent 作用域路由 + 专用路由
2. **Agent 上下文**：通过中间件从路径提取 agentId，存入 request.state
3. **认证策略**：公开路径 + 本地请求跳过认证
4. **Voice 路由**：独立于 `/api` 前缀（避免 SPA 拦截 WebSocket）
5. **自定义扩展**：custom_channels 可注册额外路由（必须 `/api/` 前缀）

### 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| 路由聚合 | `src/qwenpaw/app/routers/__init__.py` |
| Agent 作用域 | `src/qwenpaw/app/routers/agent_scoped.py` |
| Agent 路由 | `src/qwenpaw/app/routers/agents.py` |
| 消息路由 | `src/qwenpaw/app/routers/messages.py` |
| 配置路由 | `src/qwenpaw/app/routers/config.py` |
| 认证路由 | `src/qwenpaw/app/routers/auth.py` |
| 语音路由 | `src/qwenpaw/app/routers/voice.py` |

---

## 延伸阅读

- [40-FastAPI应用结构](./40-FastAPI应用结构.md) -- 理解 FastAPI 应用的整体架构和模块组织
- [93-CORS与中间件](./93-CORS与中间件.md) -- 深入了解跨域配置和中间件链的工作原理
