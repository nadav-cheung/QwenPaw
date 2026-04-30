# ACP 协议深度解析

## 概述

ACP（Agent Communication Protocol）是 QwenPaw 的智能体间通信协议，支持 Server 模式和 Tool 模式，实现智能体间的互操作性。通过 ACP，不同的 QwenPaw 实例可以相互通信，共享工具能力，构建分布式多智能体系统。

**核心特性：**
- HTTP/REST 通信，支持跨网络调用
- 统一的异常处理体系（ACPErrors）
- 权限挂起机制（SuspendedPermission），支持用户确认后继续
- 工具自动注册，其他智能体可发现可用工具

**源码路径：** `src/qwenpaw/agents/acp/`

---

## 1. ACP 核心组件

源码路径：`src/qwenpaw/agents/acp/core.py`

### 1.1 ACP 异常类

```python
# src/qwenpaw/agents/acp/core.py:16
class ACPErrors(Exception):
    def __init__(self, message: str, *, agent: Optional[str] = None):
        super().__init__(message)
        self.agent = agent  # 关联的智能体 ID

class ACPConfigurationError(ACPErrors): pass  # 配置错误
class ACPTransportError(ACPErrors): pass      # 传输错误（网络/连接）
class ACPProtocolError(ACPErrors): pass       # 协议错误（格式/版本）
class ACPSessionError(ACPErrors): pass        # 会话错误（超时/状态）
```

### 1.2 SuspendedPermission 数据类

当远程智能体请求执行敏感操作时，权限被挂起等待本地用户确认：

```python
# src/qwenpaw/agents/acp/core.py:30
@dataclass
class SuspendedPermission:
    payload: dict[str, Any]           # 请求的完整 payload
    options: list[dict[str, Any]]     # 用户可选的操作选项
    agent: str                         # 请求操作的智能体 ID
    tool_name: str                     # 目标工具名称
    tool_kind: str                     # 工具类型
    target: str | None = None          # 操作目标（如文件路径）
    action: str | None = None          # 具体操作（如 read/write）
    summary: str | None = None        # 操作摘要描述
    command: str | None = None        # 命令（用于 shell 类工具）
    paths: list[str] = field(default_factory=list)  # 涉及的文件路径
    requires_user_confirmation: bool = True  # 是否需要用户确认
```

---

## 2. ACP 服务端

源码路径：`src/qwenpaw/agents/acp/server.py`

### 2.1 QwenPawACPAgent 类

```python
# src/qwenpaw/agents/acp/server.py
class QwenPawACPAgent:
    """ACP 智能体封装，提供给其他智能体调用"""

    async def handle_request(self, request: ACPRequest) -> ACPResponse:
        """处理来自其他智能体的请求"""
```

### 2.2 run_qwenpaw_agent 函数

```python
# src/qwenpaw/agents/acp/server.py
async def run_qwenpaw_agent(
    agent_id: str,
    config: AgentConfig,
    *args,
    **kwargs,
) -> None:
    """启动 ACP 智能体服务器，暴露 HTTP 接口供其他智能体调用"""
```

### 2.3 Server 模式特点

| 特性 | 说明 |
|------|------|
| API 暴露 | 通过 HTTP 暴露 ACP 接口 |
| 会话管理 | 支持多会话并发 |
| 权限控制 | SuspendedPermission 机制 |
| 工具注册 | 自动注册可用工具 |

### 2.4 服务端初始化流程

```python
async def start_acp_server(agent_id: str, config: ACPConfig):
    """启动 ACP 服务端"""

    # 1. 创建 QwenPawACPAgent 实例
    agent = QwenPawACPAgent(agent_id=agent_id, config=config)

    # 2. 注册可用工具
    for tool in discover_tools():
        agent.register_tool(tool)

    # 3. 启动 HTTP 服务器
    await start_http_server(agent, port=config.port)

    # 4. 注册到服务发现（可选）
    await register_service(agent_id, config.address)
```

---

## 3. ACP 客户端

