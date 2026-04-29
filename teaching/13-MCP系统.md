# MCP 系统 (Model Context Protocol)

## 概述

MCP（Model Context Protocol）是一种让 LLM 与外部工具和数据源交互的标准化协议。QwenPaw 通过 `MCPClientManager` 实现 MCP 客户端管理，支持热重载和多种传输方式。本教程深入讲解 MCP 系统架构、配置和使用方法。

---

## 1. MCP 简介

### 1.1 什么是 MCP

MCP 是一个开放协议，允许 AI 模型与外部服务交互：

```
┌─────────────┐         MCP          ┌─────────────┐
│   LLM Model │ ◄───────────────► │ MCP Server  │
│  (QwenPaw)  │                    │ (Tool Host) │
└─────────────┘                    └─────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    ▼                    ▼                    ▼
              ┌──────────┐        ┌──────────┐        ┌──────────┐
              │ Database  │        │  Files   │        │   APIs  │
              └──────────┘        └──────────┘        └──────────┘
```

### 1.2 QwenPaw MCP 架构

```
app/mcp/
├── __init__.py
├── manager.py           # MCPClientManager - 生命周期管理
├── stateful_client.py  # HttpStatefulClient, StdIOStatefulClient
└── watcher.py          # MCPConfigWatcher - 配置变更监听
```

---

## 2. MCP 客户端类型

### 2.1 HttpStatefulClient

HTTP 轮询模式的 MCP 客户端。

**源码路径**: `src/qwenpaw/app/mcp/stateful_client.py`

**核心设计**: 解决跨任务生命周期的 CPU 泄漏问题——原始 AgentScope 的 StatefulClientBase 在 uvicorn/FastAPI 环境中，`connect()` 在任务 A 中进入 AsyncExitStack，`close()` 在任务 B 中退出，导致 anyio.CancelScope 错误。

**生命周期管理** (`_run_lifecycle` 方法，第112-175行):

```python
class StdIOStatefulClient(StatefulClientBase):
    """StdIO MCP client with proper cross-task lifecycle management.
    
    在单一后台任务中运行整个生命周期，避免跨任务 cancel scope 错误。"""
    
    def __init__(self, name, command, args=None, env=None, cwd=None, ...):
        # 生命周期管理
        self._lifecycle_task: asyncio.Task | None = None
        self._reload_event = asyncio.Event()
        self._ready_event = asyncio.Event()
        self._stop_event = asyncio.Event()
        self.session: ClientSession | None = None
        self.is_connected = False
        self._cached_tools = None
    
    async def _run_lifecycle(self) -> None:
        """在专用后台任务中运行 MCP 客户端生命周期"""
        while not self._stop_event.is_set():
            try:
                async with AsyncExitStack() as stack:
                    # 在同一任务中进入上下文管理器
                    context = await stack.enter_async_context(
                        stdio_client(self.server_params),
                    )
                    self.session = ClientSession(read_stream, write_stream)
                    await stack.enter_async_context(self.session)
                    await self.session.initialize()
                    
                    self.is_connected = True
                    self._ready_event.set()
                    
                    # 等待 reload 或 stop 信号
                    while not self._reload_event.is_set() and not self._stop_event.is_set():
                        await asyncio.sleep(0.1)
                    
            except Exception as e:
                logger.error(f"Error in MCP client lifecycle: {e}")
                self.is_connected = False
                await asyncio.sleep(1)
    
    async def connect(self, timeout: float = 30.0) -> None:
        """连接 MCP 服务器"""
        if self.is_connected:
            raise RuntimeError(f"MCP client '{self.name}' is already connected.")
        
        self._stop_event.clear()
        self._lifecycle_task = asyncio.create_task(self._run_lifecycle())
        
        # 等待初始连接
        await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
    
    async def close(self, ignore_errors: bool = True) -> None:
        """关闭 MCP 客户端并清理资源"""
        if not self.is_connected:
            return
        
        self._stop_event.set()
        if self._lifecycle_task:
            await self._lifecycle_task
```

