# CORS 与中间件

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 配置 CORS 安全策略 2) 分析中间件链的执行顺序 3) 实现自定义中间件 |
| **前置知识** | [40-FastAPI应用结构](./40-FastAPI应用结构.md) |
| **预计时长** | 25 分钟（阅读 20 分钟 + 练习 5 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `CORS` `中间件` `安全策略` |

> **一句话概述**：本章讲解 QwenPaw 的中间件栈架构，包括 AgentContextMiddleware、AuthMiddleware 和 CORS 的执行顺序、agentId 提取优先级和认证跳过条件，帮助读者理解请求处理管道并掌握自定义中间件的扩展方法。

## 概述

QwenPaw 的中间件栈包括 AgentContextMiddleware（上下文注入）、AuthMiddleware（认证）和 CORS 配置，按顺序执行以确保请求正确处理和安全性。

---

## 1. 中间件顺序

源码路径：`src/qwenpaw/app/_app.py`

```
请求进入
    ↓
AgentContextMiddleware  (提取 agentId 到 request.state)
    ↓
AuthMiddleware         (Bearer token 验证)
    ↓
CORS Middleware        (跨域资源共享)
    ↓
路由处理
```

**执行顺序说明**：中间件按注册顺序**逆序**执行，因此最后注册的 AgentContextMiddleware 最先处理请求。

### 1.1 中间件职责

| 中间件 | 职责 | 路径匹配 |
|--------|------|----------|
| AgentContextMiddleware | 从 URL 路径提取 agentId | `/api/agents/{agentId}/*` |
| AuthMiddleware | 认证验证 | 所有 `/api/` 路径 |
| CORS | 跨域头处理 | 所有路径 |

---

## 2. AgentContextMiddleware

源码路径：`src/qwenpaw/app/routers/agent_scoped.py:12`

### 2.1 类定义

```python
# src/qwenpaw/app/routers/agent_scoped.py:12
class AgentContextMiddleware(BaseHTTPMiddleware):
    """Middleware to inject agentId into request.state."""
```

### 2.2 agentId 提取优先级

```python
# src/qwenpaw/app/routers/agent_scoped.py:35
# Priority 1: 从路径提取 /api/agents/{agentId}/...
path_parts = request.url.path.split("/")
if len(path_parts) >= 4 and path_parts[2] == "agents":
    agent_id = path_parts[3]
    request.state.agent_id = agent_id

# Priority 2: 从 X-Agent-Id header 提取
if not agent_id:
    agent_id = request.headers.get("X-Agent-Id")
```

### 2.3 路由挂载结构

```python
# src/qwenpaw/app/routers/agent_scoped.py:58
router = APIRouter(prefix="/agents/{agentId}", tags=["agent-scoped"])

# 挂载的子路由：
# /agents/{agentId}/agent/*      → agent_router
# /agents/{agentId}/chats/*      → chats_router
# /agents/{agentId}/config/*      → config_router
# /agents/{agentId}/cron/*       → cron_router
# /agents/{agentId}/mcp/*        → mcp_router
# /agents/{agentId}/skills/*     → skills_router
# /agents/{agentId}/tools/*      → tools_router
# /agents/{agentId}/workspace/*   → workspace_router
# /agents/{agentId}/console/*    → console_router
# /agents/{agentId}/plugins/*     → plugins_router
```

---

## 3. AuthMiddleware

源码路径：`src/qwenpaw/app/auth.py:387`

### 3.1 类定义

```python
# src/qwenpaw/app/auth.py:387
class AuthMiddleware(BaseHTTPMiddleware):
    """Middleware that checks Bearer token on protected routes."""
```

### 3.2 跳过认证条件

```python
# src/qwenpaw/app/auth.py:416
@staticmethod
def _should_skip_auth(request: Request) -> bool:
    # 1. 认证未启用或无注册用户
    if not is_auth_enabled() or not has_registered_users():
        return True

    # 2. OPTIONS 预检请求
    if request.method == "OPTIONS":
        return True

    # 3. 公开路径
    if path in _PUBLIC_PATHS or path.startswith(_PUBLIC_PREFIXES):
        return True

    # 4. 非 /api/ 路径
    if not path.startswith("/api/"):
        return True

    # 5. 本地请求（CLI 本地运行）
    client_host = request.client.host if request.client else ""
    if client_host in ("127.0.0.1", "::1"):
        return True

    return False
```

