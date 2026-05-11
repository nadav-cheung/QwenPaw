# 第 10 章：Agent 的身世——Mixin 与继承

```
卷一：追踪请求                    卷二：理解设计
[1] HTTP -> [2] Runner -> ... -> [8] 响应归途    [9] 源码地图
                                                  [10] Agent身世 <- you are here
```

上一章我们鸟瞰了源码全貌。这一章我们聚焦 `QwenPawAgent`——它为什么同时继承 `ToolGuardMixin` 和 `ReActAgent`？三层 `_reasoning()` 重写是怎么通过 MRO 串起来的？AgentConfig 有多少个字段？这些设计决策背后的权衡是什么？

---

## 问题

`QwenPawAgent(ToolGuardMixin, ReActAgent)` 这个类声明看起来很简单，但它隐含了一个复杂的继承体系。为什么不用组合？为什么用三层重写？配置系统是怎么支撑这么多可选项的？

## 术语其实很简单

> **术语：MRO（Method Resolution Order，方法解析顺序）**
> 想象你有多位长辈——遇到问题先问爸，爸不知道问妈，妈不知道问爷爷。MRO 就是 Python 的"问谁顺序"——调用 `self._reasoning()` 时，Python 按固定顺序在继承链上查找方法定义。

> **术语：AgentConfig（Agent 配置）**
> 想象一份详细的岗位说明书——职位名称、技能要求、工作地点、行为规范。AgentConfig 就是 Agent 的"岗位说明书"——一个 Pydantic 模型，定义了 Agent 的所有可配置项。

## 探索

### 三层 _reasoning() 的完整调用链

第 5 章我们提到过 MRO，这里深入看三层 `_reasoning()` 各自的职责：

```
self._reasoning()
  |
  v
QwenPawAgent._reasoning()          # 第三层（最外层）
  职责：媒体过滤
  - 如果模型不支持多模态，从消息中剥离图片/视频/音频
  - 如果模型报 400 错误（媒体不支持），自动剥离后重试
  - 自动继续：如果模型只返回文字没调工具，再给一次机会
  |
  -> super()._reasoning()
       |
       v
  ToolGuardMixin._reasoning()      # 第二层（中间层）
  职责：审批和重放
  - 检查是否有待重放的工具调用（用户刚批准了一个工具）
  - 如果有，构造合成的 tool_use 消息跳过 LLM 调用
  - 如果上次工具被拒绝，生成"等待审批"提示
  - 否则正常调用 LLM
  |
  -> super()._reasoning()
       |
       v
  ReActAgent._reasoning()          # 第一层（最底层，agentscope）
  职责：实际调用 LLM
  - 用 Formatter 格式化消息
  - 调用 model(messages, tools=..., tool_choice=...)
  - 返回包含 content blocks 的 Msg
```

每一层只做一件事，通过 `super()` 传递给下一层。这种设计让各层独立——改媒体过滤不影响安全检查，改安全检查不影响 LLM 调用。

### 媒体过滤——为什么不直接报错？

`QwenPawAgent._reasoning()` 的媒体过滤有两层防线：

**主动层**（调用 LLM 之前）：检查 `get_active_model_supports_multimodal()`。如果模型不支持多模态，从复制的消息中移除图片/视频/音频块。

**被动层**（LLM 报错后）：如果 LLM 返回 400 错误或媒体相关异常，尝试两种修复：
1. 在 Formatter 上设置 `_qwenpaw_force_strip_media` 标志，重试
2. 如果还不行，从记忆中彻底移除所有媒体块，重试

为什么这么复杂？因为有些模型声称支持多模态但实际不支持（"说支持但不真支持"），有些模型的能力探测结果可能过期。被动层是最后一道防线。

### ToolGuardMixin——两个重写方法

`ToolGuardMixin` 重写了两个方法，形成一个完整的安全拦截体系：

