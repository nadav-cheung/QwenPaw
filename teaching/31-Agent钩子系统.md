# Agent 钩子系统 (Hooks)

钩子系统允许在 Agent 的关键生命周期节点注入自定义逻辑，实现引导、上下文压缩等功能。

## 目录结构

```
src/qwenpaw/agents/hooks/
├── __init__.py          # 模块导出
├── bootstrap.py         # BootstrapHook 实现
└── memory_compaction.py # MemoryCompactionHook 实现
```

## 关键类和行号

| 类/函数 | 文件 | 行号 |
|---------|------|------|
| `BootstrapHook` | `hooks/bootstrap.py` | 20 |
| `MemoryCompactionHook` | `hooks/memory_compaction.py` | 27 |
| `build_bootstrap_guidance` | `agents/prompt.py` | 310 |
| `_register_hooks` | `agents/react_agent.py` | 428 |

## 钩子类型

### AgentHookTypes (基础钩子)

```python
AgentHookTypes = (
    str
    | Literal[
        "pre_reply",      # 回复前
        "post_reply",     # 回复后
        "pre_print",      # 打印前
        "post_print",     # 打印后
        "pre_observe",    # 观察前
        "post_observe",   # 观察后
    ]
)
```

### ReActAgentHookTypes (ReAct 代理专用)

```python
ReActAgentHookTypes = (
    AgentHookTypes
    | Literal[
        "pre_reasoning",   # 推理前 ← QwenPaw 使用
        "post_reasoning", # 推理后
        "pre_acting",     # 行动前
        "post_acting",    # 行动后
    ]
)
```

**QwenPaw 当前仅使用 `pre_reasoning` 钩子**

## 钩子注册

**文件**: `src/qwenpaw/agents/react_agent.py:428-456`

```python
def _register_hooks(self) -> None:
    """Register pre-reasoning and pre-acting hooks."""

    # Bootstrap hook - 检查首次交互
    bootstrap_hook = BootstrapHook(
        working_dir=working_dir,
        language=self._language,
    )
    self.register_instance_hook(
        hook_type="pre_reasoning",
        hook_name="bootstrap_hook",
        hook=bootstrap_hook.__call__,
    )

    # Memory compaction hook - 上下文满时自动压缩
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

## 钩子执行机制

### _wrap_with_hooks 装饰器

```python
# agentscope/agent/_agent_meta.py, 第 55-156 行
def _wrap_with_hooks(original_func: Callable) -> Callable:
    """Decorator wrapping original async function with pre- and post-hooks"""

    @wraps(original_func)
    async def async_wrapper(self: AgentBase, *args, **kwargs) -> Any:
        # === PRE-HOOKS 执行 ===
        pre_hooks = (
            list(getattr(self, f"_instance_pre_{func_name}_hooks").values()) +
            list(getattr(self.__class__, f"_class_pre_{func_name}_hooks").values())
        )
        for pre_hook in pre_hooks:
            modified_keywords = await _execute_async_or_sync_func(
                pre_hook, self, deepcopy(current_normalized_kwargs)
            )
            if modified_keywords is not None:
                current_normalized_kwargs = modified_keywords

        # === 原始函数执行 ===
        current_output = await original_func(self, *args, **kwargs)

        # === POST-HOOKS 执行 ===
        post_hooks = ...
        for post_hook in post_hooks:
            ...

        return current_output

    return async_wrapper
```

## BootstrapHook - 首次用户引导

**文件**: `src/qwenpaw/agents/hooks/bootstrap.py:20-107`

```python
class BootstrapHook:
    """Hook for bootstrap guidance on first user interaction."""

    async def __call__(
        self,
        agent,
        kwargs: dict[str, Any],
    ) -> dict[str, Any] | None:
        """Check and load BOOTSTRAP.md on first user interaction."""

        # 1. 检查是否已完成引导
        bootstrap_completed_flag = self.working_dir / ".bootstrap_completed"
        if bootstrap_completed_flag.exists():
            return None

        # 2. 检查 BOOTSTRAP.md 是否存在
        bootstrap_path = self.working_dir / "BOOTSTRAP.md"
        if not bootstrap_path.exists():
            return None

        # 3. 检查是否为首次用户交互
        messages = await agent.memory.get_memory()
        if not is_first_user_interaction(messages):
            return None

        # 4. 生成引导文本并前置到用户消息
        bootstrap_guidance = build_bootstrap_guidance(self.language)
        for msg in messages[system_prompt_count:]:
            if msg.role == "user":
                prepend_to_message_content(msg, bootstrap_guidance)
                break

        # 5. 创建完成标记
        bootstrap_completed_flag.touch()