### 3.3 公开路径列表

```python
# src/qwenpaw/app/auth.py:44
_PUBLIC_PATHS: frozenset[str] = frozenset({
    "/api/auth/login",
    "/api/auth/status",
    "/api/auth/register",
    "/api/version",
    "/api/settings/language",
    "/api/plugins",
})

_PUBLIC_PREFIXES: tuple[str, ...] = (
    "/assets/",
    "/logo.png",
    "/qwenpaw-symbol.svg",
    "/api/plugins/",  # plugin JS bundles served to unauthenticated login page
)
```

### 3.4 Token 验证流程

```python
# src/qwenpaw/app/auth.py:402
# Bearer token 提取顺序：
# 1. Authorization header: "Bearer <token>"
# 2. WebSocket upgrade: query_params.get("token")
# 3. 普通请求: query_params.get("token")

# 验证成功后注入用户信息
request.state.user = user
```

### 3.5 Token 结构

```python
# src/qwenpaw/app/auth.py:106
# Token = base64(payload).signature
# payload = {"sub": username, "exp": expiry, "iat": issued_at, "jti": token_id}
# 使用 HMAC-SHA256 签名，不依赖 PyJWT
```

### 3.6 Token 吊销机制

```python
# src/qwenpaw/app/auth.py:170
# O(1) 字典查找：revoked_tokens_meta[jti] = exp
# 支持单独吊销和全部吊销（JWT secret 轮换）
```

---

## 4. CORS 配置

### 4.1 FastAPI CORS 中间件

```python
# FastAPI 内置 CORS 配置
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],           # 生产环境应限制
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### 4.2 跨域头说明

| 头信息 | 说明 |
|--------|------|
| `Access-Control-Allow-Origin` | 允许的源 |
| `Access-Control-Allow-Credentials` | 是否允许携带 cookie |
| `Access-Control-Allow-Methods` | 允许的 HTTP 方法 |
| `Access-Control-Allow-Headers` | 允许的请求头 |

### 4.3 生产环境 CORS 配置

```python
# 生产环境应限制允许的源
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://your-domain.com",
        "https://app.your-domain.com",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Agent-Id"],
)
```

---

## 5. 中间件注册

源码路径：`src/qwenpaw/app/_app.py`

### 5.1 注册顺序

```python
# 中间件按注册顺序逆序执行
app.add_middleware(AgentContextMiddleware)   # 最后执行，最外层
app.add_middleware(AuthMiddleware)          # 第二
app.add_middleware(CORSMiddleware)         # 第一，最先执行
```

### 5.2 中间件执行流程图

```
请求进入
    │
    ▼
┌─────────────────────────────────────┐
│  CORS Middleware (最先注册，最后执行)  │
│  - 处理 OPTIONS 预检                  │
│  - 添加 CORS 响应头                   │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  AuthMiddleware (第二注册，中间执行)   │
│  - 检查跳过条件                        │
│  - 验证 Bearer Token                  │
│  - 注入 request.state.user            │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  AgentContextMiddleware (最后注册，   │
│                    最先执行)          │
│  - 提取 agentId                       │
│  - 注入 request.state.agent_id        │
└─────────────────────────────────────┘
    │
    ▼
  路由处理
```

---

## 6. 最佳实践

### 6.1 新增中间件

添加新的中间件时，注意注册顺序：

```python
# 新中间件应在 CORS 之后、路由之前注册
app.add_middleware(NewMiddleware)

# 执行顺序：CORS → NewMiddleware → Auth → AgentContext → 路由
```

### 6.2 中间件中访问 request.state

在后续中间件或路由中，可以访问 `request.state` 中注入的值：

```python
# 在路由处理函数中
@router.get("/agent/info")
async def get_agent_info(request: Request):
    agent_id = request.state.agent_id  # 由 AgentContextMiddleware 注入
    user = request.state.user          # 由 AuthMiddleware 注入
    return {"agent_id": agent_id, "user": user}
