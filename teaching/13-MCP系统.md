# MCP 系统 (Model Context Protocol)

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 解释 MCP 协议的通信模型 2) 配置和管理 MCP 客户端 3) 理解热重载和生命周期管理机制 4) 分析 StdIO 客户端的跨任务生命周期解决方案 |
| **前置知识** | [07-智能体核心架构](./07-智能体核心架构.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 45 分钟（阅读 25 分钟 + 练习 20 分钟） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `MCP` `StdIO` `热重载` `工具注册` |

> **一句话概述**：深入讲解 MCP 协议在 QwenPaw 中的实现，包括客户端管理、热重载和跨任务生命周期等核心机制。

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

**HTTP 客户端实现** (`HttpStatefulClient` 类，第322行；`_run_lifecycle` 第392-490行):

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

**源码路径**: `src/qwenpaw/app/mcp/manager.py`

MCP 支持运行时更新配置而不中断服务，采用"锁外连接，锁内替换"策略：

```python
class MCPClientManager:
    """MCP 客户端生命周期管理器"""

    def __init__(self) -> None:
        self._clients: Dict[str, Any] = {}
        self._lock = asyncio.Lock()

    async def replace_client(
        self,
        key: str,
        client_config: "MCPClientConfig",
        timeout: float = 60.0,
    ) -> None:
        """热重载：替换客户端

        流程: 连接新客户端(锁外) → 锁内交换并关闭旧客户端(锁内)
        """
        # 1. 在锁外创建并连接新客户端（可能耗时）
        new_client = self._build_client(client_config)
        await asyncio.wait_for(new_client.connect(), timeout=timeout)

        # 2. 在锁内交换并关闭旧客户端（最小化锁时间）
        async with self._lock:
            old_client = self._clients.get(key)
            self._clients[key] = new_client

        # 3. 关闭旧客户端（在锁外执行）
        if old_client is not None:
            await old_client.close()
```

**热重载流程图**:
```
配置文件变更 (config.json)
         │
         ▼
MCPConfigWatcher 检测到变更
         │
         ▼
调用 replace_client(key, new_config)
         │
         ├── 锁外: 创建新客户端
         │       └── new_client = _build_client(config)
         │       └── await new_client.connect()
         │
         └── 锁内: 原子替换
                 ├── old = _clients[key]
                 ├── _clients[key] = new_client
                 └── unlock
                         │
                         ▼
                 锁外: 关闭旧客户端
                         └── await old_client.close()
```

**与 ChannelManager 热重载对比**:

| 维度 | MCP 热重载 | Channel 热重载 |
|------|-----------|---------------|
| 锁机制 | `_lock` 内部锁 | `_restart_locks[channel_name]` per-channel 锁 |
| 替换策略 | 锁外连接，锁内替换 | 锁外启动，锁内交换 |
| 资源清理 | `await old_client.close()` | `await old_channel.stop()` |

### 3.3 生命周期管理

**构建客户端** (`_build_client` 方法，第230-266行):

```python
@staticmethod
def _build_client(client_config: "MCPClientConfig") -> Any:
    """根据传输类型构建 MCP 客户端实例"""
    rebuild_info = {
        "name": client_config.name,
        "transport": client_config.transport,
        "url": client_config.url,
        "headers": client_config.headers or None,
        "command": client_config.command,
        "args": list(client_config.args),
        "env": dict(client_config.env),
        "cwd": client_config.cwd or None,
    }

    if client_config.transport == "stdio":
        client = StdIOStatefulClient(
            name=client_config.name,
            command=client_config.command,
            args=client_config.args,
            env=client_config.env,
            cwd=client_config.cwd or None,
        )
        setattr(client, "_qwenpaw_rebuild_info", rebuild_info)
        return client

    # HTTP 客户端：展开环境变量 (第256-257行)
    headers = client_config.headers
    if headers:
        headers = {k: os.path.expandvars(v) for k, v in headers.items()}

    client = HttpStatefulClient(
        name=client_config.name,
        transport=client_config.transport,
        url=client_config.url,
        headers=headers or None,
    )
    setattr(client, "_qwenpaw_rebuild_info", rebuild_info)
    return client
```

**环境变量注入** (`_build_client` 第256-257行):

配置中的 `${VAR}` 格式的环境变量会在 HTTP 请求头中自动展开：

```python
headers = client_config.headers
if headers:
    headers = {k: os.path.expandvars(v) for k, v in headers.items()}
```

这使得配置可以安全引用环境变量而不暴露实际值：
```json
{
  "headers": {
    "Authorization": "Bearer ${GITHUB_TOKEN}"
  }
}
```

**强制清理** (`_force_cleanup_client` 方法，第190-228行):

```python
@staticmethod
async def _force_cleanup_client(client: Any) -> None:
    """强制关闭 connect() 被中断的客户端

    StatefulClientBase.close() 在 is_connected 仍为 False 时拒绝运行。
    我们直接关闭 AsyncExitStack 来触发 stdio_client 的 finally 块，
    发送 SIGTERM/SIGKILL 到子进程。
    """
    if client is None:
        return

    stack = getattr(client, "stack", None)
    if stack is None:
        return

    try:
        await stack.aclose()
    except Exception:
        logger.debug("Error during force-cleanup of MCP client", exc_info=True)
    finally:
        # 重置客户端状态
        for attr, default in (
            ("stack", None),
            ("session", None),
            ("is_connected", False),
        ):
            try:
                setattr(client, attr, default)
            except Exception:
                pass
```

**StdIOStatefulClient 生命周期** (`stateful_client.py` 第112-175行):

```python
async def _run_lifecycle(self) -> None:
    """在专用后台任务中运行 MCP 客户端生命周期"""
    while not self._stop_event.is_set():
        try:
            async with AsyncExitStack() as stack:
                # 在同一任务中进入上下文管理器，避免 cancel scope 错误
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
```

**关键设计**:
- **单一后台任务**: 整个生命周期在一个 `asyncio.Task` 中运行
- **AsyncExitStack**: 确保 `connect()` 和 `close()` 在同一任务中
- **_stop_event**: 优雅停止信号
- **_reload_event**: 配置重载信号

### 3.4 MCPConfigWatcher 配置监听

**源码路径**: `src/qwenpaw/app/mcp/watcher.py`

`MCPConfigWatcher` 是独立的配置监听器，使用轮询方式检测配置文件变化，实现客户端热重载：

```python
class MCPConfigWatcher:
    """Watch MCP configuration and hot-reload clients on changes."""

    def __init__(
        self,
        mcp_manager: MCPClientManager,
        config_loader: Callable,
        poll_interval: float = DEFAULT_POLL_INTERVAL,  # 默认 2.0 秒
        config_path: Optional[Path] = None,
    ):
        self._mcp_manager = mcp_manager
        self._config_loader = config_loader
        self._poll_interval = poll_interval
        self._config_path = config_path

        # 快照：用于快速比较
        self._last_mcp: Optional["MCPConfig"] = None
        self._last_mcp_hash: Optional[int] = None
        self._last_mtime: float = 0.0

        # 重试跟踪：防止无限重试
        self._client_failures: Dict[str, tuple[int, int]] = {}
        self._max_retries: int = 3

    async def start(self) -> None:
        """拍摄初始快照并启动轮询任务"""
        self._snapshot()
        self._task = asyncio.create_task(self._poll_loop(), name="mcp_config_watcher")

    async def stop(self) -> None:
        """停止轮询任务并等待进行中的重载完成"""
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass

        # 等待进行中的重载任务
        if self._reload_task and not self._reload_task.done():
            try:
                await asyncio.wait_for(self._reload_task, timeout=5.0)
            except asyncio.TimeoutError:
                self._reload_task.cancel()
```

**轮询检查机制** (`_poll_loop` + `_check`):

```python
async def _poll_loop(self) -> None:
    """主轮询循环"""
    while True:
        try:
            await asyncio.sleep(self._poll_interval)
            await self._check()
        except Exception:
            logger.exception("MCPConfigWatcher: poll iteration failed")

async def _check(self) -> None:
    """检查配置变化"""
    # 1. 检查 mtime 快速跳过
    if self._config_path:
        try:
            mtime = self._config_path.stat().st_mtime
        except FileNotFoundError:
            return
        if mtime == self._last_mtime:
            return
        self._last_mtime = mtime

    # 2. 加载新配置并快速比较 hash
    new_mcp = self._load_mcp_config()
    new_hash = self._mcp_hash(new_mcp)
    if new_hash == self._last_mcp_hash:
        return  # 无变化

    # 3. 检查是否已有进行中的重载
    if self._reload_task and not self._reload_task.done():
        logger.debug("Skipping reload, previous still in progress")
        return

    # 4. 在后台任务中触发重载
    self._reload_task = asyncio.create_task(
        self._reload_changed_clients_wrapper(new_mcp),
        name="mcp_reload_task",
    )
```

**重试跟踪机制** (`_reload_changed_clients_wrapper`):

```python
async def _reload_changed_clients_wrapper(self, new_mcp: "MCPConfig") -> None:
    """重载包装器：处理异常，只在成功时更新快照"""
    new_hash = self._mcp_hash(new_mcp)

    try:
        await self._reload_changed_clients(new_mcp)
        # 成功：更新快照
        self._last_mcp = new_mcp.model_copy(deep=True)
        self._last_mcp_hash = new_hash
    except Exception:
        logger.warning("MCPConfigWatcher: reload task failed")

def _should_skip_client(self, key: str, client_hash: int) -> bool:
    """检查客户端是否应因失败而跳过"""
    if key in self._client_failures:
        retry_count, last_hash = self._client_failures[key]
        if last_hash == client_hash and retry_count >= self._max_retries:
            return True
    return False

def _track_client_failure(self, key: str, client_hash: int) -> None:
    """跟踪客户端失败次数"""
    if key in self._client_failures:
        old_count, old_hash = self._client_failures[key]
        new_count = old_count + 1 if old_hash == client_hash else 1
    else:
        new_count = 1

    self._client_failures[key] = (new_count, client_hash)

    if new_count >= self._max_retries:
        logger.warning(f"Client '{key}' failed {new_count} times, giving up")
```

**配置变化处理** (`_reload_changed_clients`):

```python
async def _reload_changed_clients(self, new_mcp: "MCPConfig") -> None:
    """比较旧配置和新配置，重载变化的客户端"""
    old_mcp = self._last_mcp
    old_clients = old_mcp.clients if old_mcp else {}

    # 新增或变更的客户端
    for key, new_cfg in new_mcp.clients.items():
        old_cfg = old_clients.get(key)
        await self._handle_client_update(key, old_cfg, new_cfg)

    # 删除的客户端
    for key in old_clients:
        if key not in new_mcp.clients:
            await self._handle_client_removal(key)

async def _handle_client_update(self, key: str, old_cfg, new_cfg) -> None:
    """处理单个客户端更新"""
    # 客户端被禁用：移除
    if not new_cfg.enabled:
        if old_cfg and old_cfg.enabled:
            await self._mcp_manager.remove_client(key)
            self._client_failures.pop(key, None)
        return

    # 客户端配置变更：重载
    if old_cfg != new_cfg:
        await self._reload_single_client(key, new_cfg)

async def _reload_single_client(self, key: str, new_cfg) -> None:
    """重载单个客户端（带重试跟踪）"""
    client_hash = hash(str(new_cfg.model_dump(mode="json")))

    if self._should_skip_client(key, client_hash):
        return

    try:
        await self._mcp_manager.replace_client(key, new_cfg)
        self._client_failures.pop(key, None)
    except Exception:
        self._track_client_failure(key, client_hash)
```

**触发热重载**:
```
检测到配置文件 mtime 变更
         │
         ▼
load_mcp_config() 重新加载配置
         │
         ▼
遍历配置的客户端
         │
         ├── 新增 → _add_client()
         ├── 变更 → replace_client()
         └── 删除 → remove_client()
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

## 9. 如果你来自 Java...

### 9.1 MCP 对比 Java RPC 框架

| 特性 | MCP (Python/JS SDK) | Java RPC (gRPC/Thrift) |
|------|---------------------|------------------------|
| 设计目标 | LLM 工具/上下文交互 | 微服务间通信 |
| 协议格式 | JSON-RPC 2.0 | Protocol Buffers/Avro |
| 传输方式 | HTTP/SSE + stdio | HTTP/2 (gRPC) |
| 状态管理 | 有状态会话 | 无状态（通常） |
| 上下文传递 | 原生支持 | 需手动处理 |

### 9.2 MCP 的 Java 类比

| MCP 概念 | Java 类比 | 说明 |
|----------|-----------|------|
| MCP Server | gRPC Server | 暴露工具/资源的服务 |
| MCP Client | Stub/Proxy | 调用远程服务的客户端 |
| ClientSession | Channel | 有状态的会话连接 |
| Tool | RPC Method | 远程可调用方法 |
| Resource | DataSource | 可读取的数据 |

### 9.3 等价代码对比

**Java gRPC：**
```java
// Java - gRPC 服务定义
service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc ListUsers(Empty) returns (UserList);
}