```

**触发条件**：工作目录存在 `BOOTSTRAP.md` 且用户首次交互时。

## MemoryCompactionHook - 上下文压缩

**文件**: `src/qwenpaw/agents/hooks/memory_compaction.py:27-218`

```python
class MemoryCompactionHook:
    """Hook for automatic memory compaction when context is full."""

    _REENTRANCY_ATTR = "_memory_compact_hook_running"

    async def __call__(
        self,
        agent: ReActAgent,
        kwargs: dict[str, Any],
    ) -> dict[str, Any] | None:
        """Pre-reasoning hook to check and compact memory if needed."""

        # 1. 重入保护
        if getattr(agent, self._REENTRANCY_ATTR, False):
            return None
        setattr(agent, self._REENTRANCY_ATTR, True)

        try:
            # 2. 获取配置和 token 计数器
            agent_config = load_agent_config(self.memory_manager.agent_id)
            token_counter = get_token_counter(AgentConfig)

            # 3. 计算剩余压缩阈值
            left_compact_threshold = (
                running_config.memory_compact_threshold - str_token_count
            )

            # 4. 压缩工具结果
            trc = running_config.tool_result_compact
            if trc.enabled:
                await self.memory_manager.compact_tool_result(...)

            # 5. 检查是否需要压缩
            messages_to_compact, _, is_valid = await self.memory_manager.check_context(...)

            if not messages_to_compact:
                return None

            # 6. 执行压缩
            if running_config.context_compact.context_compact_enabled:
                compact_content = await self.memory_manager.compact_memory(...)
            else:
                compact_content = ""

            # 7. 标记消息为已压缩
            updated_count = await memory.mark_messages_compressed(messages_to_compact)
            await memory.update_compressed_summary(compact_content)

        finally:
            setattr(agent, self._REENTRANCY_ATTR, False)
```

**触发条件**：当消息 token 数超过 `memory_compact_threshold` 配置值时。

## 钩子函数签名规范

```python
# Pre-reasoning hook 签名
async def hook(
    self,                      # agent 实例
    kwargs: dict[str, Any],    # 归一化的参数
) -> dict[str, Any] | None:   # 返回修改后的 kwargs 或 None
    ...

# Post-reasoning hook 签名
async def hook(
    self,
    kwargs: dict[str, Any],
    output: Any,               # 原始输出
) -> Msg | None:              # 返回修改后的消息或 None
    ...
```

## 钩子调用顺序

1. **实例级钩子** (`_instance_pre_*_hooks`) 先于 **类级钩子** (`_class_pre_*_hooks`)
2. 同一级别的钩子按注册顺序执行
3. 后注册的同名钩子会覆盖先注册的

## 重要特性

- **重入保护**：通过 `_hook_running_{func_name}` 属性防止重复执行
- **内存压缩钩子专项保护**：额外的 `_memory_compact_hook_running` 属性
- **热重载配置**：每次执行时通过 `load_agent_config()` 重新加载配置

## 与其他模块的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    QwenPawAgent                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │         _register_hooks()                           │    │
│  │  ┌──────────────┐  ┌──────────────────────────┐    │    │
│  │  │BootstrapHook│  │MemoryCompactionHook      │    │    │
│  │  └──────┬───────┘  └────────────┬─────────────┘    │    │
│  └─────────┼──────────────────────┼──────────────────┘    │
│            │                      │                         │
│            ▼                      ▼                         │
│  ┌─────────────────┐    ┌──────────────────────┐          │
│  │  prompt.py       │    │  memory_manager       │          │
│  │  (引导文本生成)   │    │  (BaseMemoryManager)  │          │
│  └─────────────────┘    └──────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```