```

### 6.3 跳过认证的最佳实践

对于需要公开访问的 API 端点，确保路径在 `_PUBLIC_PATHS` 或 `_PUBLIC_PREFIXES` 中。

---

## 7. 常见问题

### 7.1 跨域请求失败

**问题**：浏览器控制台显示 `Access-Control-Allow-Origin` 错误。

**原因**：
1. `allow_origins` 配置为 `["*"]` 但 `allow_credentials=True` 不兼容
2. 前端请求的 Origin 不在允许列表中

**解决**：
```python
# 方案 1：列出所有允许的源
allow_origins=["https://app.example.com"]

# 方案 2：通过环境变量动态配置
import os
allow_origins = os.getenv("CORS_ORIGINS", "").split(",") or ["*"]
```

### 7.2 Token 验证失败

**问题**：已登录用户仍然被要求重新登录。

**原因**：
1. Token 已过期（`exp` 字段）
2. Token 已被吊销
3. Token 签名验证失败

**解决**：检查 Token 结构和 HMAC 密钥是否一致。

### 7.3 agentId 无法提取

**问题**：`request.state.agent_id` 为空。

**原因**：
1. URL 路径不匹配 `/api/agents/{agentId}/*`
2. 缺少 `X-Agent-Id` header

**解决**：
```python
# 确保请求路径格式正确
# 正确：GET /api/agents/my-agent/chats
# 错误：GET /api/agent/my-agent/chats
```

### 7.4 预检请求被拦截

**问题**：OPTIONS 请求返回 401/403。

**原因**：`AuthMiddleware` 将 OPTIONS 请求当作普通请求处理。

**解决**：确保 `_should_skip_auth` 中包含 `request.method == "OPTIONS"` 的检查。

---

## 8. 总结

| 要点 | 说明 |
|------|------|
| 中间件数量 | 3 个（CORS、Auth、AgentContext） |
| 执行顺序 | 注册逆序：AgentContext → Auth → CORS |
| agentId 来源 | URL 路径 或 X-Agent-Id header |
| Token 类型 | HMAC-SHA256 签名，非 PyJWT |
| 公开路径 | `_PUBLIC_PATHS` + `_PUBLIC_PREFIXES` |

**核心文件索引**：

| 组件 | 文件路径 |
|------|----------|
| AgentContextMiddleware | `src/qwenpaw/app/routers/agent_scoped.py:12` |
| AuthMiddleware | `src/qwenpaw/app/auth.py:387` |
| _should_skip_auth | `src/qwenpaw/app/auth.py:416` |
| Token 创建/验证 | `src/qwenpaw/app/auth.py:106` |
| 公开路径配置 | `src/qwenpaw/app/auth.py:44` |

---

## 9. 交叉引用

| 相关章节 | 说明 |
|----------|------|
| [92-多语言支持与国际化](./92-多语言支持与国际化.md) | 中间件可处理 Accept-Language 请求头 |
| [94-生命周期管理](./94-生命周期管理.md) | 中间件在应用启动时注册 |
| [97-安全加固与最佳实践](./97-安全加固与最佳实践.md) | AuthMiddleware 是安全体系的一部分 |
| [99-部署与运维指南](./99-部署与运维指南.md) | systemd 服务配置与中间件启动顺序 |

---

## 知识检查

1. FastAPI 中间件的执行顺序与注册顺序是什么关系？三个中间件（CORS、Auth、AgentContext）的实际请求处理顺序是什么？

2. AuthMiddleware 的 `_should_skip_auth` 函数有哪几个跳过条件？为什么本地请求（127.0.0.1）需要跳过认证？

3. 当 `allow_origins=["*"]` 同时设置 `allow_credentials=True` 时，浏览器会报什么错误？正确的做法是什么？

---

## 延伸阅读

- [40-FastAPI应用结构](40-FastAPI应用结构.md) -- FastAPI 应用结构和中间件注册机制
- [50-认证授权系统详解](50-认证授权系统详解.md) -- AuthMiddleware 的认证流程和 Token 管理详解