**HTTP 客户端实现** (`HttpStatefulClient` 类，第322-490行):

```python
class HttpStatefulClient(StatefulClientBase):
    """HTTP/SSE MCP client with proper cross-task lifecycle management."""
    
    async def _run_lifecycle(self) -> None:
        while not self._stop_event.is_set():
            async with AsyncExitStack() as stack:
                if self.transport == "streamable_http":
                    # 配置 httpx 客户端
                    http_client = httpx.AsyncClient(
                        headers=self.headers or {},
                        timeout=httpx.Timeout(
                            connect=timeout_seconds,
                            read=sse_read_timeout_seconds,
                            write=timeout_seconds,
                            pool=timeout_seconds,
                        ),
                    )
                    await stack.enter_async_context(http_client)
                    
                    context = await stack.enter_async_context(
                        streamable_http_client(url=self.url, http_client=http_client),
                    )
                else:  # SSE
                    context = await stack.enter_async_context(
                        sse_client(url=self.url, headers=self.headers, ...),
                    )
```

### 2.2 StdIOStatefulClient

标准输入输出模式的 MCP 客户端（用于本地进程）：

**源码路径**: `src/qwenpaw/app/mcp/stateful_client.py`

```python
class StdIOStatefulClient(StatefulClientBase):
    """stdio 传输的 MCP 客户端"""
    
    async def connect(self) -> None:
        """启动本地进程并建立连接"""
        
        # 1. 启动子进程
        self.process = await asyncio.create_subprocess_exec(
            self.command,
            *self.args,
            env={**os.environ, **self.env},
            cwd=self.cwd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        
        # 2. 创建 stdio 传输
        context = await stack.enter_async_context(
            stdio_client(stdin=self.process.stdin, stdout=self.process.stdout),
        )
        
        # 3. 创建 session
        self.session = await stack.enter_async_context(
            ClientSession(read_stream, write_stream)
        )
        await self.session.initialize()
        self.is_connected = True
```

### 2.3 传输方式对比

| 类型 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| HTTP | 远程 MCP 服务器 | 简单，跨平台 | 需要 HTTP 服务器 |
| stdio | 本地 MCP 进程 | 低延迟，无需网络 | 进程管理复杂 |

---

## 3. MCPClientManager

### 3.1 核心功能

```python
class MCPClientManager:
    """MCP 客户端生命周期管理器"""
    
    def __init__(self):
        self._clients: Dict[str, Any] = {}
        self._lock = asyncio.Lock()
    
    async def init_from_config(self, config: "MCPConfig") -> None:
        """从配置初始化所有客户端"""
        for key, client_config in config.clients.items():
            if not client_config.enabled:
                continue
            await self._add_client(key, client_config)
    
    async def get_clients(self) -> List[Any]:
        """获取所有活跃客户端"""
        async with self._lock:
            return [c for c in self._clients.values() if c is not None]
    
    async def replace_client(
        self,
        key: str,
        client_config: "MCPClientConfig",
        timeout: float = 60.0,
    ) -> None:
        """热重载：替换客户端"""
        # 1. 连接新客户端（锁外，可能慢）
        new_client = self._build_client(client_config)
        await asyncio.wait_for(new_client.connect(), timeout=timeout)
        
        # 2. 锁内替换
        async with self._lock:
            old_client = self._clients.get(key)
            self._clients[key] = new_client
        
        # 3. 关闭旧客户端
        if old_client:
            await old_client.close()
    
    async def close_all(self) -> None:
        """关闭所有客户端"""
        async with self._lock:
            clients = list(self._clients.values())
            self._clients.clear()
        
        for client in clients:
            if client:
                await client.close()
```

### 3.2 热重载机制

MCP 支持运行时更新配置而不中断服务：