**`_acting()` 拦截**（第 7 章详细讲过）：在工具执行前做安全检查。三个决策分支：auto_denied（拒绝）、needs_approval（等审批）、放行。

**`_reasoning()` 拦截**：这是审批流程的另一半。当用户在 UI 上批准了一个工具调用时：
1. Runner 把批准信息注入 `_request_context`
2. `ToolGuardMixin._reasoning()` 检测到有等待重放的工具调用
3. 构造一个合成的 `tool_use` 消息（不调用 LLM），直接进入 `_acting()`
4. `_acting()` 检测到预审批令牌，跳过安全检查，直接执行工具

这个"拒绝-审批-重放"的闭环确保了安全：敏感操作被拦截 → 用户确认 → 安全执行。

### AgentConfig——30+ 个配置字段

`AgentProfileConfig`（定义在 `config/config.py`）是 Agent 的完整配置模型。关键字段：

```python
class AgentProfileConfig(BaseModel):
    id: str                          # Agent 唯一 ID
    name: str                        # 人类可读名称
    workspace_dir: str               # 工作区路径
    active_model: Optional[ModelSlotConfig]  # 覆盖模型
    language: str = "zh"             # 语言
    system_prompt_files: List[str]   # 提示词文件列表
    tools: Optional[ToolsConfig]     # 工具开关
    security: Optional[SecurityConfig]  # 安全配置
    running: AgentsRunningConfig     # 运行时参数
    channels: Optional[ChannelConfig]   # 通道配置
    mcp: Optional[MCPConfig]         # MCP 客户端配置
    heartbeat: Optional[HeartbeatConfig]  # 心跳调度
    ...
```

`running` 字段尤其丰富——包含 `max_iters`（ReAct 最大循环次数）、LLM 重试/退避参数、输入长度限制、记忆压缩阈值等。

### 配置的加载链

配置存储在两级文件中：

```
~/.qwenpaw/
  |-- config.json                    # 根配置（Agent 列表）
  +-- workspaces/default/
       |-- agent.json                # Agent 完整配置
       |-- agents/                   # 提示词文件
       |    |-- AGENTS.md
       |    |-- SOUL.md
       |    +-- PROFILE.md
       +-- skills/                   # 技能目录
```

`load_agent_config()` 的加载过程：
1. 从 `config.json` 读取 Agent 列表，找到 `workspace_dir`
2. 从 `<workspace_dir>/agent.json` 读取完整配置
3. 如果 `agent.json` 不存在，用根配置构建默认值并保存
4. 路径规范化：把旧的 `~/.copaw` 路径改成当前的 `~/.qwenpaw`

### 两个生命周期钩子

`_register_hooks()` 注册了两个 `pre_reasoning` 钩子——在每次推理前执行：

**BootstrapHook**：首次交互时检查 `BOOTSTRAP.md`。如果存在且 `.bootstrap_completed` 标志不存在，把引导内容注入第一条用户消息——告诉 Agent 阅读 `BOOTSTRAP.md`，欢迎用户，帮助定义身份。完成后创建 `.bootstrap_completed` 标志，防止重复触发。

**MemoryCompactionHook**：每次推理前检查上下文长度。如果超过阈值，自动压缩历史消息：
1. 先压缩工具结果（把长输出替换为摘要）
2. 如果还不够，压缩完整上下文（生成对话摘要）
3. 压缩后的摘要作为系统消息保留

这两个钩子都通过 `pre_reasoning` 事件注册，不需要修改 `ReActAgent` 的代码。

### rebuild_sys_prompt——运行时刷新提示词

`rebuild_sys_prompt()` 方法在 Session 恢复后被调用：

```python
def rebuild_sys_prompt(self):
    self._sys_prompt = self._build_sys_prompt()  # 重新读取文件
    # 更新记忆中的系统消息
    for msg in self.memory.content:
        if msg.role == "system":
            msg.content = self._sys_prompt
            break  # 只更新第一个系统消息
```

