# QwenPaw Agents/Hooks 系统研究报告

## 1. 概述

QwenPaw 的 Agent 钩子系统基于 AgentScope 框架实现，允许在 Agent 推理过程中的特定生命周期节点注入自定义逻辑。目前实现了两个内置钩子：

- **BootstrapHook**: 首次用户交互引导
- **MemoryCompactionHook**: 上下文窗口自动管理

---

## 2. 钩子类详解

### 2.1 BootstrapHook

**文件**: `/Users/nadav/IdeaProjects/QwenPaw/src/qwenpaw/agents/hooks/bootstrap.py`

**用途**: 在首次用户交互时检测并加载 `BOOTSTRAP.md` 文件，向用户展示初始化引导。

**核心逻辑**:

```python
class BootstrapHook:
    def __init__(self, working_dir: Path, language: str = "zh"):
        self.working_dir = working_dir
        self.language = language

    async def __call__(self, agent, kwargs: dict[str, Any]) -> dict[str, Any] | None:
```

**触发条件** (同时满足):
1. 工作目录存在 `BOOTSTRAP.md` 文件
2. 工作目录不存在 `.bootstrap_completed` 标记文件
3. `is_first_user_interaction(messages)` 返回 True（仅一条用户消息，无助手回复）

**对 Agent 行为的影响**:
- 在第一条用户消息前插入引导文本
- 引导文本内容由 `build_bootstrap_guidance(language)` 生成
- 创建 `.bootstrap_completed` 标记文件，防止重复触发

**引导文本示例** (中文):
```
# 引导模式

工作目录中存在 `BOOTSTRAP.md` — 首次设置。

1. 阅读 BOOTSTRAP.md，友好地表示初次见面，引导用户完成设置。
2. 按照 BOOTSTRAP.md 的指示，帮助用户定义你的身份和偏好。
3. 按指南创建/更新必要文件（PROFILE.md、MEMORY.md 等）。
4. 完成后删除 BOOTSTRAP.md。

如果用户希望跳过，直接回答下面的问题即可。
```

---

### 2.2 MemoryCompactionHook

**文件**: `/Users/nadav/IdeaProjects/QwenPaw/src/qwenpaw/agents/hooks/memory_compaction.py`

**用途**: 当上下文窗口接近上限时，自动对旧消息进行压缩摘要，保留系统提示和最近消息。

**核心属性**:

| 属性 | 说明 |
|------|------|
| `_REENTRANCY_ATTR = "_memory_compact_hook_running"` | 防重入标记，避免元类多重包装导致钩子重复执行 |

**核心逻辑**:

```python
class MemoryCompactionHook:
    def __init__(self, memory_manager: "BaseMemoryManager"):
        self.memory_manager = memory_manager

    async def __call__(self, agent: ReActAgent, kwargs: dict[str, Any]) -> dict[str, Any] | None:
```

**触发时机**: `pre_reasoning` 阶段（每次推理前检查）

**执行流程**:

1. **防重入检查**: 通过 `_memory_compact_hook_running` 属性防止重复执行
2. **获取配置**: 热加载 `agent_config.running` 获取运行参数
3. **计算令牌余量**:
   - `left_compact_threshold = memory_compact_threshold - (system_prompt + compressed_summary 的token数)`
4. **工具结果压缩** (可选):
   - 若 `tool_result_compact.enabled = True`，调用 `compact_tool_result()`
5. **检查上下文**: 调用 `memory_manager.check_context()` 确定需要压缩的消息
6. **执行压缩**:
   - 若 `context_compact.context_compact_enabled = True`，调用 `compact_memory()` 生成摘要
   - 发送状态消息: "🔄 Context compaction started..." → "✅ Context compaction completed"
7. **标记已压缩**: 调用 `memory.mark_messages_compressed()` 标记已压缩消息
8. **更新摘要**: 调用 `memory.update_compressed_summary()` 更新压缩摘要

**关键配置参数**:

| 参数 | 来源 | 默认值 | 说明 |
|------|------|--------|------|
| `memory_compact_threshold` | `max_input_length * memory_compact_ratio (0.75)` | 75% of max | 触发压缩的令牌阈值 |
| `memory_compact_reserve` | `max_input_length * memory_reserve_ratio (0.1)` | 10% of max | 压缩后保留的最近消息比例 |
| `context_compact_enabled` | `running_config` | `True` | 是否启用上下文压缩 |
| `memory_summary_enabled` | `running_config` | `True` | 是否在压缩时生成摘要 |
| `tool_result_compact.enabled` | `running_config` | `True` | 是否启用工具结果压缩 |

