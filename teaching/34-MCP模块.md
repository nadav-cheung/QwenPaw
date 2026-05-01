# MCP 模块 (Model Context Protocol)

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 理解 MCP 模块的路由和管理 2) 配置 MCP 客户端连接 3) 分析 MCP 工具的注册流程 |
| **前置知识** | [MCP系统](./13-MCP系统.md)、[智能体核心架构](./07-智能体核心架构.md) |
| **预计时长** | 30 分钟（阅读 20 + 练习 10） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `MCP` `工具注册` `路由` |

> **一句话概述**：MCP 模块通过 MCPClientManager 统一管理 StdIO 和 HTTP 两种传输模式的客户端，支持热更新、跨任务生命周期管理和工具自动注册到 Agent。

MCP 模块管理 MCP 客户端连接，支持热更新和多种传输协议。

### 🐍 来自 Java 的你

| Java SPI | Python MCP | 说明 |
|----------|------------|------|
| `ServiceLoader.load()` | `MCPClientManager` | 动态加载服务 |
| `META-INF/services/` 配置文件 | `config.yaml` 中的 mcp 配置 | 服务发现机制 |
| `XXService` 接口 | `StatefulClientBase` | 服务抽象基类 |
| `ServiceProvider` | `StdIOStatefulClient` / `HttpStatefulClient` | 具体实现 |
| 同步加载 | 异步 `asyncio` + 生命周期任务 | 并发模型 |
| 静态配置 | 热更新 `MCPConfigWatcher` | 配置变更处理 |
| `List<XXService>` | `get_clients()` / `get_client()` | 获取服务实例 |

**Java SPI 示例:**
```java
// META-INF/services/com.example.ToolPlugin
// com.example.impl.FileToolPlugin

ServiceLoader<ToolPlugin> loader = ServiceLoader.load(ToolPlugin.class);
for (ToolPlugin plugin : loader) {
    plugin.initialize();
}
```

**Python MCP 等效:**
```python
# 配置文件中定义
mcp:
  clients:
    - name: "filesystem"
      transport: "stdio"
      command: "npx"
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

# 代码中使用
manager = MCPClientManager()
await manager.init_from_config()
clients = manager.get_clients()
```

**关键区别:**
- Java SPI 是**编译时**服务发现，MCP 是**运行时**协议通信
- Java SPI 加载后常驻，MCP 支持热更新替换客户端
- Java SPI 返回实例，Python MCP 通过 `session.call_tool()` 远程调用
- Java SPI 是同步的，MCP 客户端运行在独立的 `asyncio` 生命周期任务中

---

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

---

## 附录：MCP 协议 2025 最新演进

### Streamable HTTP（2025.3 重大更新）

2025 年 3 月 26 日，MCP 协议引入 **Streamable HTTP** 传输层，取代原有的 HTTP + SSE：

| 特性 | HTTP + SSE（旧） | Streamable HTTP（新） |
|------|------------------|----------------------|
| 连接建立 | 需专用 `/sse` 端点 | 统一 `/mcp` 端点 |
| 流式响应 | 仅服务端推送 | 按需流式或标准 HTTP 响应 |
| 状态管理 | 无 session 机制 | 支持 session 会话恢复 |
| 重连能力 | 差 | `Last-Event-ID` 支持完整恢复 |
| 连接压力 | 长连接压力大 | 可复用 HTTP 请求 |

**为什么演进？** 原 SSE 方案存在：
- 连接不可恢复
- 服务端长连接压力大  
- 无统一端点管理

