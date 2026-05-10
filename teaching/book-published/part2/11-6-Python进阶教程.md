# 11.6 Python 进阶教程

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 运用 Python 进阶特性（生成器、上下文管理器、元类） 2) 阅读 QwenPaw 源码中的高级 Python 模式 3) 理解 asyncio 异步编程模型 |
| **前置知识** | [06-Python基础教程](./06-Python基础教程.md) |
| **预计时长** | 90 分钟（阅读 60 分钟 + 练习 30 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `生成器` `上下文管理器` `asyncio` `dataclass` `Mixin` |

> **一句话概述**：基于 QwenPaw 源码实战讲解 Python 进阶特性，助你掌握项目中的高级编程模式。

## 概述

本教程是 `06-Python基础教程.md` 的进阶篇。所有示例均来自 QwenPaw 真实源码，按模块组织，帮助你在理解 Python 高级特性的同时深入项目架构。

**前置知识**：已完成基础教程，了解 Python 基本语法、类型提示和 async/await。

**学习目标**：
- 掌握装饰器、上下文管理器、魔术方法等高级语法
- 熟练使用 Pydantic 和 dataclass 进行数据建模
- 理解抽象基类（ABC）及其与 Protocol 的区别
- 理解生成器和异步迭代器的原理
- 掌握日志系统和模块懒加载的实现

---

## 目录