public class UserServiceImpl extends UserServiceGrpc.UserServiceImplBase {
  @Override
  public void getUser(GetUserRequest req, StreamObserver<User> observer) {
    User user = userRepository.findById(req.getId());
    observer.onNext(user);
    observer.onCompleted();
  }
}
```

**等价 MCP（Python）：**
```python
# Python - MCP 服务器
from mcp.server import Server
from mcp.types import Tool

server = Server("user-service")

@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="get_user",
            description="获取用户信息",
            inputSchema={
                "type": "object",
                "properties": {
                    "user_id": {"type": "string"}
                }
            }
        )
    ]

@server.call_tool()
async def call_tool(name, arguments):
    if name == "get_user":
        user = user_repository.find_by_id(arguments["user_id"])
        return [TextContent(type="text", text=str(user))]
```

### 9.4 QwenPaw MCP 的特殊性

MCP 在 QwenPaw 中的定位**不是**微服务间通信，而是**LLM 与外部工具的桥梁**：

```
传统架构：
  Client → gRPC Server → Database
           (服务调用)

QwenPaw MCP 架构：
  LLM (大模型) → QwenPaw Agent → MCP Client → MCP Server → 外部工具/数据
                (智能体)        (客户端管理)  (协议端点)
```

### 9.5 与 Spring AI 的对比

Spring AI 是 Java 生态中类似 MCP 的框架：

| 特性 | Spring AI | QwenPaw MCP |
|------|-----------|-------------|
| 模型支持 | OpenAI、Anthropic、本地模型 | 同上 |
| 工具调用 | @Tool 注解 | MCP Tool |
| 上下文管理 | PromptTemplate | 内置 |
| 协议 | 专用 API | MCP 开放标准 |

```java
// Java - Spring AI 工具调用
public class MathService {
    @Tool(description = "计算器工具")
    public int calculate(@ToolParam("表达式") String expression) {
        return eval(expression);
    }
}
```

### 9.6 MCP 生态优势

MCP 相比传统 Java RPC 的优势：
1. **开放标准**：任何厂商可实现，不依赖特定云服务商
2. **工具生态**：npm/PyPI 上已有数千个 MCP 服务器
3. **LLM 原生**：专为 AI 模型设计，支持 prompts、资源、工具统一抽象
4. **热重载**：配置变更自动重连，无需重启服务

---

## 10. 故障排查

### 10.1 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `Connection refused` | MCP 服务器未启动 | 启动 MCP 服务器或检查 URL |
| `Timeout` | 连接超时 | 增加 timeout 值或检查网络 |
| `Tool not found` | 工具名拼写错误 | 使用正确的工具名 |
| `Permission denied` | 权限不足 | 检查文件权限或 sudo |

### 10.2 调试技巧

```python
import logging