源码路径：`src/qwenpaw/agents/acp/client.py`

### 3.1 ACPService 类

```python
# src/qwenpaw/agents/acp/service.py
class ACPService:
    """ACP 服务客户端封装"""

    async def call_agent(
        self,
        agent_id: str,
        message: str,
        **kwargs,
    ) -> Any:
        """调用远程 ACP 智能体"""

    async def list_agents(self) -> list[str]:
        """列出可用的 ACP 智能体"""

    async def get_agent_tools(self, agent_id: str) -> list[ToolInfo]:
        """获取远程智能体可用工具列表"""
```

### 3.2 服务初始化

```python
# src/qwenpaw/agents/acp/service.py
async def init_acp_service(config: ACPConfig) -> ACPService:
    """初始化 ACP 服务客户端"""
    return ACPService(config=config)

async def get_acp_service() -> ACPService:
    """获取全局 ACP 服务单例"""

async def close_acp_service() -> None:
    """关闭 ACP 服务客户端，清理连接"""
```

---

## 4. ACP 模式

### 4.1 Server 模式 vs Tool 模式对比

| 维度 | Server 模式 | Tool 模式 |
|------|-------------|-----------|
| 角色 | 服务提供者 | 服务消费者 |
| 通信方向 | 被动接收请求 | 主动发起调用 |
| 典型用途 | 构建可被调用的助手 | 调用外部智能体能力 |
| 配置位置 | 被调用方 | 调用方 |
| 生命周期 | 长期运行 | 按需创建 |

### 4.2 Server 模式架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      远程智能体                              │
│  ┌─────────────┐                                           │
│  │ ACPService  │                                           │
│  └──────┬──────┘                                           │
└─────────┼───────────────────────────────────────────────────┘
          │ HTTP/REST
          │ call_agent(agent_id, message)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                   QwenPaw ACP Server                        │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │ QwenPawACPAgent │───▶│  Tool Registry  │               │
│  └────────┬────────┘    └─────────────────┘               │
│           │                                                │
│           ▼                                                │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │  Request        │───▶│  Permission     │               │
│  │  Handler        │    │  Checker        │               │
│  └────────┬────────┘    └─────────────────┘               │
│           │                                                │
│           ▼ (if permission suspended)                       │
│  ┌─────────────────┐                                       │
│  │ SuspendedPermission│ ──── 等待用户确认 ────▶ 执行      │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 Tool 模式架构图

```
┌─────────────────────────────────────────────────────────────┐
│                   QwenPaw 本地 Agent                        │
│  ┌─────────────┐                                           │
│  │ ReActAgent  │                                           │
│  └──────┬──────┘                                           │
│         │ Tool Call (acp_call_agent)                       │
└─────────┼───────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│  ACPService.call_agent()                                   │
│  ┌─────────────┐                                           │
│  │ HTTP Client │                                           │
│  └──────┬──────┘                                           │
└─────────┼───────────────────────────────────────────────────┘
          │ HTTP/REST
          ▼
┌─────────────────────────────────────────────────────────────┐
│                   远程 ACP 智能体                           │
│  ┌─────────────────┐                                       │
│  │ QwenPawACPAgent │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

### 4.4 消息格式

```python
# ACP 请求消息
class ACPRequest(BaseModel):
    id: str                    # 请求唯一 ID
    agent_id: str              # 目标智能体 ID
    message: str               # 发送给智能体的消息
    tools: list[str] | None   # 允许使用的工具（可选）
    timeout: float = 30.0      # 超时时间

# ACP 响应消息
class ACPResponse(BaseModel):
    id: str                    # 请求 ID
    status: str                # success | error | permission_required
    result: Any | None         # 执行结果
    error: str | None          # 错误信息
    suspended: SuspendedPermission | None  # 权限挂起信息
```

---

## 5. ACP 配置

源码路径：`src/qwenpaw/config/config.py`

### 5.1 ACPConfig 模型

```python
# src/qwenpaw/config/config.py
class ACPConfig(BaseModel):
    enabled: bool = False                        # 是否启用 ACP
    agents: Dict[str, ACPAgentConfig] = {}     # 各智能体的配置