**官方 Python SDK (FastMCP) 示例：**

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("My Server", json_response=True)

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers"""
    return a + b

@mcp.resource("greeting://{name}")
def get_greeting(name: str) -> str:
    """Get a personalized greeting"""
    return f"Hello, {name}!"

@mcp.prompt()
def greet_user(name: str, style: str = "friendly") -> str:
    """Generate a greeting prompt"""
    return f"Write a {style} greeting for someone named {name}."

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
```

### 🐍 来自 Java 的你（Spring AI 版）

如果你熟悉 **Spring AI Alibaba** 的 MCP Server 实现，核心概念对照：

| Spring AI MCP | Python MCP SDK | 说明 |
|----------------|----------------|------|
| `@Tool` + `@Bean` | `@mcp.tool()` | 暴露工具方法 |
| `MethodToolCallbackProvider` | 自动注册 | 工具回调提供者 |
| `spring-ai-starter-mcp-server-webmvc` | `mcp.server.fastmcp.FastMCP` | Server 框架 |
| `@Service` 封装业务 | 普通 Python 函数 | 业务逻辑 |
| REST API (Spring Boot) | Streamable HTTP / stdio | 传输层 |
| `RestClient` 调外部 API | `httpx` / `aiohttp` | 外部服务调用 |

**Spring AI Java 示例：**

```java
@Service
public class WeatherService {
    @Tool(description = "Get weather forecast for a location")
    public String getWeather(
        @ToolParam(description = "Latitude") double lat,
        @ToolParam(description = "Longitude") double lon
    ) {
        // 调用外部天气 API
        return restClient.get().uri("https://api.weather.gov/...").retrieve().body();
    }
}

@SpringBootApplication
public class McpServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(McpServerApplication.class, args);
    }
    
    @Bean
    public ToolCallbackProvider weatherTools(WeatherService service) {
        return MethodToolCallbackProvider.builder()
            .toolObjects(service)
            .build();
    }
}
```

**关键区别：**
- Java 需要 `@ComponentScan` + `@Bean` 注入，Python 使用装饰器自动注册
- Java `@ToolParam` 显式声明参数，Python 类型注解自动推断
- Java 构建在 Spring Boot 之上，Python 是轻量级 asyncio 框架

---

## 知识检查

1. **StdIOStatefulClient 和 HttpStatefulClient 分别适用于什么场景？它们的传输协议有什么区别？**
2. **`_run_lifecycle()` 为什么需要在独立的 asyncio 任务中运行？直接在请求处理流程中运行会有什么问题？**
3. **`MCPConfigWatcher` 的热更新机制是如何检测配置变更的？**

## 练习题

### 选择题

1. **MCPClientManager 的热更新核心机制是？**
   - A. 文件监听器监控文件变化
   - B. 轮询 agent.json 的 mtime，通过哈希快速拒绝
   - C. WebSocket 长连接推送更新
   - D. 数据库变更通知

2. **Streamable HTTP 相比 SSE 的核心优势是？**
   - A. 更快的传输速度
   - B. 支持会话恢复和统一端点
   - C. 更好的压缩比
   - D. 更简单的实现

3. **QwenPaw 中 MCP 客户端生命周期运行在？**
   - A. FastAPI 主线程
   - B. uvicorn worker 进程
   - C. 独立的 asyncio 任务中
   - D. Redis 队列中

### 简答题

4. **描述 `replace_client()` 的热更新流程。**

5. **为什么 StdIOStatefulClient 需要 `_run_lifecycle()` 独立任务？**

6. **在 QwenPaw 中注册一个新的 MCP 客户端需要哪些步骤？**

### 答案

1. **B** - AgentConfigWatcher 通过轮询 mtime 检测变更，哈希快速拒绝无变更的配置
2. **B** - Streamable HTTP 引入 session 机制和统一端点，支持完整会话恢复
3. **C** - 客户端运行在 `_run_lifecycle()` 独立任务中，避免 anyio CancelScope 问题
4. 参考"设计亮点"中的 replace_client 流程
5. 因为 FastAPI/uvicorn 的 CancelScope 在不同任务间退出时会导致 CPU 泄漏
6. 1) 在 config 中添加 MCP 客户端配置；2) 调用 `manager.init_from_config()` 或 `manager.replace_client()`

---

**参考答案：**

1. **B** - AgentConfigWatcher 通过轮询 mtime 检测变更，哈希快速拒绝无变更的配置
2. **B** - Streamable HTTP 引入 session 机制和统一端点，支持完整会话恢复
3. **C** - 客户端运行在 `_run_lifecycle()` 独立任务中，避免 anyio CancelScope 问题

4. **replace_client() 热更新流程：**
   - 创建新客户端实例（新配置）
   - 启动新客户端（锁外，可能较慢）
   - 在锁内原子替换客户端列表中的旧实例
   - 优雅停止旧客户端

5. **为什么需要独立任务：**
   - FastAPI/uvicorn 使用 anyio 的 CancelScope
   - 当 CancelScope 在不同任务间退出时，会导致 CPU 泄漏
   - `_run_lifecycle()` 在独立任务中运行，通过 AsyncExitStack 管理完整生命周期

6. **注册 MCP 客户端步骤：**
   - 在 `config.yaml` 或 `agent.json` 的 mcp.clients 中添加配置
   - 配置包括：name, transport, command/args（stdio）或 url/headers（HTTP）
   - QwenPaw 启动时 MCPClientManager.init_from_config() 自动初始化
   - 或运行时通过 POST /mcp API 动态添加

---

## 延伸阅读

- [MCP系统](./13-MCP系统.md) — MCP 协议的核心概念与架构
- [插件系统](./18-插件系统.md) — MCP 与插件系统的集成方式