# 启用 MCP 调试日志
logging.getLogger("qwenpaw.app.mcp").setLevel(logging.DEBUG)
logging.getLogger("mcp").setLevel(logging.DEBUG)
```

### 10.3 诊断命令

```bash
# MCP 客户端配置通过配置文件操作
# 编辑 ~/.qwenpaw/config.json 中的 mcp.clients 部分
# 或通过 API 端点管理
# GET  /api/config/mcp             查看 MCP 配置
# PUT  /api/config/mcp             更新 MCP 配置
# 配置变更后 MCPConfigWatcher 自动热重载
```

---

## 11. 应用场景

### 11.1 文件系统操作

通过 MCP 服务器实现安全的文件系统访问：
- **场景**: 文档处理、代码读取、日志分析
- **服务器**: `@modelcontextprotocol/server-filesystem`
- **优势**: 细粒度权限控制，限制访问目录范围

### 11.2 GitHub 集成

通过 MCP 服务器操作 GitHub：
- **场景**: Issue 管理、PR 审查、仓库分析
- **服务器**: `@modelcontextprotocol/server-github`
- **优势**: 无需配置 API Token，通过 MCP 协议安全访问

### 11.3 数据库连接

通过 MCP 连接 PostgreSQL、MySQL 等数据库：
- **场景**: 数据查询、报表生成、数据库管理
- **服务器**: `@modelcontextprotocol/server-postgres`
- **优势**: SQL 查询能力，结构化数据返回

---

## 12. 常见问题

### 12.1 连接问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `Connection refused` | MCP 服务器未启动 | 启动 MCP 服务器或检查 URL |
| `Timeout` | 连接超时 | 增加 timeout 配置或检查网络 |
| `stdio not found` | npx 命令不可用 | 安装 Node.js 或使用 Python MCP 服务器 |

### 12.2 工具调用问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `Tool not found` | 工具名拼写错误 | 使用正确的工具名 |
| `Permission denied` | 权限不足 | 检查 mcp.json 配置的权限 |
| 工具无响应 | 服务器崩溃 | 重启 MCP 服务器 |

### 12.3 调试方法

```bash
# 检查 MCP 配置（通过配置文件）
cat ~/.qwenpaw/config.json | grep -A 20 mcp

