# 第 3 章：Agent 的诞生

```
Browser -> HTTP -> FastAPI -> Runner -> [Agent] -> Prompt -> ReAct -> LLM -> Tool -> Response
                                      ^
                                  you are here
```

上一章我们看到 `AgentRunner` 在每次请求时都会创建一个全新的 `QwenPawAgent`。这一章，我们走进这个"诞生"过程——一个 Agent 对象是怎么从无到有被创建出来的？它继承了谁？有哪些能力被"注入"了？工厂模式在这里起了什么作用？

---

## 问题

Agent 是什么？它不是一个文件、不是一个进程——它是一个 Python 对象。那这个对象是怎么被创建出来的？为什么它的类声明里有 `ToolGuardMixin`？18 个内置工具是怎么注册上去的？

## 术语其实很简单

> **术语：Agent（智能体）**
> 想象一个能听懂指令、会思考、能动手的助手。Agent 就是这样一个 Python 对象——它能接收消息、调用大模型"思考"、执行工具"行动"，然后把结果告诉你。

> **术语：类与实例（Class and Instance）**
> 想象饼干模具和饼干的关系。类（Class）是模具——定义了形状和配方。实例（Instance）是用模具压出来的饼干。`QwenPawAgent` 是模具，每次请求创建的那个对象是饼干。

> **术语：工厂模式（Factory Pattern）**
> 想象你去蛋糕店说"要一个巧克力蛋糕"——你不用关心蛋糕是怎么做的，厨房帮你搞定。工厂模式就是这种"你说要什么，我帮你造"的设计。`create_model_and_formatter()` 就是一个工厂函数——你说要用什么模型，它帮你创建好。

> **术语：Mixin（混入）**
> 想象给手机装壳——手机本身能打电话，装上保护壳就多了防摔能力。Mixin 就是这种"给类加能力"的技术——不改变继承关系，但混入新功能。`ToolGuardMixin` 就是给 Agent 混入了"安全检查"能力。

## 探索

### Agent 的"族谱"

打开 `src/qwenpaw/agents/react_agent.py`，找到类声明：

```python
class QwenPawAgent(ToolGuardMixin, ReActAgent):
    ...
```

Agent 的继承链是这样的：

```
QwenPawAgent          # QwenPaw 自己的 Agent，加了工具注册、记忆、技能
    |-- ToolGuardMixin # 安全拦截：在工具执行前检查是否安全
    +-- ReActAgent     # agentscope 的推理-行动循环（"思考->行动->观察->再思考"）
```

Python 的 MRO（方法解析顺序）决定了调用 `self._reasoning()` 时先找 `QwenPawAgent`，再找 `ToolGuardMixin`，最后找 `ReActAgent`。这意味着 `ToolGuardMixin` 可以在推理过程中插入安全检查——如果 Agent 想执行 `rm -rf /`，Mixin 会在 `ReActAgent` 真正执行之前拦住它。**MRO 的具体工作机制见第 5 章（ReAct 循环实操）和第 10 章（Mixin 设计原理）。现在先记住：ToolGuardMixin 夹在中间，能抢先拦截工具调用。**

### Agent 的诞生过程

`QwenPawAgent.__init__()` 是一个精心编排的初始化序列。用伪代码展示核心流程：

```python
def __init__(self, agent_config, env_context=None, mcp_clients=None, ...):
    # 1. 创建工具包，注册 18 个内置工具
    toolkit = self._create_toolkit()
    # 2. 加载工作目录下的技能（Skill）
    self._register_skills(toolkit)
    # 3. 拼装系统提示词
    sys_prompt = self._build_sys_prompt()
    # 4. 通过工厂函数创建 LLM 模型和格式化器
    model, formatter = create_model_and_formatter(agent_id=...)
    # 5. 调用父类初始化（ReActAgent）
    super().__init__(name="Friday", model=model, sys_prompt=sys_prompt,
                     toolkit=toolkit, ...)
    # 6. 设置记忆管理器
    self._setup_memory_manager(...)
    # 7. 注册钩子（首次引导、记忆压缩）
    self._register_hooks()
```

七步，每一步都在为 Agent 装配一种能力。让我们逐一看。

### 第 1 步：创建工具包

`_create_toolkit()` 创建一个 `Toolkit` 对象，然后根据配置注册 18 个内置工具。这些工具分为几类：

```
文件操作：read_file, write_file, edit_file
搜索：   grep_search, glob_search
Shell：  execute_shell_command
浏览器： browser_use, desktop_screenshot
多媒体： view_image, view_video, send_file_to_user
时间：   get_current_time, set_user_timezone
Agent：  delegate_external_agent, list_agents, chat_with_agent, ...
监控：   get_token_usage
```

不是所有工具都会被注册。`agent_config.tools.builtin_tools` 控制着哪些工具启用、哪些禁用。

### 第 2 步：加载技能

`_register_skills(toolkit)` 从工作目录的 `skills/` 文件夹加载用户自定义的技能。技能和工具的区别我们会在第 16 章详细讲。现在只需要知道：技能也被注册到 `Toolkit` 里，Agent 可以像调用内置工具一样调用它们。

### 第 3 步：拼装系统提示词

`_build_sys_prompt()` 从工作目录读取多个 Markdown 文件（`AGENTS.md`、`SOUL.md`、`PROFILE.md`），按顺序拼装成一段完整的系统提示词。第 4 章我们会深入这个过程。