为什么需要这个？因为 Agent 是每次请求新建的（第 2 章），但 Session 恢复的是旧的记忆。如果用户在两次请求之间修改了 `SOUL.md`，新 Agent 需要读到最新的提示词——不能让旧提示词污染新的 Agent。

## 实验

追踪配置加载链：

1. 打开 `~/.qwenpaw/config.json`，看 `agents.profiles` 的结构
2. 打开 `~/.qwenpaw/workspaces/default/agent.json`，看完整配置
3. 在源码中打开 `src/qwenpaw/config/config.py`，搜索 `AgentProfileConfig`
4. 搜索 `load_agent_config`，追踪加载流程

预期结果：能看到 `config.json` 只存 workspace 路径，`agent.json` 存完整配置。

## 工程权衡

### 为什么用 Mixin 而非在 ReActAgent 里加 if？

如果把安全检查直接写在 `ReActAgent._acting()` 里，每次改安全策略都要改 agentscope 的代码。Mixin 让安全逻辑独立于推理循环——QwenPaw 的安全策略更新不需要碰 agentscope 的代码。代价是理解 MRO——开发者需要知道三层 `_reasoning()` 的调用顺序。

### 为什么 AgentConfig 有 30+ 个字段？

每个字段都对应一个真实的用户需求：`max_iters` 控制推理深度、`system_prompt_files` 控制提示词来源、`tools.builtin_tools` 控制工具开关、`running.llm_max_retries` 控制重试次数。字段多是因为可配置项多。用 Pydantic 模型定义配置保证了类型安全和自动验证。

### 为什么配置存 JSON 而非 YAML？

JSON 是 Python 标准库原生支持的格式，不需要额外依赖。YAML 更适合人类编写配置，但解析更复杂、容易出错（缩进敏感）。QwenPaw 的配置主要由程序生成和管理（通过 Web UI 或 CLI），用户很少手动编辑 JSON 文件。

## 常见误区

> **误区：Mixin 模式让代码难以调试？**
>
> 三层 `_reasoning()` 确实增加了理解成本。但 QwenPaw 在代码中有明确的 MRO 注释（`tool_guard_mixin.py` 第 76-93 行），警告任何 `_reasoning` 重写都必须调用 `super()`。而且三层各自有明确的单一职责，理解了职责划分后就不容易混淆。调试时在每一层的入口打一个断点，就能看清调用链。

> **误区：配置越多越好？**
>
> AgentConfig 有 30+ 个字段，但大部分有合理的默认值——用户不需要显式配置所有字段。QwenPaw 的设计是"约定优于配置"——默认值覆盖 80% 的使用场景，只有特殊需求才需要改配置。

## 动手环节

**任务**：在源码中追踪三层 `_reasoning()` 的完整调用链。

**步骤**：
1. 打开 `src/qwenpaw/agents/react_agent.py`，搜索 `def _reasoning`
2. 打开 `src/qwenpaw/agents/tool_guard_mixin.py`，搜索 `def _reasoning`
3. 在两个文件中搜索 `super()._reasoning()`，确认调用链
4. 打开 `src/qwenpaw/config/config.py`，搜索 `class AgentProfileConfig`

**预期输出**：
- `react_agent.py` 中的 `_reasoning` 处理媒体过滤
- `tool_guard_mixin.py` 中的 `_reasoning` 处理审批/重放
- 两处都调用 `super()._reasoning()`

**自检**：
- [ ] 理解了三层 `_reasoning()` 各自的职责
- [ ] 知道 MRO 决定了调用顺序：QwenPawAgent → ToolGuardMixin → ReActAgent
- [ ] 知道 `load_agent_config()` 从两个 JSON 文件加载配置

---

Agent 的身世——Mixin、MRO、Config——清楚了。下一章我们看 Provider 的棋局：为什么用抽象基类？20+ 个 Provider 是怎么管理的？策略模式在这里起了什么作用？