**内存结构布局**:
```
[System Prompt (保留)] + [待压缩消息] + [最近消息 (保留)]
```

---

## 3. 钩子调用时机

### 3.1 AgentScope 钩子系统架构

AgentScope 使用 **`_ReActAgentMeta`** 元类包装 `_reasoning` 和 `_acting` 方法，在其前后注入钩子逻辑。

**支持的钩子类型**:

| 类型 | 说明 |
|------|------|
| `pre_reasoning` | `_reasoning()` 调用前执行 |
| `post_reasoning` | `_reasoning()` 调用后执行 |
| `pre_acting` | `_acting()` 调用前执行 |
| `post_acting` | `_acting()` 调用后执行 |
| `pre_reply` | `reply()` 调用前执行 |
| `post_reply` | `reply()` 调用后执行 |
| `pre_print` | `print()` 调用前执行 |
| `post_print` | `print()` 调用后执行 |

### 3.2 钩子执行流程

```
用户消息 → reply() → _reasoning()
                      ↓
               ┌─────────────────────┐
               │  pre_reasoning hooks │  ← BootstrapHook, MemoryCompactionHook
               │  (可修改 kwargs)     │
               └─────────────────────┘
                      ↓
               ┌─────────────────────┐
               │  _reasoning()       │  ← Agent 核心推理
               │  (原方法执行)        │
               └─────────────────────┘
                      ↓
               ┌─────────────────────┐
               │  post_reasoning     │
               │  (可修改 output)     │
               └─────────────────────┘
                      ↓
               _acting()
                      ↓
               (工具执行、响应生成等)
```

### 3.3 QwenPaw 中的钩子注册

**位置**: `QwenPawAgent.__init__()` → `_register_hooks()`

```python
def _register_hooks(self) -> None:
    # Bootstrap hook - pre_reasoning
    bootstrap_hook = BootstrapHook(
        working_dir=working_dir,
        language=self._language,
    )
    self.register_instance_hook(
        hook_type="pre_reasoning",
        hook_name="bootstrap_hook",
        hook=bootstrap_hook.__call__,
    )

    # Memory compaction hook - pre_reasoning
    if self._enable_memory_manager and self.memory_manager is not None:
        memory_compact_hook = MemoryCompactionHook(
            memory_manager=self.memory_manager,
        )
        self.register_instance_hook(
            hook_type="pre_reasoning",
            hook_name="memory_compact_hook",
            hook=memory_compact_hook.__call__,
        )
```

---

## 4. 钩子如何影响 Agent 行为

### 4.1 BootstrapHook 的影响

| 影响维度 | 说明 |
|----------|------|
| **消息内容** | 在首条用户消息前插入引导文本 |
| **交互流程** | 引导用户完成 Agent 初始化设置 |
| **文件系统** | 创建 `.bootstrap_completed` 标记文件 |
| **副作用** | 读取 `BOOTSTRAP.md` 文件内容 |

### 4.2 MemoryCompactionHook 的影响

| 影响维度 | 说明 |
|----------|------|
| **上下文窗口** | 动态管理可用上下文空间 |
| **消息历史** | 将旧消息标记为已压缩，生成摘要替代 |
| **Token 消耗** | 降低单次请求的令牌数 |
| **用户体验** | 显示压缩进度状态 ("🔄 Context compaction started...") |
| **内存结构** | 保留系统提示 + 压缩摘要 + 最近消息 |

---

## 5. 如何自定义钩子

### 5.1 钩子接口规范

AgentScope 的钩子是可调用对象，签名为:

```python
async def my_hook(
    agent,                    # Agent 实例
    kwargs: dict[str, Any],   # 方法参数
) -> dict[str, Any] | None:
    """
    返回值:
    - None: 不修改参数
    - dict: 修改后的参数（将传递给下一个钩子和原方法）
    """
```

### 5.2 创建自定义钩子示例