### 第 4 步：创建 LLM 模型——工厂模式

`create_model_and_formatter()` 是一个工厂函数，负责创建 Agent 的"大脑"。它的流程（伪代码）：

```python
def create_model_and_formatter(agent_id=None):
    # 1. 加载配置，确定用哪个 Provider 和哪个模型
    provider_id, model_name = load_agent_config(agent_id).model_slot
    # 2. 从 Provider 获取原始模型实例
    raw_model = ProviderManager.get_provider(provider_id).get_chat_model_instance(model_name)
    # 3. 包装第一层：Token 用量记录
    wrapped = TokenRecordingModelWrapper(provider_id, raw_model)
    # 4. 包装第二层：重试和限流
    final_model = RetryChatModel(wrapped, retry_config=..., rate_limit_config=...)
    # 5. 创建格式化器
    formatter = _create_formatter_instance(raw_model.__class__)
    return final_model, formatter
```

模型被包装了两层，像套娃：

```
RetryChatModel                    # 最外层：自动重试 + 限流
  |-- TokenRecordingModelWrapper  # 第二层：记录用了多少 Token
       +-- RawModel               # 最内层：实际的 API 调用
```

每一层只做一件事——重试逻辑不关心 Token 统计，Token 统计不关心具体的 API 调用。组合起来就是完整的功能。

### 第 5 步：调用父类初始化

前四步准备好了"配料"，第 5 步把它们交给 `ReActAgent`（agentscope 的基类）：

```python
super().__init__(
    name="Friday",          # Agent 的名字
    model=model,            # 包装好的 LLM 模型
    sys_prompt=sys_prompt,  # 系统提示词
    toolkit=toolkit,        # 工具包
    memory=InMemoryMemory(),# 短期记忆
    max_iters=...,          # ReAct 循环最大迭代次数
)
```

`ReActAgent` 初始化之后，Agent 就具备了完整的"思考->行动->观察->再思考"循环能力。

### 第 6-7 步：记忆和钩子

`_setup_memory_manager()` 配置长期记忆——如果启用了，Agent 能"记住"跨会话的对话内容，还会注册一个 `memory_search` 工具让 Agent 主动搜索过去的记忆。

`_register_hooks()` 注册两个钩子：
- **BootstrapHook**：首次交互时检查 `BOOTSTRAP.md`，给 Agent 提供初始指导
- **MemoryCompactionHook**：对话太长时自动压缩记忆，避免超出模型的上下文窗口

## 实验

在源码中找到 Agent 创建的位置：

1. 打开 `src/qwenpaw/agents/react_agent.py`
2. 搜索 `class QwenPawAgent`
3. 搜索 `__init__` 方法，浏览初始化步骤
4. 搜索 `_create_toolkit` 方法，看看工具函数名列表

预期结果：能看到 `__init__` 按顺序调用了 `_create_toolkit` → `_register_skills` → `_build_sys_prompt` → `create_model_and_formatter` → `super().__init__` → `_setup_memory_manager` → `_register_hooks`。

## 工程权衡

### 为什么用工厂模式创建模型？

如果直接在 `__init__` 里写 `model = OpenAIChatModel(api_key=...)`，那换一个模型就要改 Agent 的代码。工厂模式把"创建模型"抽出来——Agent 只说"我要一个模型"，工厂根据配置决定给你 OpenAI 还是 Qwen 还是 Ollama。切换模型只需改配置，不用改代码。

### 为什么工具是注册的而不是硬编码的？

如果工具名直接写死在代码里，想加一个新工具就要改 `react_agent.py`。注册机制让工具列表变成可配置的——你可以在配置里禁用 `browser_use`，也可以通过 Skill 机制添加新工具。这种"注册表"模式在 QwenPaw 里到处都是（Provider、Channel、Skill 都用注册机制）。

## 常见误区

> **误区：Agent 是一个一直运行的进程？**
>
> 有人以为 Agent 是一个后台常驻的服务进程，不断监听消息。实际上 Agent 只是一个普通的 Python 对象——有属性（模型、工具包、记忆）、有方法（`reply()`、`interrupt()`）。它在每次请求时被创建，请求结束后被垃圾回收。状态的连续性靠 Session 文件维持，不靠进程常驻。

## 动手环节

**任务**：在源码中找到 Agent 的创建位置和工具列表。

**步骤**：
1. 在 IDE 中打开 `src/qwenpaw/agents/react_agent.py`
2. 搜索 `__init__` 方法
3. 搜索 `_create_toolkit` 方法，数一数有多少个工具函数名
4. 搜索 `create_model_and_formatter`，看工厂函数的调用方式

**预期输出**：
- `__init__` 中能看到七步初始化序列
- `_create_toolkit` 中能看到 18 个工具函数的字典
- `create_model_and_formatter` 的调用能看到 `agent_id` 参数

**自检**：
- [ ] 找到了 `QwenPawAgent(ToolGuardMixin, ReActAgent)` 的类声明
- [ ] 理解了七步初始化序列的顺序
- [ ] 知道工厂模式在哪里被使用（`create_model_and_formatter`）

---

Agent 诞生了——模型、工具、技能、提示词、记忆全都就位。但它怎么知道自己是"谁"？系统提示词是怎么从一堆 Markdown 文件变成一段完整文本的？下一章我们走进提示词的拼装车间。