```python
# 配置变更监听
class MCPConfigWatcher:
    """监控 MCP 配置变化"""
    
    async def watch(self, config_path: Path) -> None:
        """监听配置文件变化"""
        
        last_mtime = 0
        
        while True:
            try:
                current_mtime = config_path.stat().st_mtime
                
                if current_mtime > last_mtime:
                    last_mtime = current_mtime
                    
                    # 重新加载配置
                    new_config = load_mcp_config(config_path)
                    
                    # 热更新客户端
                    await self._hot_reload(new_config)
                
                await asyncio.sleep(5)  # 轮询间隔
                
            except asyncio.CancelledError:
                break
```

---

## 4. MCP 配置

### 4.1 配置模型

```python
class MCPClientConfig(BaseModel):
    """单个 MCP 客户端配置"""
    name: str
    enabled: bool = True
    transport: Literal["http", "stdio"]  # 传输方式
    url: Optional[str] = None            # HTTP 模式 URL
    headers: Optional[Dict[str, str]] = None  # HTTP 请求头
    command: Optional[str] = None         # stdio 模式命令
    args: List[str] = []                 # stdio 模式参数
    env: Dict[str, str] = {}             # stdio 模式环境变量
    cwd: Optional[str] = None             # stdio 模式工作目录

class MCPConfig(BaseModel):
    """MCP 全局配置"""
    clients: Dict[str, MCPClientConfig] = {}
```

### 4.2 配置文件

`~/.qwenpaw/config.json` 中的 MCP 配置：

```json
{
  "mcp": {
    "clients": {
      "filesystem": {
        "name": "filesystem",
        "enabled": true,
        "transport": "stdio",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/dir"],
        "cwd": "/tmp"
      },
      "github": {
        "name": "github",
        "enabled": true,
        "transport": "http",
        "url": "http://localhost:3000",
        "headers": {
          "Authorization": "Bearer ${GITHUB_TOKEN}"
        }
      }
    }
  }
}
```

### 4.3 环境变量注入

```python
# 配置中的 ${VAR} 会被自动替换为环境变量
{
  "headers": {
    "Authorization": "Bearer ${GITHUB_TOKEN}"
  }
}

# 等价于
{
  "headers": {
    "Authorization": "Bearer actual_token_value"
  }
}
```

---

## 5. MCP 规则文件

### 5.1 规则文件位置

```
~/.qwenpaw/plugins/<plugin_name>/mcp.json
```

### 5.2 规则文件格式

```json
{
  "mcp_servers": {
    "my_server": {
      "command": "python",
      "args": ["/path/to/server.py"],
      "env": {
        "API_KEY": "${API_KEY}"
      },
      "cwd": "/path/to"
    }
  }
}
```

---

## 6. MCP 工具注册

### 6.1 工具包集成

MCP 客户端连接到工具包：

```python
class Toolkit:
    """工具包"""
    
    async def register_mcp_client(
        self,
        client: Any,
        namesake_strategy: str = "skip",
    ) -> None:
        """注册 MCP 客户端的工具"""
        
        # 1. 获取客户端提供的工具列表
        tools = await client.list_tools()
        
        # 2. 注册每个工具
        for tool in tools:
            self.register_tool_function(
                tool.function,
                namesake_strategy=namesake_strategy,
            )
```

### 6.2 使用示例

```python
# 假设有一个 MCP 服务器提供 filesystem 工具
async def setup_mcp():
    # 1. 创建 MCP 客户端
    client = StdIOStatefulClient(
        name="filesystem",
        command="npx",
        args=["-y", "@modelcontextprotocol/server-filesystem", "/home/user"],
    )
    
    # 2. 连接到服务器
    await client.connect()
    
    # 3. 注册到工具包
    toolkit = Toolkit()
    await toolkit.register_mcp_client(client)
    
    # 4. 现在可以通过智能体调用这些工具
    # agent 可以调用 read_file, write_file 等工具
```

---

## 7. 常用 MCP 服务器

### 7.1 官方 MCP 服务器

