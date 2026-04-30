✅ 内容增强完成

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

### 🐍 来自 Java 的你

| Java | Python (QwenPaw) | 说明 |
|------|------------------|------|
| Java Agent (`java.lang.instrument`) | Agent 钩子系统 | 两者都可拦截运行时，但目的不同 |
| `premain()` / `agentmain()` | `pre_reasoning` / `post_reasoning` 钩子 | Java 在类加载/方法调用前拦截，QwenPaw 在 LLM 推理前后拦截 |
| `Instrumentation.retransformClasses()` | `register_instance_hook()` | Java 改写字节码，QwenPaw 注入异步函数 |
| 静态插桩（类加载时） | 动态插桩（运行时每次调用） | Java Agent 需要 JVM 启动参数，QwenPaw 在代码中直接注册 |
| `AgentBuilder` + `TypeStrategy` | 装饰器 `_wrap_with_hooks` | Java 用字节码库构建器，Python 用函数装饰器 |
| JVMTI / BCI 框架 | 函数式钩子 | Java 可用多种字节码框架，Python 用函数组合 |
| `JavaAgent` 做 ASM 字节码操作 | Python 钩子做 Prompt/响应处理 | Java 改写编译后字节码，Python 拦截运行时函数调用 |
| Servlet Filter / Spring AOP Aspect | `logging.Filter` 类 | 请求/响应链式拦截 |

**核心区别：** Java Agent 是 JVM 层面的二进制拦截（需要理解字节码），QwenPaw 钩子是 Python 层面的函数拦截（更轻量、纯 Python 实现）。

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

## 练习题

✅ 练习题设计完成

### 基础练习

1. **钩子类型识别**：说明 `pre_reasoning`、`post_reasoning`、`pre_acting`、`post_acting` 四种钩子的执行时机。

2. **钩子注册实验**：使用 `register_instance_hook()` 注册一个简单的 `pre_reasoning` 钩子，观察其执行时机。

3. **重入保护机制分析**：分析 `MemoryCompactionHook` 如何防止重复执行。

### 进阶练习

1. **计时钩子实现**：实现一个 `TimingHook` 类，在 `pre_reasoning` 时记录开始时间，在 `post_reasoning` 时计算并记录推理耗时。

### 实战练习

- **自定义日志钩子系统**：实现一个完整的 `DetailedLoggingHook`，能够记录每次推理的输入、输出类型和执行耗时，并将日志写入文件。结合 QwenPaw 的 `register_instance_hook` API 实现与 Agent 的集成。

---

## 如果你来自 Java

QwenPaw 的 Hook 系统与 Java 生态中的拦截器/过滤器模式高度相似，但设计更加轻量和函数式。

### 概念对应表

| Java 概念 | QwenPaw 概念 | 说明 |
|-----------|--------------|------|
| **Servlet Filter** | `logging.Filter` | 两者都可在请求处理链中插入预处理/后处理逻辑 |
| **AOP `@Before/@After`** | `pre_*` / `post_*` 钩子 | Java 通过注解声明切面，QwenPaw 通过函数注册 |
| **Spring AOP Aspect** | `Hook` 类 + `_wrap_with_hooks` | 核心都是装饰器/代理模式 |
| ** CDI Interceptor** | `register_instance_hook()` | Java 用注解+容器，QwenPaw 用显式 API |
| **Java Agent (java.lang.instrument)** | 钩子系统 | 两者都可在运行时拦截，但 Java Agent 拦截的是字节码 |

### 关键差异 1：注册机制

```java
// Java: 声明式 + 字节码增强
@Aspect
@Component
public class LoggingAspect {
    @Before("execution(* com.example.*.*(..))")
    public void before(JoinPoint jp) {
        System.out.println("Before: " + jp.getSignature());
    }
}
```

```python
# Python: 动态 API 注册
agent.register_instance_hook(
    hook_type="pre_reasoning",
    hook_name="my_hook",
    hook=my_hook_function,  # 普通 Python 函数
)
```

### 关键差异 2：执行方式

- **Java**: 同步字节码拦截，通过 JVM Instrumentation API 或 CGLIB/Spring AOP 代理
- **Python**: 异步函数装饰器，通过 `_wrap_with_hooks` 在运行时包装目标函数

```java
// Java: CGLIB 代理（运行时生成子类）
Enhancer enhancer = new Enhancer();
enhancer.setSuperclass(TargetClass.class);
enhancer.setCallback(new MethodInterceptor() {
    @Override
    public Object intercept(Object obj, Method m, Object[] args, MethodProxy proxy) {
        // 前置处理
        Object result = proxy.invokeSuper(obj, args);
        // 后置处理
        return result;
    }
});
```

```python
# Python: 装饰器包装（更简洁）
@_wrap_with_hooks
async def reasoning(self, *args, **kwargs):
    ...  # 原始逻辑
```

### 关键差异 3：拦截粒度

Java AOP 可以拦截任意方法调用（构造方法、静态方法、私有方法等），粒度极细。QwenPaw 钩子系统专注于 Agent 的关键生命周期节点（reasoning、acting、reply 等）。

### Spring Boot 健康检查对比

Java Spring Boot Actuator 提供 `/actuator/health` 端点：

```java
// Spring Boot: 响应式健康指标
@Component
public class ChannelHealthIndicator implements ReactiveHealthIndicator {
    @Override
    public Mono<Health> health() {
        return checkTelegramConnection()
            .map(connected -> Health.up()
                .withDetail("telegram", "connected")
                .build())
            .onErrorResume(e -> Mono.just(Health.down()
                .withDetail("error", e.getMessage())
                .build()));
    }
}
```

QwenPaw 的渠道健康检查对应设计：

```python
# QwenPaw: 异步健康检查 API
@router.get("/channels/{channel_name}/health")
async def get_channel_health(channel_name: str):
    channel_manager = await get_channel_manager()
    status = await channel_manager.health_check(channel_name)
    return {"channel": channel_name, "status": status}
```

### 内存管理钩子的 Java 类比

QwenPaw 的 `MemoryCompactionHook` 类似于 Java 中的缓存淘汰策略：

```java
// Java: Guava Cache 自动淘汰
LoadingCache<String, ChatHistory> cache = CacheBuilder.newBuilder()
    .maximumSize(1000)                              // 最大条目数
    .expireAfterWrite(10, TimeUnit.MINUTES)         // 写入后超时
    .removalListener(notification -> {
        // 淘汰时压缩旧条目
        archive(notification.getValue());
    })
    .build(key -> loadHistory(key));
```

QwenPaw 的内存压缩在上下文 token 接近窗口上限时触发，更像 LLM 特有的"上下文窗口管理"场景——Java 中没有直接类比。

### 装饰器模式对比

QwenPaw 的 `_wrap_with_hooks` 本质上是装饰器模式：

```python
# Python: 装饰器（更直观）
@_wrap_with_hooks
async def reasoning(self, *args, **kwargs):
    ...
```

```java
// Java: 代理模式（更底层）
@Configuration
@EnableAspectJAutoProxy
public class AopConfig {
    @Bean
    public Advisor timingAdvisor() {
        AspectJExpressionPointcut pointcut =
            new AspectJExpressionPointcut();
        pointcut.setExpression("execution(* *.reasoning(..))");
        return new DefaultPointcutAdvisor(
            pointcut, new TimingAdvice());
    }
}
```

**总结：** Java 用字节码操作实现 AOP（ASM、Javassist、CGLIB），强大但复杂；Python 用函数闭包和装饰器实现 Hook，更轻量但粒度较粗。