```python
# my_custom_hook.py
from typing import Any

class MyCustomHook:
    """自定义钩子示例"""

    def __init__(self, some_config: str):
        self.some_config = some_config

    async def __call__(
        self,
        agent,
        kwargs: dict[str, Any],
    ) -> dict[str, Any] | None:
        # 在推理前执行自定义逻辑
        print(f"自定义钩子触发，配置: {self.some_config}")

        # 可选：修改 kwargs
        # kwargs["some_param"] = "modified"

        return None  # 或返回修改后的 kwargs
```

### 5.3 注册自定义钩子

**方式一：实例级别注册**（仅影响当前实例）

```python
agent = QwenPawAgent(...)
my_hook = MyCustomHook(some_config="value")
agent.register_instance_hook(
    hook_type="pre_reasoning",  # 或 "post_reasoning", "pre_acting", etc.
    hook_name="my_custom_hook",
    hook=my_hook.__call__,
)
```

**方式二：类级别注册**（影响所有实例）

```python
from agentscope.agent import ReActAgent

def class_level_hook(agent, kwargs):
    print("类级别钩子")
    return None

ReActAgent.register_class_hook(
    hook_type="pre_reasoning",
    hook_name="class_hook",
    hook=class_level_hook,
)
```

### 5.4 移除钩子

```python
# 移除实例钩子
agent.remove_instance_hook(
    hook_type="pre_reasoning",
    hook_name="my_custom_hook",
)

# 清除所有实例钩子
agent.clear_instance_hooks()

# 清除所有类级别钩子
ReActAgent.clear_class_hooks()
```

---

## 6. 完整文件清单

| 文件路径 | 说明 |
|----------|------|
| `/src/qwenpaw/agents/hooks/__init__.py` | 钩子包入口，导出 `BootstrapHook`, `MemoryCompactionHook` |
| `/src/qwenpaw/agents/hooks/bootstrap.py` | BootstrapHook 实现 |
| `/src/qwenpaw/agents/hooks/memory_compaction.py` | MemoryCompactionHook 实现 |
| `/src/qwenpaw/agents/react_agent.py` | QwenPawAgent，`_register_hooks()` 方法注册所有钩子 |
| `/src/qwenpaw/agents/utils/message_processing.py` | `is_first_user_interaction()`, `prepend_to_message_content()` |
| `/src/qwenpaw/agents/prompt.py` | `build_bootstrap_guidance()` |
| `/src/qwenpaw/config/config.py` | 内存压缩相关配置 (`RunningConfig`, `ContextCompactConfig` 等) |

---

## 7. 关键配置项参考

### 7.1 内存压缩配置 (RunningConfig)

```python
class ContextCompactConfig(BaseModel):
    context_compact_enabled: bool = True          # 是否启用压缩
    memory_compact_ratio: float = 0.75           # 触发阈值比例
    memory_reserve_ratio: float = 0.1            # 保留比例
    compact_with_thinking_block: bool = True     # 是否包含思考块

class ToolResultCompactConfig(BaseModel):
    enabled: bool = True
    recent_n: int = 2                            # 最近N条消息使用大阈值
    old_max_bytes: int = 3000                    # 旧消息最大字节数
    recent_max_bytes: int = 50000                # 最新消息最大字节数
    retention_days: int = 5
```

### 7.2 内存摘要配置 (MemorySummaryConfig)

```python
class MemorySummaryConfig(BaseModel):
    memory_summary_enabled: bool = True
    memory_prompt_enabled: bool = True
    force_memory_search: bool = False
    force_max_results: int = 5
    force_min_score: float = 0.1
    force_memory_search_timeout: int = 10
```

---

## 8. 总结

QwenPaw 的钩子系统充分利用了 AgentScope 的元类拦截机制，在不修改核心 Agent 类的情况下实现了：

1. **BootstrapHook**: 通过拦截 `pre_reasoning`，在首次交互时注入初始化引导
2. **MemoryCompactionHook**: 通过拦截 `pre_reasoning`，在每次推理前检查上下文是否需要压缩

两个钩子都是 **pre_reasoning** 类型，这意味着它们在 Agent 进行核心推理之前执行，有机会修改传递给推理过程的信息或执行清理/准备工作。

要添加新的钩子，只需：
1. 创建一个带有 `__call__` 方法的类
2. 实现所需的钩子逻辑
3. 调用 `agent.register_instance_hook()` 注册即可