```

### 5.2 ACPAgentConfig 模型

```python
# src/qwenpaw/config/config.py
class ACPAgentConfig(BaseModel):
    tool_parse_mode: str = "call_title"  # 工具解析模式
    # call_title: 只解析工具调用标题
    # update_detail: 解析更新详情
    # call_detail: 解析完整调用详情
```

### 5.3 配置示例

```yaml
# .qwenpaw/config.yaml
acp:
  enabled: true
  agents:
    assistant:
      tool_parse_mode: "call_detail"
    data-analyst:
      tool_parse_mode: "call_title"
```

---

## 6. 权限挂起机制

### 6.1 权限检查流程

```python
async def handle_tool_request(tool_request: ToolRequest):
    """处理工具调用请求"""

    # 1. 检查工具是否需要权限
    if not tool.requires_permission:
        return await tool.execute()

    # 2. 检查权限策略
    decision = await permission_checker.check(tool_request)

    if decision.allowed:
        return await tool.execute()
    elif decision.suspended:
        # 3. 权限挂起，等待用户确认
        return SuspendedPermission(...)
    else:
        raise ACPProtocolError("Permission denied")
```

### 6.2 用户确认处理

```python
async def handle_permission_response(
    suspended: SuspendedPermission,
    action: str,  # "approve" | "deny" | "modify"
    options: dict | None = None,
):
    """处理用户对挂起权限的响应"""

    if action == "approve":
        # 执行原请求
        return await tool.execute(suspended.payload)

    elif action == "modify":
        # 用户修改了参数
        modified_payload = options.get("payload")
        return await tool.execute(modified_payload)

    else:  # deny
        raise ACPSessionError("Permission denied by user")
```

---

## 7. 应用场景

### 场景 1: 多智能体协作

**问题：** 需要多个专业智能体协作完成复杂任务

**解决方案：**
```
用户: "帮我分析销售数据并生成报告"

├── 主智能体 (assistant)
│     ↓ 分解任务
├── 数据分析智能体 (data-analyst)
│     ↓ 返回分析结果
└── 报告生成智能体 (report-generator)
      ↓ 返回最终报告
```

### 场景 2: 外部专家咨询

**问题：** 当前智能体需要调用外部专业智能体获取知识

**解决方案：**
```python
# 配置远程专家智能体
acp:
  enabled: true
  agents:
    expert:
      address: "https://expert.example.com/acp"
      api_key: "xxx"

# 调用远程专家
result = await acp_service.call_agent(
    agent_id="expert",
    message="解释量子计算中的叠加态原理"
)
```

### 场景 3: 敏感操作二次确认

**问题：** 远程智能体请求执行敏感操作需要本地用户确认

**解决方案：**
```python
# 1. 远程请求触发权限挂起
response = await acp_service.call_agent("remote", "删除所有日志")

# 2. 返回权限挂起信息
if response.status == "permission_required":
    show_confirmation_dialog(response.suspended)

# 3. 用户确认后继续
await acp_service.submit_permission_response(
    suspended_id=response.suspended.id,
    action="approve"
)
```

---

## 8. 最佳实践

### 8.1 Server 模式最佳实践

| 实践 | 说明 |
|------|------|
| 限制工具暴露 | 只暴露必要的工具接口 |
| 超时设置 | 根据任务复杂度合理设置 timeout |
| 权限检查 | 敏感工具启用权限挂起 |
| 日志记录 | 记录所有远程调用请求 |

### 8.2 Tool 模式最佳实践

| 实践 | 说明 |
|------|------|
| 错误重试 | 网络错误时指数退避重试 |
| 超时处理 | 设置合理的超时时间 |
| 结果缓存 | 对不频繁变化的调用结果缓存 |
| 降级策略 | 远程不可用时使用本地备选 |

### 8.3 安全建议

```python
# 1. 使用 HTTPS 传输
acp:
  agents:
    remote:
      address: "https://secure.example.com/acp"