| 服务器 | 功能 | 安装命令 |
|--------|------|---------|
| filesystem | 文件系统操作 | `npx -y @modelcontextprotocol/server-filesystem` |
| github | GitHub API | `npx -y @modelcontextprotocol/server-github` |
| slack | Slack 集成 | `npx -y @modelcontextprotocol/server-slack` |
| postgres | PostgreSQL | `npx -y @modelcontextprotocol/server-postgres` |
| sequential-thinking | 思维链 | `npx -y @modelcontextprotocol/server-sequential-thinking` |

### 7.2 社区 MCP 服务器

| 服务器 | 功能 | 仓库 |
|--------|------|------|
| Everything | 全能搜索 | [modelcontextprotocol/everything](https://github.com/modelcontextprotocol/servers/tree/main/src/everything) |
| Brave Search | 网页搜索 | [@modelcontextprotocol/server-brave-search](https://github.com/modelcontextprotocol/servers/tree/main/src/brave-search) |
| Google Maps | 地图服务 | [@modelcontextprotocol/server-google-maps](https://github.com/modelcontextprotocol/servers/tree/main/src/google-maps) |

---

## 8. 开发自定义 MCP 服务器

### 8.1 服务器模板

```python
#!/usr/bin/env python3
"""自定义 MCP 服务器示例"""

from mcp.server import Server
from mcp.types import Tool, TextContent
from pydantic import AnyUrl
import asyncio

# 创建服务器
server = Server("my-custom-server")

@server.list_tools()
async def list_tools() -> list[Tool]:
    """列出所有可用工具"""
    return [
        Tool(
            name="my_tool",
            description="这是一个自定义工具",
            inputSchema={
                "type": "object",
                "properties": {
                    "input": {"type": "string"}
                }
            }
        )
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    """执行工具调用"""
    if name == "my_tool":
        result = await my_tool_function(arguments.get("input"))
        return [TextContent(type="text", text=result)]
    raise ValueError(f"Unknown tool: {name}")

async def my_tool_function(input: str) -> str:
    """工具实现"""
    return f"处理结果: {input}"

# 运行服务器
if __name__ == "__main__":
    import sys
    asyncio.run(server.run())
```

### 8.2 在 QwenPaw 中使用

```json
{
  "mcp": {
    "clients": {
      "my_server": {
        "name": "my_server",
        "enabled": true,
        "transport": "stdio",
        "command": "python",
        "args": ["/path/to/my_server.py"]
      }
    }
  }
}
```

---

## 9. 故障排查

### 9.1 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `Connection refused` | MCP 服务器未启动 | 启动 MCP 服务器或检查 URL |
| `Timeout` | 连接超时 | 增加 timeout 值或检查网络 |
| `Tool not found` | 工具名拼写错误 | 使用正确的工具名 |
| `Permission denied` | 权限不足 | 检查文件权限或 sudo |

### 9.2 调试技巧

```python
import logging

# 启用 MCP 调试日志
logging.getLogger("qwenpaw.app.mcp").setLevel(logging.DEBUG)
logging.getLogger("mcp").setLevel(logging.DEBUG)
```

### 9.3 诊断命令

```bash
# 检查 MCP 客户端状态
qwenpaw mcp list

# 测试 MCP 连接
qwenpaw mcp test --client filesystem

# 查看 MCP 配置
qwenpaw mcp show --client github
```

---

## 10. 最佳实践

### 10.1 安全建议

1. **最小权限**: 只授予必要的文件/目录访问权限
2. **环境变量**: 使用环境变量而非硬编码敏感信息
3. **输入验证**: MCP 服务器应验证所有输入
4. **审计日志**: 记录工具调用以便审计

### 10.2 性能优化

| 问题 | 解决方案 |
|------|----------|
| 连接慢 | 使用 stdio 替代 HTTP |
| 超时 | 增加 timeout 配置 |
| 工具过多 | 按需加载，而非全部加载 |

---

## 11. 参考资料

- 源码路径：`src/qwenpaw/app/mcp/`
- MCP 官方文档：https://modelcontextprotocol.io/
- 官方服务器仓库：https://github.com/modelcontextprotocol/servers
