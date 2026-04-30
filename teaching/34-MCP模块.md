# MCP 模块 (Model Context Protocol)

MCP 模块管理 MCP 客户端连接，支持热更新和多种传输协议。

## 核心文件

| 文件路径 | 关键类和行号 |
|---------|------------|
| `app/mcp/__init__.py` | 模块导出 (L11-20) |
| `app/mcp/manager.py` | `MCPClientManager` (L23-266) |
| `app/mcp/stateful_client.py` | `StdIOStatefulClient` (L36-320), `HttpStatefulClient` (L322-599) |
| `app/mcp/watcher.py` | `MCPConfigWatcher` (L24-331) |
| `app/routers/mcp.py` | API 路由 (L17-484) |
| `config/config.py` | `MCPClientConfig` (L1012-1085), `MCPConfig` (L1088-1106) |

## MCPClientManager

**文件**: `src/qwenpaw/app/mcp/manager.py`

### 类定义 (L23-38)

```python
class MCPClientManager:
    """Manages MCP clients with hot-reload support."""

    def __init__(self) -> None:
        """Initialize an empty MCP client manager."""
        self._clients: Dict[str, Any] = {}
        self._lock = asyncio.Lock()
```

### 关键方法

| 方法 | 行号 | 功能 |
|-----|------|-----|
| `init_from_config()` | L39-60 | 从配置初始化所有客户端 |
| `get_clients()` | L62-76 | 获取所有活跃客户端列表 |
| `get_client()` | L78-88 | 获取特定客户端 |
| `replace_client()` | L90-131 | 热更新替换客户端 |
| `remove_client()` | L133-147 | 移除客户端 |
| `close_all()` | L149-164 | 关闭所有客户端 |

## 配置类

**文件**: `src/qwenpaw/config/config.py`

### MCPClientConfig (L1012-1027)

```python
class MCPClientConfig(BaseModel):
    """Configuration for a single MCP client."""

    name: str
    description: str = ""
    enabled: bool = True
    transport: Literal["stdio", "streamable_http", "sse"] = "stdio"
    url: str = ""
    headers: Dict[str, str] = Field(default_factory=dict)
    command: str = ""
    args: List[str] = Field(default_factory=list)
    env: Dict[str, str] = Field(default_factory=dict)
    cwd: str = ""
```

## 客户端架构

**文件**: `src/qwenpaw/app/mcp/stateful_client.py`

### StdIOStatefulClient (L36-320)

本地进程模式：

```python
class StdIOStatefulClient(StatefulClientBase):
    def __init__(
        self,
        name: Any,
        command: Any,
        args: list[str] | None = None,
        env: dict[str, str] | None = None,
        cwd: str | None = None,
        encoding: str = "utf-8",
        ...
    ) -> None:
```

### HttpStatefulClient (L322-599)

远程 HTTP/SSE 模式：

```python
class HttpStatefulClient(StatefulClientBase):
    def __init__(
        self,
        name: Any,
        transport: Any,  # "streamable_http" or "sse"
        url: Any,
        headers: dict[str, str] | None = None,
        timeout: float = 30,
        sse_read_timeout: float = 60 * 5,
        ...
    ) -> None:
```

## 跨任务生命周期管理

**问题**: 使用 AgentScope 的 StatefulClientBase 在 uvicorn/FastAPI 中会出现 CPU 泄漏

**解决方案** (L112-175):

```python
async def _run_lifecycle(self) -> None:
    """Run MCP client lifecycle in a dedicated task."""
    while not self._stop_event.is_set():
        try:
            async with AsyncExitStack() as stack:
                context = await stack.enter_async_context(
                    stdio_client(self.server_params),
                )
                self.session = ClientSession(read_stream, write_stream)
                await stack.enter_async_context(self.session)
                await self.session.initialize()

                self.is_connected = True
                self._ready_event.set()

                while not self._reload_event.is_set() and not self._stop_event.is_set():
                    await asyncio.sleep(0.1)
```

## 工具调用

**list_tools()** (L269-284):

```python
async def list_tools(self):
    self._validate_connection()
    res = await self.session.list_tools()
    self._cached_tools = res.tools
    return res.tools
```

**call_tool()** (L286-301):

```python
async def call_tool(self, name: str, arguments: dict | None = None):
    self._validate_connection()
    return await self.session.call_tool(name, arguments or {})
```

## 与其他模块的交互

| 模块 | 文件 | 用途 |
|------|------|------|
| `react_agent.py` | L22 | 导入 MCP 客户端类 |
| `react_agent.py` | L481-544 | register_mcp_clients() 注册客户端 |
| `runner.py` | L144, L497-498 | 获取 MCP 客户端列表 |
| `workspace.py` | L101-103 | mcp_manager 属性 |
| `watcher.py` | L24-331 | MCPConfigWatcher 热更新 |

## API 路由

**文件**: `src/qwenpaw/app/routers/mcp.py`

| 端点 | 方法 | 功能 |
|-----|------|-----|
| `/mcp` | GET | 列出所有 MCP 客户端 |
| `/mcp/{client_key}` | GET | 获取特定客户端详情 |
| `/mcp/{client_key}/tools` | GET | 列出客户端工具 |
| `/mcp` | POST | 创建新客户端 |
| `/mcp/{client_key}` | PUT | 更新客户端 |
| `/mcp/{client_key}/toggle` | PATCH | 切换启用状态 |
| `/mcp/{client_key}` | DELETE | 删除客户端 |

## 核心架构流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend (React)                         │
└──────────────────────────┼──────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                    FastAPI Backend                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              routers/mcp.py                               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌──────────────────────────┼──────────────────────────────┐   │
│  │              app/mcp/manager.py                          │   │
│  │              MCPClientManager                            │   │
│  └──────────────────────────┼──────────────────────────────┘   │
│                              │                                  │
│  ┌──────────────────────────┼──────────────────────────────┐   │
│  │              stateful_client.py                           │   │
│  │  StdIOStatefulClient      HttpStatefulClient             │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                           │
                 ┌─────────┴─────────┐
                 │   MCP Protocol     │
                 └───────────────────┘
```

## 设计亮点

1. **跨任务生命周期管理**: 解决 anyio CancelScope 在不同任务中退出的 CPU 泄漏
2. **热更新支持**: MCPConfigWatcher 轮询配置文件变化，自动重载客户端
3. **环境变量安全**: API 返回时自动掩码敏感信息
4. **多传输协议**: StdIO、Streamable HTTP、SSE 三种传输模式
5. **自动恢复**: Agent 启动时可重新连接断开的 MCP 客户端