1. [装饰器 (Decorators)](#1-装饰器-decorators)
2. [上下文管理器 (Context Managers)](#2-上下文管理器-context-managers)
3. [Pydantic 数据模型](#3-pydantic-数据模型)
4. [dataclass 数据类](#4-dataclass-数据类)
5. [枚举类型 (Enum)](#5-枚举类型-enum)
6. [抽象基类 (ABC)](#6-抽象基类-abc)
7. [魔术方法 (Dunder Methods)](#7-魔术方法-dunder-methods)
8. [生成器与异步迭代](#8-生成器与异步迭代)
9. [日志系统 (Logging)](#9-日志系统-logging)
10. [模块系统与懒加载](#10-模块系统与懒加载)
11. [Python 最佳实践](#11-python-最佳实践)

---

## 1. 装饰器 (Decorators)

### 1.1 什么是装饰器

装饰器是 Python 中最强大的特性之一。它本质上是一个**接受函数并返回新函数的高阶函数**。在 Java 中没有直接等价物，最接近的是注解（Annotation）+ AOP。

```python
# 装饰器的基本结构
def my_decorator(func):
    def wrapper(*args, **kwargs):
        # 前置逻辑
        result = func(*args, **kwargs)
        # 后置逻辑
        return result
    return wrapper

@my_decorator  # 等价于: my_function = my_decorator(my_function)
def my_function():
    pass
```

**装饰器链**：

```python
@a
@b
@c
def my_function():
    pass
# 等价于: my_function = a(b(c(my_function)))
```

### 1.2 QwenPaw 中的内置装饰器

### @staticmethod — 静态方法

源码路径: `src/qwenpaw/constant.py:34-83`

```python
# src/qwenpaw/constant.py:34
class EnvVarLoader:
    @staticmethod
    def get_bool(env_var: str, default: bool = False) -> bool:
        """从环境变量读取布尔值"""
        value = os.environ.get(env_var, "").lower()
        if value in ("1", "true", "yes"):
            return True
        if value in ("0", "false", "no"):
            return False
        return default

    @staticmethod
    def get_float(
        env_var: str,
        default: float = 0.0,
        min_value: float | None = None,
        max_value: float | None = None,
        allow_inf: bool = False,
    ) -> float:
        """从环境变量读取浮点数，支持范围约束"""
        value = os.environ.get(env_var)
        if value is None:
            return default
        # ... 解析和验证逻辑
```

**Java 对比**：`@staticmethod` 等价于 Java 的 `static` 方法，不需要实例就能调用。

### @classmethod — 类方法

源码路径: `src/qwenpaw/app/routers/agents.py:62-87`

```python
# src/qwenpaw/app/routers/agents.py:62
class CreateAgentRequest(BaseModel):
    id: str | None = None
    name: str
    description: str = ""
    workspace_dir: str | None = None
    language: str = "en"
    skill_names: list[str] | None = None

    @field_validator("id", mode="before")
    @classmethod
    def sanitize_id(cls, value: str | None) -> str | None:
        """Strip whitespace from the custom ID."""
        if value is None:
            return None
        if isinstance(value, str):
            sanitized = sanitize_agent_id(value)
            return sanitized if sanitized else None
        return value
```

**关键点**：`cls` 参数是类本身（不是实例），用于创建工厂方法。

### @property — 属性访问器

源码路径: `src/qwenpaw/app/workspace/workspace.py:90-115`

```python
# src/qwenpaw/app/workspace/workspace.py:90
class Workspace:
    @property
    def workspace_dir(self) -> Path:
        """工作空间目录路径"""
        return self._workspace_dir

    @property
    def agent_config_path(self) -> Path:
        """智能体配置文件路径"""
        return self.workspace_dir / "agent.yaml"

    @property
    def skills_dir(self) -> Path:
        """技能目录路径"""
        return self.workspace_dir / "skills"

    @property
    def is_running(self) -> bool:
        """智能体是否正在运行"""
        return self._agent is not None
```

**Java 对比**：`@property` 等价于 Java 的 getter，但访问时不需要括号：

```python
ws = Workspace(...)
print(ws.workspace_dir)   # 像访问属性一样，不需要 ws.get_workspace_dir()
print(ws.is_running)       # 而不是 ws.is_running()
```

### 1.3 自定义装饰器模式

QwenPaw 虽然没有大量自定义装饰器，但这种模式在 Python 生态中极为常见：

```python
import functools
import asyncio
import time
from typing import TypeVar, Callable

T = TypeVar("T")

def retry(max_retries: int = 3, delay: float = 1.0):
    """带参数的装饰器工厂"""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)  # 保留原函数的元信息（名称、文档字符串等）
        async def wrapper(*args, **kwargs) -> T:
            last_error = None
            for attempt in range(max_retries):
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    last_error = e
                    if attempt < max_retries - 1:
                        await asyncio.sleep(delay * (2 ** attempt))  # 指数退避
            raise last_error
        return wrapper
    return decorator

# 使用
@retry(max_retries=3, delay=0.5)
async def call_llm(prompt: str) -> str:
    ...
```

### 1.4 装饰器使用场景

| 场景 | 示例 | 说明 |
|------|------|------|
| 日志记录 | `@log_calls` | 记录函数调用时间和参数 |
| 性能计时 | `@timed` | 测量函数执行时间 |
| 重试机制 | `@retry(max_retries=3)` | 失败时自动重试 |
| 缓存结果 | `@lru_cache` | 缓存函数返回值 |
| 权限校验 | `@requires_auth` | 检查用户权限 |
| 参数验证 | `@validate` | 验证函数参数 |

### 1.5 functools.wraps 的重要性

**不使用 @wraps**：

```python
def decorator(func):
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    wrapper.__name__ = "wrapper"  # 丢失原函数名
    wrapper.__doc__ = None         # 丢失原文档
    return wrapper

@decorator
def original():
    """This is original docstring"""
    pass

print(original.__name__)  # "wrapper" — 错误！
print(original.__doc__)   # None — 错误！
```

**使用 @wraps**：

```python
import functools

def decorator(func):
    @functools.wraps(func)  # 保留原函数元信息
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper

@decorator
def original():
    """This is original docstring"""
    pass

print(original.__name__)  # "original" — 正确！
print(original.__doc__)   # "This is original docstring" — 正确！
```

---

## 2. 上下文管理器 (Context Managers)

### 2.1 基本概念

上下文管理器用于**自动管理资源的获取和释放**。Java 中最接近的是 try-with-resources。

```python
# Python 的 with 语句
with open("file.txt") as f:    # 自动打开
    content = f.read()
# 离开 with 块后自动关闭文件

# Java 等价写法
# try (BufferedReader reader = new BufferedReader(new FileReader("file.txt"))) {
#     String content = reader.readLine();
# }
```

### 2.2 QwenPaw 中的异步上下文管理器

源码路径: `src/qwenpaw/app/_app.py:78-207`

```python
# src/qwenpaw/app/_app.py:78
class App:
    """QwenPaw 应用主类，实现了异步上下文管理器协议"""

    def __init__(self):
        self.runner: Runner | None = None
        self.multi_agent_manager: MultiAgentManager | None = None

    async def __aenter__(self):
        """进入上下文：初始化所有资源"""
        # src/qwenpaw/app/_app.py:194
        logger.info("Starting QwenPaw application...")
        # 初始化 MultiAgentManager、Runner、MCP 客户端等
        await self._initialize()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """退出上下文：清理所有资源"""
        # src/qwenpaw/app/_app.py:200
        logger.info("Shutting down QwenPaw application...")
        await self._cleanup()

# 使用方式
async with App() as app:
    # 在这个代码块中，app 已经完全初始化
    await app.run()
# 退出代码块后，__aexit__ 自动清理资源
```

**关键设计**：`__aenter__` + `__aexit__` 构成异步上下文管理器协议。无论代码块是否抛异常，`__aexit__` 都会被调用。

### 2.3 asyncio.Lock — 异步锁

源码路径: `src/qwenpaw/app/multi_agent_manager.py:34,70`

```python
# src/qwenpaw/app/multi_agent_manager.py:34
class MultiAgentManager:
    def __init__(self):
        self.agents: Dict[str, Workspace] = {}
        self._lock = asyncio.Lock()  # 异步锁（也是上下文管理器）

    async def get_agent(self, agent_id: str) -> Workspace:
        # 快速路径：无锁检查
        if agent_id in self.agents:
            return self.agents[agent_id]

        # src/qwenpaw/app/multi_agent_manager.py:70
        async with self._lock:  # 获取锁（如果锁被占用，会异步等待）
            # 双重检查锁定模式
            if agent_id in self.agents:
                return self.agents[agent_id]
            instance = Workspace(agent_id=agent_id)
            await instance.start()
            self.agents[agent_id] = instance
            return instance
```

**设计要点**：
- `asyncio.Lock()` 不是普通的 `threading.Lock()`，它不会阻塞事件循环
- `async with` 保证即使发生异常也会释放锁
- **双重检查锁定**：先无锁检查（快速路径），再加锁检查，避免不必要的锁竞争

### 2.4 自定义上下文管理器

**方式1：使用类（推荐用于复杂逻辑）**：

```python
class DatabaseConnection:
    async def __aenter__(self):
        self.conn = await create_connection()
        return self.conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.conn.close()
        # 返回 False 表示不吞掉异常，返回 True 表示异常已处理
        return False
```

**方式2：使用 contextlib（推荐用于简单逻辑）**：

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def get_db_connection():
    conn = await create_connection()
    try:
        yield conn  # yield 的值就是 as 后面的变量
    finally:
        await conn.close()

# 使用
async with get_db_connection() as conn:
    await conn.execute("SELECT 1")
```

### 2.5 同步上下文管理器

Python 也支持同步上下文管理器：

```python
class FileHandler:
    def __init__(self, filename: str):
        self.filename = filename

    def __enter__(self):
        self.file = open(self.filename)
        return self.file

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.file.close()
        return False

# 使用
with FileHandler("data.txt") as f:
    content = f.read()
```

---

## 3. Pydantic 数据模型

### 3.1 为什么用 Pydantic

Pydantic 是 Python 最流行的数据验证库。在 QwenPaw 中，几乎所有 API 请求/响应模型都使用 Pydantic。它提供：

- **运行时类型验证**：传入的 JSON 数据会自动验证和转换
- **序列化/反序列化**：自动与 JSON 互转
- **OpenAPI 文档**：FastAPI 自动从 Pydantic 模型生成 API 文档

**Java 对比**：Pydantic ≈ Jackson 注解 + Bean Validation + Lombok @Data 的合体。

### 3.2 基本用法 — 来自 QwenPaw 路由层

源码路径: `src/qwenpaw/app/routers/messages.py:12`

```python
# src/qwenpaw/app/routers/messages.py:40
from pydantic import BaseModel, ConfigDict, Field

class SendMessageRequest(BaseModel):
    """聊天消息请求模型"""
    model_config = ConfigDict(extra="forbid")  # 禁止传入未定义的字段

    content: str = Field(..., min_length=1, max_length=10000, description="消息内容")
    conversation_id: str | None = Field(default=None, description="会话ID")
    stream: bool = Field(default=False, description="是否流式响应")
```

**关键概念**：
- `Field(...)` — `...` 表示必填字段，`default=` 表示可选字段
- `ConfigDict(extra="forbid")` — 严格模式，防止传入多余字段
- 类型注解直接用于验证：`str | None` 表示可以传字符串或 null

### 3.3 字段验证器

源码路径: `src/qwenpaw/app/routers/agents.py:11`

```python
# src/qwenpaw/app/routers/agents.py:62
from pydantic import BaseModel, field_validator

class CreateAgentRequest(BaseModel):
    id: str | None = None
    name: str = Field(..., min_length=1, max_length=50)
    model: str = Field(default="qwen-plus")
    system_prompt: str | None = None
    description: str = ""
    workspace_dir: str | None = None
    language: str = "en"
    skill_names: list[str] | None = None

    @field_validator("id", mode="before")
    @classmethod
    def sanitize_id(cls, value: str | None) -> str | None:
        """Strip whitespace from the custom ID."""
        if value is None:
            return None
        if isinstance(value, str):
            sanitized = sanitize_agent_id(value)
            return sanitized if sanitized else None
        return value
```

### 3.4 Pydantic 在配置系统中的应用

源码路径: `src/qwenpaw/config/config.py:43`

```python
# src/qwenpaw/config/config.py:43
from pydantic import BaseModel, Field

class ModelSlotConfig(BaseModel):
    """Model slot configuration for LLM routing."""
    provider_id: str = Field(default="")
    model: str = Field(default="")
```

### 3.5 序列化与模型转换

```python
# Pydantic 模型常用操作
req = SendMessageRequest(content="Hello", stream=True)

# 序列化为字典
data = req.model_dump()
# {"content": "Hello", "conversation_id": None, "stream": True}

# 序列化为 JSON（排除 None 值）
json_str = req.model_dump_json(exclude_none=True)
# '{"content":"Hello","stream":true}'

# 从字典创建模型（会自动验证）
req2 = SendMessageRequest.model_validate({"content": "Hi", "stream": False})

# 从 JSON 字符串创建
req3 = SendMessageRequest.model_validate_json('{"content":"Hey"}')
```

### 3.6 嵌套模型

```python
from pydantic import BaseModel, Field

class Address(BaseModel):
    street: str
    city: str
    zip_code: str

class User(BaseModel):
    name: str
    email: str
    address: Address  # 嵌套模型

# 使用
user = User(
    name="Alice",
    email="alice@example.com",
    address={"street": "123 Main St", "city": "NYC", "zip_code": "10001"}
)
print(user.address.city)  # NYC
```

---

## 4. dataclass 数据类

### 4.1 基本概念

`dataclass` 是 Python 3.7+ 引入的语法糖，自动生成 `__init__`、`__repr__`、`__eq__` 等方法。

**Java 对比**：`dataclass` ≈ Java Record（Java 16+）或 Lombok @Value。

### 4.2 QwenPaw 中的 dataclass

### 任务追踪器

源码路径: `src/qwenpaw/app/runner/task_tracker.py:25-31`

```python
# src/qwenpaw/app/runner/task_tracker.py:25
from dataclasses import dataclass, field

@dataclass
class _RunState:
    """Per-run state (task, queues, buffer), guarded by tracker lock."""

    task: asyncio.Future
    queues: list[asyncio.Queue] = field(default_factory=list)
    buffer: list[str] = field(default_factory=list)
```

**注意**：
- `field(default_factory=...)` 用于可变默认值（不能直接写 `= time.time()`，否则所有实例共享同一个时间戳）
- `@dataclass` 内部可以混用 `@property`

### 守护进程命令

源码路径: `src/qwenpaw/app/runner/daemon_commands.py:12-51`

```python
# src/qwenpaw/app/runner/daemon_commands.py:12
from dataclasses import dataclass

@dataclass
class DaemonCommand:
    """守护进程命令基类"""
    command: str
    agent_id: str | None = None

@dataclass
class QueryCommand(DaemonCommand):
    """查询命令"""
    query: str = ""
    channel_name: str = "cli"
    conversation_id: str | None = None
```

### 统一队列消息

源码路径: `src/qwenpaw/app/channels/unified_queue_manager.py:25-41`

```python
# src/qwenpaw/app/channels/unified_queue_manager.py:41
from dataclasses import dataclass, field

@dataclass
class QueueState:
    """State for a single queue."""

    queue: asyncio.Queue
    consumer_task: asyncio.Task
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    processed_count: int = 0
```

### 4.3 dataclass vs Pydantic — 如何选择

| 场景 | 使用 dataclass | 使用 Pydantic |
|------|---------------|--------------|
| API 请求/响应 | | ✅ |
| 内部数据结构 | ✅ | |
| 需要序列化为 JSON | | ✅ |
| 需要数据验证 | | ✅ |
| 性能敏感 | ✅ | |
| 简单数据容器 | ✅ | |

**QwenPaw 的实践**：
- **Pydantic**：用于 API 层（routers）和配置文件（config），需要验证和序列化
- **dataclass**：用于内部数据传输（task tracker、channel messages），不需要复杂验证

### 4.4 dataclass 高级特性

```python
from dataclasses import dataclass, field

# 不可变的 dataclass
@dataclass(frozen=True)
class Config:
    """不可变配置"""
    name: str
    timeout: int = 30

# 后代比较（按字段顺序比较所有字段）
@dataclass(order=True)
class Version:
    major: int
    minor: int
    patch: int

# 自动添加 __slots__
@dataclass(slots=True)
class Point:
    x: float
    y: float
```

---

## 5. 枚举类型 (Enum)

### 5.1 基本概念

Python 的 `Enum` 类似 Java 的 `enum`，但更灵活。QwenPaw 使用 `str, Enum` 多继承实现"字符串枚举"，这样枚举值可以直接当作字符串使用。

### 5.2 QwenPaw 中的枚举

### 审批决策枚举

源码路径: `src/qwenpaw/security/tool_guard/approval.py:5-12`

```python
# src/qwenpaw/security/tool_guard/approval.py:12
class ApprovalDecision(str, Enum):
    """Possible approval outcomes for a guarded tool call."""

    APPROVED = "approved"
    DENIED = "denied"
    TIMEOUT = "timeout"

# 使用 — str 枚举可以直接比较字符串
decision = ApprovalDecision.APPROVED
if decision == "approved":  # ✅ 可以直接和字符串比较
    execute_tool()
```

### 威胁严重级别

源码路径: `src/qwenpaw/security/tool_guard/models.py:12-25`

```python
# src/qwenpaw/security/tool_guard/models.py:12
from enum import Enum

class GuardSeverity(str, Enum):
    """安全告警严重级别"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class GuardThreatCategory(str, Enum):
    """威胁类别"""
    CODE_INJECTION = "code_injection"
    DATA_EXFILTRATION = "data_exfiltration"
    RESOURCE_ABUSE = "resource_abuse"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    UNAUTHORIZED_ACCESS = "unauthorized_access"
```

### 下载任务状态

源码路径: `src/qwenpaw/local_models/download_manager.py:11-37`

```python
# src/qwenpaw/local_models/download_manager.py:11
from enum import Enum

class DownloadTaskStatus(str, Enum):
    """下载任务状态机"""
    PENDING = "pending"
    DOWNLOADING = "downloading"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class DownloadTaskMessageType(str, Enum):
    """下载进度消息类型"""
    PROGRESS = "progress"
    ERROR = "error"
    COMPLETE = "complete"
```

### 5.3 枚举最佳实践

```python
# ✅ 推荐：str + Enum（可序列化为 JSON）
class Status(str, Enum):
    ACTIVE = "active"

# ❌ 避免：纯 Enum（序列化时变成 Status.ACTIVE 而非 "active"）
class Status(Enum):
    ACTIVE = "active"

# ✅ 枚举迭代
for severity in GuardSeverity:
    print(f"{severity.name} = {severity.value}")

# ✅ 从字符串创建枚举
decision = ApprovalDecision("approved")  # 返回 ApprovalDecision.APPROVED

# ✅ 在 match 语句中使用（Python 3.10+）
match decision:
    case ApprovalDecision.APPROVED:
        execute()
    case ApprovalDecision.DENIED:
        reject()
    case _:
        defer()
```

### 5.4 IntEnum 和 Flag

```python
from enum import Enum, IntEnum, Flag, auto

# IntEnum — 可以用作字典键和 switch
class Priority(IntEnum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3

# Flag — 用于位掩码
class Permissions(Flag):
    READ = auto()
    WRITE = auto()
    EXECUTE = auto()

ADMIN = Permissions.READ | Permissions.WRITE | Permissions.EXECUTE
```

---

## 6. 抽象基类 (ABC)

### 6.1 基本概念

Python 的 `ABC`（Abstract Base Class）类似 Java 的 `abstract class` 或 `interface`。使用 `@abstractmethod` 标记的方法**必须**由子类实现。

### 6.2 QwenPaw 中的 ABC 模式

### 工具守卫基类

源码路径: `src/qwenpaw/security/tool_guard/guardians/__init__.py:11-34`

```python
# src/qwenpaw/security/tool_guard/guardians/__init__.py:11
from abc import ABC, abstractmethod

class BaseToolGuardian(ABC):
    """工具守卫抽象基类 — 定义所有守卫必须实现的接口"""

    @abstractmethod
    async def check_tool_call(
        self,
        tool_name: str,
        tool_args: dict,
        context: dict,
    ) -> "GuardResult":
        """检查工具调用是否安全

        Args:
            tool_name: 工具名称
            tool_args: 工具参数
            context: 调用上下文

        Returns:
            GuardResult: 检查结果（通过/拒绝/需修改）
        """
        ...

    @abstractmethod
    def get_guarded_tools(self) -> list[str]:
        """返回此守卫负责监控的工具列表"""
        ...
```

**设计要点**：
- `ABC` 使类成为抽象基类，**不能直接实例化**
- `@abstractmethod` 标记的方法必须被子类实现
- 方法体使用 `...`（Ellipsis）表示"这里没有默认实现"

### 聊天仓库基类

源码路径: `src/qwenpaw/app/runner/repo/base.py:5-20`

```python
# src/qwenpaw/app/runner/repo/base.py:5
from abc import ABC, abstractmethod
from pathlib import Path

class BaseChatRepository(ABC):
    """聊天记录存储抽象基类"""

    @abstractmethod
    async def save_message(self, conversation_id: str, message: dict) -> None:
        """保存一条消息"""
        ...

    @abstractmethod
    async def get_messages(
        self, conversation_id: str, limit: int = 50
    ) -> list[dict]:
        """获取会话的消息列表"""
        ...
```

### 技能扫描分析器基类

源码路径: `src/qwenpaw/security/skill_scanner/analyzers/__init__.py:11-57`

```python
# src/qwenpaw/security/skill_scanner/analyzers/__init__.py:11
from abc import ABC, abstractmethod

class BaseAnalyzer(ABC):
    """技能安全扫描分析器抽象基类"""

    @abstractmethod
    async def analyze(self, skill_path: Path) -> list["ThreatInfo"]:
        """分析技能目录中的安全威胁"""
        ...

    @abstractmethod
    def get_severity(self) -> "Severity":
        """返回此分析器的严重级别"""
        ...
```

### 6.3 ABC vs Protocol — 如何选择

```python
# 方式1：ABC（显式继承）
class MyGuardian(BaseToolGuardian):
    async def check_tool_call(self, tool_name, tool_args, context):
        return GuardResult(passed=True)

    def get_guarded_tools(self):
        return ["shell_exec"]

# 方式2：Protocol（结构化子类型，Python 3.8+）
from typing import Protocol

class ToolGuardian(Protocol):
    async def check_tool_call(self, tool_name: str, tool_args: dict, context: dict) -> "GuardResult": ...
    def get_guarded_tools(self) -> list[str]: ...

# 使用 Protocol 时不需要显式继承
class MyGuardian:  # 不需要写 (ToolGuardian)
    async def check_tool_call(self, tool_name, tool_args, context):
        return GuardResult(passed=True)
```

**QwenPaw 的选择**：使用 ABC，因为需要运行时检查（`isinstance`）和显式的"实现"关系。

### 6.4 ABC 的注册机制

ABC 允许在不继承的情况下注册类：

```python
from abc import ABC, abstractmethod

class Animal(ABC):
    @abstractmethod
    def speak(self) -> str:
        ...

# 不继承 Animal，但注册为"虚拟子类"
@Animal.register
class Dog:
    def speak(self) -> str:
        return "Woof!"

# isinstance 检查可以通过
print(isinstance(Dog(), Animal))  # True
```

---

## 7. 魔术方法 (Dunder Methods)

### 7.1 概述

魔术方法（Magic Methods / Dunder Methods）是以双下划线开头和结尾的特殊方法。它们让自定义类支持 Python 的内置操作。

### 7.2 QwenPaw 中使用的魔术方法

### `__init__` — 构造函数

几乎所有类都有。例如 `src/qwenpaw/app/runner/runner.py:131`：

```python
# src/qwenpaw/app/runner/runner.py:131
class Runner:
    def __init__(
        self,
        workspace: Workspace,
        *,
        channel_manager: Any | None = None,
        runner_config: dict | None = None,
    ):
        super().__init__()
        self.workspace = workspace
        self.channel_manager = channel_manager
        self.config = runner_config or {}
```

**注意**：`*` 后面的参数强制使用关键字参数调用：
```python
Runner(workspace, channel_manager=cm)  # ✅
Runner(workspace, cm)                   # ❌ TypeError
```

### `__repr__` — 调试字符串表示

源码路径: `src/qwenpaw/app/multi_agent_manager.py:517`

```python
# src/qwenpaw/app/multi_agent_manager.py:517
class MultiAgentManager:
    def __repr__(self) -> str:
        return f"MultiAgentManager(agents={list(self.agents.keys())})"

# 调试时输出
print(manager)  # MultiAgentManager(agents=['agent-1', 'agent-2'])
```

### `__aenter__` / `__aexit__` — 异步上下文管理器

源码路径: `src/qwenpaw/app/_app.py:194-200`

（见第2章上下文管理器部分）

### `__call__` — 可调用对象

源码路径: `src/qwenpaw/agents/hooks/bootstrap.py:42`

```python
# src/qwenpaw/agents/hooks/bootstrap.py:42
class BootstrapHook:
    """智能体启动钩子 — 实现了 __call__ 使其可以像函数一样调用"""

    async def __call__(
        self,
        agent,
        kwargs: dict[str, Any],
    ) -> dict[str, Any] | None:
        """Check and load BOOTSTRAP.md on first user interaction.

        Args:
            agent: The agent instance
            kwargs: Input arguments to the _reasoning method

        Returns:
            None (hook doesn't modify kwargs)
        """

# 使用
hook = BootstrapHook()
await hook(agent)  # 像调用函数一样调用对象
```

源码路径: `src/qwenpaw/token_usage/model_wrapper.py:61`

```python
# src/qwenpaw/token_usage/model_wrapper.py:61
class TokenCountingWrapper:
    """Token 计数包装器 — 包装 LLM 调用以统计 token 使用量"""

    async def __call__(
        self,
        messages: list[dict],
        **kwargs,
    ) -> Any:
        """拦截 LLM 调用，统计 token 消耗"""
        result = await self._inner_model(messages, **kwargs)
        self._record_usage(result.usage)
        return result
```

### `__getattr__` — 属性查找回退 / 懒加载

源码路径: `src/qwenpaw/app/channels/__init__.py:7`

```python
# src/qwenpaw/app/channels/__init__.py:7
def __getattr__(name: str):
    """模块级懒加载：首次访问时才导入"""
    if name == "ChannelManager":
        from .manager import ChannelManager
        return ChannelManager
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

源码路径: `src/qwenpaw/agents/__init__.py:24`

```python
# src/qwenpaw/agents/__init__.py:24
def __getattr__(name: str):
    """延迟导入智能体模块，避免循环依赖"""
    # ... 根据名称动态导入
```

**设计意图**：`__getattr__` 在模块级别使用时，可以实现懒加载，避免循环导入问题，同时减少启动时间。

### 7.3 常用魔术方法速查表

| 魔术方法 | 用途 | Java 等价 |
|---------|------|----------|
| `__init__` | 构造函数 | 构造器 |
| `__repr__` | 调试表示 | `toString()` |
| `__str__` | 用户友好表示 | `toString()` |
| `__call__` | 可调用对象 | 函数式接口 |
| `__getattr__` | 属性查找回退 | 动态代理 |
| `__aenter__/__aexit__` | 异步上下文管理 | AutoCloseable |
| `__eq__` | 相等比较 | `equals()` |
| `__hash__` | 哈希值 | `hashCode()` |
| `__contains__` | `in` 操作符 | `contains()` |
| `__len__` | `len()` | `size()` |
| `__getitem__` | `obj[key]` | `get()` |
| `__setitem__` | `obj[key] = value` | `put()` |
| `__delitem__` | `del obj[key]` | `remove()` |
| `__iter__` | 迭代器 | Iterable |
| `__next__` | 迭代器下一个 | Iterator.next() |
| `__aiter__/__anext__` | 异步迭代器 | 异步 Iterable |

### 7.4 实现自定义迭代器

```python
class Counter:
    """自定义迭代器示例"""
    def __init__(self, limit: int):
        self.limit = limit
        self.current = 0

    def __iter__(self):
        return self

    def __next__(self):
        if self.current >= self.limit:
            raise StopIteration
        result = self.current
        self.current += 1
        return result

# 使用
for i in Counter(5):
    print(i)  # 0, 1, 2, 3, 4
```

---

## 8. 生成器与异步迭代

### 8.1 基本生成器

生成器是 Python 中用于创建迭代器的简洁方式。使用 `yield` 关键字可以在函数暂停执行，而不是返回值后完全终止。

```python
def fibonacci(n):
    """生成器：使用 yield 逐个产生值"""
    a, b = 0, 1
    for _ in range(n):
        yield a    # 暂停执行，返回值
        a, b = b, a + b

# 生成器是惰性的：只在需要时计算
for num in fibonacci(10):
    print(num)

# 可以转为列表
list(fibonacci(10))  # [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
```

**生成器 vs 列表**：

| 特性 | 生成器 | 列表 |
|------|--------|------|
| 内存占用 | 惰性，按需计算 | 一次性加载 |
| 迭代次数 | 一次性，不可重置 | 可多次迭代 |
| 适用场景 | 大数据集、无界序列 | 小数据集、需要随机访问 |

### 8.2 QwenPaw 中的异步生成器 — 流式响应

源码路径: `src/qwenpaw/app/_app.py:148-186`

```python
# src/qwenpaw/app/_app.py:148
async def stream_query(self, request, *args, **kwargs):
    """流式查询 — 异步生成器逐个产生响应片段"""
    try:
        runner = self._get_runner()
        # async for 消费 runner 的异步生成器
        async for item in runner.stream_query(request, *args, **kwargs):
            yield item  # 将每个片段传递给上层
    except Exception as e:
        logger.error(f"Stream error: {e}")
        yield {
            "type": "error",
            "content": str(e),
        }
```

**关键概念**：
- `async def` + `yield` = 异步生成器
- `async for` = 消费异步生成器
- 这就是 LLM 流式响应（打字机效果）的核心实现

### 8.3 SSE (Server-Sent Events) 流

源码路径: `src/qwenpaw/app/routers/skills_stream.py:193-228`

```python
# src/qwenpaw/app/routers/skills_stream.py:210
async def stream_response(request, response):
    """SSE 流式响应端点"""
    try:
        async for chunk in response:
            # 处理每个数据块
            data = chunk.model_dump_json(exclude_none=True)
            yield f"data: {data}\n\n"  # SSE 格式要求
    except Exception as e:
        error_msg = json.dumps({"error": str(e)})
        yield f"data: {error_msg}\n\n"
```

**SSE 格式**：每条消息以 `data: ` 开头，以两个换行符结尾。浏览器端使用 `EventSource` API 消费。

### 8.4 异步迭代器协议

```python
# 自定义异步迭代器
class AsyncMessageStream:
    def __init__(self, queue: asyncio.Queue):
        self.queue = queue

    def __aiter__(self):
        return self

    async def __anext__(self):
        item = await self.queue.get()
        if item is None:  # 哨兵值，表示结束
            raise StopAsyncIteration
        return item

# 使用
async for message in AsyncMessageStream(queue):
    process(message)
```

### 8.5 生成器表达式

生成器表达式是列表推导式的惰性版本：

```python
# 列表推导式（立即计算）
squares = [x**2 for x in range(1000000)]  # 占用大量内存

# 生成器表达式（惰性计算）
squares_gen = (x**2 for x in range(1000000))  # 几乎不占内存
for sq in squares_gen:
    print(sq)
    if sq > 100:
        break
```

---

## 9. 日志系统 (Logging)

### 9.1 Python logging 模块

Python 标准库 `logging` 是生产级日志方案。QwenPaw 统一使用此模式。

### 9.2 QwenPaw 的日志模式

几乎所有模块都遵循相同模式：

```python
# 每个文件顶部的标准模式
import logging

logger = logging.getLogger(__name__)  # __name__ = 模块的完整路径
```

实际例子：

```python
# src/qwenpaw/app/auth.py:23-40
import logging
logger = logging.getLogger(__name__)

class AuthService:
    async def authenticate(self, token: str) -> User:
        logger.info(f"Authenticating token: {token[:8]}...")  # 注意不要完整记录 token
        try:
            user = await self._validate_token(token)
            logger.debug(f"User authenticated: {user.id}")
            return user
        except InvalidTokenError:
            logger.warning(f"Invalid token attempt from {request.client.host}")
            raise
        except Exception as e:
            logger.error(f"Authentication failed: {e}", exc_info=True)  # 记录完整堆栈
            raise
```

### 9.3 日志级别

```python
logger.debug("Detailed debug information")     # 仅开发时使用
logger.info("Normal operation information")     # 关键业务流程
logger.warning("Warning but not error")         # 可恢复的问题
logger.error("Error occurred", exc_info=True)   # 错误 + 堆栈跟踪
logger.critical("System critical failure")      # 严重错误
```

### 9.4 QwenPaw 的日志初始化

源码路径: `src/qwenpaw/app/_app.py:55`

```python
# src/qwenpaw/app/_app.py:55
logger = setup_logger(os.environ.get(LOG_LEVEL_ENV, "info"))

# 通过环境变量控制日志级别
# LOG_LEVEL=debug python -m qwenpaw  # 开发环境
# LOG_LEVEL=warning python -m qwenpaw  # 生产环境
```

### 9.5 日志最佳实践

```python
# ✅ 使用 f-string 格式化（Python 3.6+）
logger.info(f"Processing request {request_id}")

# ✅ 记录异常时使用 exc_info=True
try:
    risky_operation()
except Exception as e:
    logger.error(f"Operation failed: {e}", exc_info=True)

# ✅ 敏感信息脱敏
logger.info(f"Token: {token[:8]}***")
logger.info(f"API key: {key[:4]}****")

# ❌ 不要在日志中记录完整密码/token
logger.info(f"Password: {password}")  # 危险！

# ❌ 不要在循环中大量 debug 日志
for item in huge_list:
    logger.debug(f"Processing {item}")  # 可能导致性能问题

# ✅ 使用 isEnabledFor 检查避免不必要的字符串格式化
if logger.isEnabledFor(logging.DEBUG):
    logger.debug(f"Expensive computation: {expensive_func()}")
```

---

## 10. 模块系统与懒加载

### 10.1 Python 的模块系统

Python 的模块系统与 Java 的包系统不同：

```
# Java: 每个 .java 文件是一个类，包结构由目录定义
com/qwenpaw/app/Runner.java  →  package com.qwenpaw.app; class Runner { }

# Python: 每个 .py 文件是一个模块，目录 + __init__.py 是包
qwenpaw/app/runner/__init__.py  →  package qwenpaw.app.runner
qwenpaw/app/runner/runner.py    →  module qwenpaw.app.runner.runner
```

### 10.2 导入方式

```python
# 绝对导入（推荐）
from qwenpaw.app.runner import Runner
from qwenpaw.config.config import AppConfig

# 相对导入（包内部使用）
from .runner import Runner          # 同级模块
from ..config import AppConfig       # 上级目录的模块
from ...exceptions import AgentError # 上上级目录

# 导入模块而非具体名称
import qwenpaw.app.runner.runner as runner_mod
```

### 10.3 `__init__.py` 的作用

`__init__.py` 是包的初始化文件，它：
1. 标记目录为 Python 包
2. 控制包的公开 API（`__all__`）
3. 实现懒加载

### QwenPaw 的懒加载实现

源码路径: `src/qwenpaw/app/channels/__init__.py:7`

```python
# src/qwenpaw/app/channels/__init__.py
"""渠道模块 — 使用懒加载避免循环依赖"""

def __getattr__(name: str):
    """模块级 __getattr__：首次访问属性时才执行导入"""
    if name == "ChannelManager":
        from .manager import ChannelManager
        return ChannelManager
    if name == "UnifiedQueueManager":
        from .unified_queue_manager import UnifiedQueueManager
        return UnifiedQueueManager
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

# 使用方不需要知道懒加载的存在
from qwenpaw.app.channels import ChannelManager  # 首次访问时才真正导入
```

**为什么需要懒加载**：
- QwenPaw 模块间有复杂的依赖关系
- 直接导入可能导致循环依赖（A 导入 B，B 导入 A）
- 懒加载将导入推迟到实际使用时，打破循环

### 10.4 `__all__` — 控制公开 API

```python
# __init__.py
__all__ = ["Workspace", "MultiAgentManager", "Runner"]

from .workspace import Workspace
from .multi_agent_manager import MultiAgentManager
from .runner import Runner

# __all__ 控制 from package import * 的行为
# 也被文档工具用来确定公开 API
```

---

## 11. Python 最佳实践

### 11.1 项目结构最佳实践

```
QwenPaw/
├── src/qwenpaw/              # 使用 src layout（推荐）
│   ├── __init__.py           # 包初始化 + 版本号
│   ├── cli/                  # CLI 子包
│   │   ├── __init__.py
│   │   └── main.py
│   ├── app/                  # 应用子包
│   │   ├── __init__.py
│   │   ├── _app.py           # _ 前缀表示内部模块
│   │   └── runner/
│   ├── config/               # 配置子包
│   ├── security/             # 安全子包
│   └── ...
├── tests/                    # 测试目录（与 src 平级）
│   ├── conftest.py           # pytest 共享 fixtures
│   ├── test_runner.py
│   └── ...
├── pyproject.toml            # 项目配置（替代 setup.py）
└── Makefile                  # 常用命令快捷方式
```

### 11.2 命名规范

```python
# ✅ 模块名：小写 + 下划线
tool_guard.py, secret_store.py, multi_agent_manager.py

# ✅ 类名：PascalCase（大驼峰）
class MultiAgentManager, class BaseToolGuardian

# ✅ 函数/方法名：snake_case（小写下划线）
async def get_agent(), def check_tool_call()

# ✅ 常量名：全大写 + 下划线
MAX_RETRIES = 3, DEFAULT_TIMEOUT = 30.0

# ✅ 私有成员：单下划线前缀
self._lock, self._agent, def _initialize()

# ✅ 名称修饰（强私有）：双下划线前缀
self.__secret  # 会被改写为 _ClassName__secret
```

### 11.3 类型提示最佳实践

```python
# ✅ 公共 API 必须有类型提示
async def get_agent(self, agent_id: str) -> Workspace:
    ...

# ✅ 使用 Python 3.10+ 语法
def process(data: str | None) -> dict[str, Any]:  # 而非 Optional[str], Dict[str, Any]

# ✅ 使用 TYPE_CHECKING 避免循环导入
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .workspace import Workspace

class Manager:
    def get(self) -> "Workspace":  # 字符串前向引用
        ...

# ❌ 不要过度使用 Any
def process(data: Any) -> Any:  # 丢失了类型信息
    ...

# ✅ 使用 ParamSpec 和 Concatenate 保持函数签名
from typing import ParamSpec, Concatenate

P = ParamSpec("P")

def with_logging(func: Callable[P, T]) -> Callable[P, T]:
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> T:
        logger.info(f"Calling {func.__name__}")
        return func(*args, **kwargs)
    return wrapper
```

### 11.4 异步编程最佳实践

```python
# ✅ 使用 asyncio.Lock 保护共享状态
class Manager:
    def __init__(self):
        self._lock = asyncio.Lock()
        self._cache: dict = {}

    async def get(self, key: str):
        if key in self._cache:       # 快速路径：无锁检查
            return self._cache[key]
        async with self._lock:       # 慢路径：加锁
            if key in self._cache:   # 双重检查
                return self._cache[key]
            value = await self._load(key)
            self._cache[key] = value
            return value

# ✅ 使用 asyncio.gather 并发执行独立任务
results = await asyncio.gather(
    fetch_user(user_id),
    fetch_orders(user_id),
    fetch_settings(user_id),
)

# ✅ 使用 asyncio.timeout（Python 3.11+）替代 wait_for
async with asyncio.timeout(30.0):
    result = await slow_operation()

# ❌ 不要在 async 函数中使用 time.sleep（会阻塞事件循环）
async def bad():
    time.sleep(5)  # ❌ 阻塞整个程序 5 秒！
    await asyncio.sleep(5)  # ✅ 正确

# ❌ 不要忘记 await
async def bad():
    result = some_async_function()  # ❌ 返回协程对象，没有执行
    result = await some_async_function()  # ✅
```

### 11.5 错误处理最佳实践

```python
# ✅ 定义明确的异常层次
class QwenPawError(Exception):
    """所有自定义异常的基类"""

class AgentError(QwenPawError):
    """智能体相关错误"""

class ProviderError(AgentError):
    """提供商 API 调用错误"""

# ✅ 使用 finally 确保资源清理
async def process_with_cleanup():
    resource = await acquire()
    try:
        await process(resource)
    finally:
        await resource.release()  # 无论成功失败都清理

# ✅ 使用 contextlib.suppress 忽略已知异常
from contextlib import suppress

with suppress(FileNotFoundError):
    os.remove(temp_file)  # 文件不存在也不报错

# ❌ 不要使用裸 except
try:
    do_something()
except:  # ❌ 捕获所有异常，包括 KeyboardInterrupt
    pass

except Exception:  # ✅ 至少限定为 Exception
    pass
```

### 11.6 配置管理最佳实践

```python
# ✅ 使用 Pydantic 验证配置
from pydantic import BaseModel, Field

class DatabaseConfig(BaseModel):
    host: str = Field(default="localhost")
    port: int = Field(default=5432, ge=1, le=65535)
    name: str = Field(default="qwenpaw")

# ✅ 使用环境变量覆盖配置
import os

class AppConfig(BaseModel):
    debug: bool = Field(default=False)
    log_level: str = Field(default="info")

    @classmethod
    def from_env(cls) -> "AppConfig":
        return cls(
            debug=os.environ.get("DEBUG", "").lower() in ("1", "true"),
            log_level=os.environ.get("LOG_LEVEL", "info"),
        )

# ✅ 使用 pathlib 而非 os.path
from pathlib import Path

config_dir = Path.home() / ".qwenpaw"
config_file = config_dir / "config.yaml"
config_dir.mkdir(parents=True, exist_ok=True)  # 自动创建目录
```

### 11.7 测试最佳实践

```python
# ✅ 使用 pytest + pytest-asyncio
import pytest

@pytest.fixture
def mock_agent():
    """测试夹具：提供模拟智能体"""
    agent = Agent(name="test", model="mock")
    yield agent  # yield 而非 return，可以做清理
    agent.cleanup()

@pytest.mark.asyncio
async def test_agent_query(mock_agent):
    result = await mock_agent.query("Hello")
    assert result is not None
    assert "error" not in result

# ✅ 使用 parametrize 进行参数化测试
@pytest.mark.parametrize("input,expected", [
    ("hello", "HELLO"),
    ("World", "WORLD"),
    ("", ""),
])
def test_uppercase(input: str, expected: str):
    assert input.upper() == expected

# ✅ 测试异常
@pytest.mark.asyncio
async def test_invalid_token():
    with pytest.raises(InvalidTokenError):
        await auth_service.authenticate("invalid_token")
```

### 11.8 性能相关实践

```python
# ✅ 使用 slots 减少内存
class Point:
    __slots__ = ("x", "y")
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

# ✅ 使用 functools.lru_cache 缓存计算结果
from functools import lru_cache

@lru_cache(maxsize=128)
def get_config(key: str) -> str:
    """缓存配置读取结果"""
    return read_from_file(key)

# ✅ 使用 asyncio.to_thread 在线程池中运行阻塞 I/O
async def read_large_file(path: str) -> str:
    """在线程池中运行阻塞的文件读取"""
    return await asyncio.to_thread(Path(path).read_text)

# ❌ 不要在事件循环中做 CPU 密集计算
async def bad():
    result = heavy_computation()  # ❌ 阻塞事件循环
    result = await asyncio.to_thread(heavy_computation)  # ✅
```

---

## 附录：QwenPaw 模块与 Python 特性对照表

| Python 特性 | QwenPaw 模块 | 关键文件 |
|------------|-------------|---------|
| Pydantic 模型 | config, routers | `config/config.py`, `app/routers/*.py` |
| dataclass | runner, channels | `app/runner/task_tracker.py`, `app/channels/` |
| Enum 枚举 | security, models | `security/tool_guard/models.py`, `local_models/` |
| ABC 抽象基类 | security, repo | `security/tool_guard/guardians/`, `app/runner/repo/` |
| 异步上下文管理器 | app | `app/_app.py` |
| `__call__` | agents, hooks | `agents/hooks/bootstrap.py`, `token_usage/model_wrapper.py` |
| `__getattr__` 懒加载 | channels, agents | `app/channels/__init__.py`, `agents/__init__.py` |
| 异步生成器 | app, routers | `app/_app.py`, `app/routers/skills_stream.py` |
| asyncio.Lock | multi_agent_manager | `app/multi_agent_manager.py` |
| logging | 全局 | 每个模块 `logger = logging.getLogger(__name__)` |

---

## 总结

### 核心要点回顾

本教程涵盖了 Python 进阶特性的核心知识点：

| 序号 | 特性 | 关键价值 |
|------|------|---------|
| 1 | 装饰器 | 拦截和修改函数行为，类似 Java AOP |
| 2 | 上下文管理器 | 自动资源管理，类似 Java try-with-resources |
| 3 | Pydantic | 运行时类型验证，FastAPI 核心依赖 |
| 4 | dataclass | 简洁的数据类定义，类似 Java Record |
| 5 | Enum | 类型安全的常量定义 |
| 6 | ABC | 定义接口契约，强制子类实现 |
| 7 | 魔术方法 | 定制类的行为，支持 Python 协议 |
| 8 | 生成器 | 惰性迭代，内存高效 |
| 9 | 日志系统 | 结构化日志，生产环境必备 |
| 10 | 模块懒加载 | 解决循环依赖，优化启动时间 |

### 与 Java 概念对照

| Python | Java |
|--------|------|
| `@staticmethod` | `static` 方法 |
| `@classmethod` | 静态工厂方法 |
| `@property` | getter |
| `dataclass` | Java Record |
| Pydantic | Jackson + Bean Validation |
| ABC | abstract class / interface |
| `__enter__/__exit__` | AutoCloseable |
| async/await | CompletableFuture |
| `asyncio.Lock` | ReentrantLock |
| 装饰器 | 注解 + AOP |
| Generator | Iterator |

### 下一步学习

1. **[07-智能体核心架构.md](./07-智能体核心架构.md)** — 深入理解 QwenPaw 智能体设计
2. **[08-消息渠道系统.md](./08-消息渠道系统.md)** — 理解消息传递与并发处理
3. **[09-技能扩展系统.md](./09-技能扩展系统.md)** — 掌握技能系统的实现

### 实践建议

- 阅读 QwenPaw 源码时，注意观察每种特性在实际项目中的使用模式
- 尝试在本地修改某些模块，验证对代码的理解
- 参与 QwenPaw 的代码贡献，将本教程中的最佳实践应用到实际代码中

## 知识检查

1. `async with` 上下文管理器与普通 `with` 有什么区别？在 QwenPaw 中哪里用到了？
2. `@dataclass` 装饰器相比手动定义 `__init__` 有什么优势？
3. Mixin 模式在 QwenPaw 的 ToolGuardMixin 中是如何实现的？

## 延伸阅读

| 方向 | 章节 | 说明 |
|------|------|------|
| 核心架构 | [07-智能体核心架构](./07-智能体核心架构.md) | 理解智能体设计 |
| 记忆系统 | [12-记忆系统深入](./12-记忆系统深入.md) | 异步编程实战 |
| 下一章 | [07-智能体核心架构](./07-智能体核心架构.md) | 继续学习核心机制 |