# 2. API 密钥认证
acp:
  agents:
    remote:
      api_key: "${ACP_API_KEY}"  # 环境变量

# 3. 限制可用工具
acp:
  agents:
    remote:
      allowed_tools: ["search", "calculator"]  # 只允许调用这些工具
```

---

## 9. 常见问题

### Q1: 远程智能体连接超时

**原因：**
- 目标服务未启动
- 网络不可达
- 防火墙阻止

**排查步骤：**
```python
# 1. 检查服务是否运行
ok, msg = await provider.check_connection(timeout=5)

# 2. 测试网络连通性
import httpx
response = await httpx.get("https://remote:8000/health")

# 3. 检查配置的地址和端口
print(agent_config.address)
```

### Q2: 权限挂起后无响应

**原因：**
- 用户未确认/拒绝
- 会话超时
- 响应通道中断

**解决方案：**
```python
# 1. 设置挂起超时
suspended.timeout = 300  # 5 分钟超时

# 2. 实现超时处理
if time.time() > suspended.created_at + suspended.timeout:
    raise ACPSessionError("Permission response timeout")

# 3. 取消挂起
await acp_service.cancel_suspended(suspended_id)
```

### Q3: 工具调用返回错误

**原因：**
- 工具不存在
- 参数格式错误
- 远程执行失败

**排查步骤：**
```python
# 1. 获取可用工具列表
tools = await acp_service.get_agent_tools(agent_id)
print([t.name for t in tools])

# 2. 检查工具参数
result = await acp_service.call_agent(
    agent_id,
    message=f"调用工具 {tool_name}，参数: {params}",
)

# 3. 查看详细错误
if result.status == "error":
    print(f"Error: {result.error}")
```

### Q4: 消息格式不兼容

**原因：**
- ACP 版本不一致
- 序列化格式差异

**解决方案：**
```python
# 确保版本兼容
acp:
  version: "1.0"  # 指定 ACP 版本

# 检查版本兼容性
if remote_version != local_version:
    logger.warning(f"Version mismatch: {remote_version} vs {local_version}")
```

---

## 10. 交叉引用

| 相关章节 | 关联内容 |
|----------|----------|
| [82-Provider系统深度解析](82-Provider系统深度解析.md) | ACP 服务发现和注册机制 |
| [87-插件系统深度解析](87-插件系统深度解析.md) | 插件可以扩展 ACP 工具 |
| [91-异常处理与恢复](91-异常处理与恢复.md) | ACP 异常处理和错误恢复 |

---

## 11. 总结

**核心要点：**

1. **协议架构：** Server 模式（被动接收）+ Tool 模式（主动调用）
2. **通信机制：** 基于 HTTP/REST 的同步请求-响应模式
3. **权限控制：** SuspendedPermission 支持敏感操作的用户确认
4. **异常体系：** 4 类异常（Configuration/Transport/Protocol/Session）便于问题定位
5. **配置管理：** ACPConfig 支持多智能体分别配置

**Server vs Tool 模式选择：**

| 场景 | 推荐模式 |
|------|----------|
| 构建被其他智能体调用的服务 | Server |
| 调用远程智能体获取能力 | Tool |
| 多智能体协作 | 两者结合 |

**最佳实践：**
- 生产环境使用 HTTPS 加密传输
- 敏感操作启用权限挂起机制
- 合理设置超时时间
- 实现错误重试和降级策略

---

## 12. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| ACP 异常类 | `src/qwenpaw/agents/acp/core.py:16` |
| SuspendedPermission | `src/qwenpaw/agents/acp/core.py:30` |
| QwenPawACPAgent | `src/qwenpaw/agents/acp/server.py` |
| ACPService | `src/qwenpaw/agents/acp/service.py` |
| ACP 客户端 | `src/qwenpaw/agents/acp/client.py` |
| ACP 配置 | `src/qwenpaw/config/config.py` |