# 启用调试日志
export LOG_LEVEL=DEBUG
qwenpaw daemon logs | grep mcp
```

---

## 13. 最佳实践

### 13.1 安全建议

1. **最小权限**: 只授予必要的文件/目录访问权限
2. **环境变量**: 使用环境变量而非硬编码敏感信息
3. **输入验证**: MCP 服务器应验证所有输入参数
4. **定期更新**: 保持 MCP 服务器版本最新

### 13.2 性能优化

| 问题 | 解决方案 |
|------|----------|
| 连接慢 | 使用 stdio 替代 HTTP 本地连接 |
| 超时 | 增加 timeout 配置 (默认 30s) |
| 工具过多 | 按需加载，而非全部加载 |
| 重复连接 | 启用客户端重用，避免频繁建立连接 |

### 13.3 开发建议

1. **自定义服务器**: 使用 Python/Node.js SDK 开发专用 MCP 服务器
2. **测试驱动**: 先在本地测试 MCP 服务器，再集成到 QwenPaw
3. **版本兼容**: 确保 MCP 客户端与服务端版本兼容

---

## 14. 总结

### 核心要点

1. **MCP 协议**: 标准化 LLM 与外部工具交互的协议，支持 HTTP 和 stdio 两种传输方式
2. **MCPClientManager**: 统一的客户端生命周期管理，支持热重载
3. **HttpStatefulClient**: HTTP/SSE 传输模式，适合远程 MCP 服务器
4. **StdIOStatefulClient**: 标准输入输出传输模式，适合本地进程
5. **三层守卫**: FilePathToolGuardian + RuleBasedToolGuardian + ShellEvasionGuardian

### 关键配置

| 配置项 | 说明 |
|--------|------|
| `~/.qwenpaw/config.json` mcp.clients | MCP 客户端配置 |
| `~/.qwenpaw/plugins/<plugin>/mcp.json` | 插件 MCP 服务器配置 |
| 环境变量 `${VAR}` | 配置中自动替换为环境变量值 |

### 故障排查流程

```
MCP 工具无法调用
    │
    ├─► 检查客户端状态: 查看配置文件 mcp.clients 部分
    │
    ├─► 测试连接: 通过 API 端点或查看日志
    │
    ├─► 检查服务器日志: 查看 MCP 服务器进程输出
    │
    └─► 验证配置: 检查 transport、url/command 是否正确

热重载不生效
    │
    ├─► 检查配置文件 mtime: ls -la ~/.qwenpaw/config.json
    │
    └─► 重启 QwenPaw: 某些配置变更需要完全重启
```

---

## 15. 参考资料

- 源码路径：`src/qwenpaw/app/mcp/`
- MCP 官方文档：https://modelcontextprotocol.io/
- 官方服务器仓库：https://github.com/modelcontextprotocol/servers

---

## 16. 知识检查

### 题目一

StdIOStatefulClient 为什么将整个生命周期放在单一后台任务中运行？如果在 `connect()` 和 `close()` 中分别使用不同的 asyncio Task 会产生什么问题？

<details>
<summary>参考答案</summary>

原始 AgentScope 的 StatefulClientBase 在 `connect()` 中进入 AsyncExitStack，在 `close()` 中退出。在 uvicorn/FastAPI 环境中，这两个调用可能分别运行在不同的 asyncio Task 中（例如任务 A 处理请求时调用 connect，任务 B 处理后续请求时调用 close）。跨任务退出 AsyncExitStack 会触发 anyio.CancelScope 错误，导致资源泄漏。

StdIOStatefulClient 的 `_run_lifecycle` 方法在同一个后台 Task 中完成 connect 和 close，AsyncExitStack 的进入和退出始终在同一 Task 的 cancel scope 内，从根本上避免了这个问题。
</details>

### 题目二

MCPClientManager 的 `replace_client` 方法为什么采用"锁外连接，锁内替换"的策略？如果改为全程持锁会有什么后果？

<details>
<summary>参考答案</summary>

新客户端的 `connect()` 可能耗时较长（网络连接、进程启动等）。如果全程持锁，其他所有需要访问 `_clients` 字典的操作（如 `get_clients`、其他客户端的热重载）都会被阻塞，导致系统吞吐量下降。

"锁外连接，锁内替换"的策略让耗时的连接操作在锁外执行，只在交换引用时短暂持锁，将锁竞争降到最低。这与 ChannelManager 的热重载策略思路一致。
</details>

### 题目三

MCPConfigWatcher 使用了哪些优化手段来减少不必要的配置重载？

<details>
<summary>参考答案</summary>

1. **mtime 快速跳过**：先检查配置文件的修改时间（st_mtime），如果与上次相同则直接跳过，避免重新加载和解析配置文件。
2. **hash 快速比较**：即使 mtime 变了，也对配置内容计算 hash，如果 hash 与上次相同说明文件内容未实际变化（可能是 touch 等操作导致的 mtime 更新）。
3. **重载去重**：如果已有重载任务正在进行（`_reload_task` 未完成），跳过新的重载请求。
4. **失败重试限制**：对连续失败的客户端跟踪失败次数（最多 3 次），超过限制后不再重试，避免无限循环。
</details>

---

## 17. 延伸阅读

- [07-智能体核心架构](./07-智能体核心架构.md) -- 理解 MCP 在智能体工具调用链中的位置
- [18-插件系统](./18-插件系统.md) -- 了解插件如何通过 MCP 规则文件注册自定义服务器
- [09-技能扩展系统](./09-技能扩展系统.md) -- 技能系统中工具注册与 MCP 工具注册的对比
