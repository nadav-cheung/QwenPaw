# QwenPaw 源码探秘 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 写一本 25万字+ 的源码分析书，从零开始（替换现有 `book/` 内容），26 章 + 5 附录。

**Architecture:** 单请求贯穿式叙事。每章包含：导航标记、问题、术语栏、探索、实验、工程权衡、常见误区、动手环节（含预期输出和自检清单）。代码展示不超过 15 行，伪代码优先。不写精确行号，用函数名+类名引用。段落内联小图用纯 ASCII（不混中文），架构级图解用 Mermaid。

**Tech Stack:** Markdown, ASCII art, Mermaid diagrams

**Spec:** `docs/superpowers/specs/2026-05-10-qwenpaw-sourcebook-design.md`

---

## Phase 1: 序章 + 卷一（Ch 0-8）

每个 Task = 一个章节文件。每个步骤约 2-5 分钟。

### Task 1: 重写序章

**Files:**
- Overwrite: `book/00-序章-启程之前.md`
- Read: `src/qwenpaw/cli/init_cmd.py`、`src/qwenpaw/cli/app_cmd.py`、`src/qwenpaw/cli/doctor_cmd.py`

- [ ] **Step 1: 阅读源码确认安装/初始化/启动流程**

Read `init_cmd.py` 确认 `qwenpaw init --defaults` 的实际行为。Read `app_cmd.py` 确认 `qwenpaw app` 的启动流程和端口号。Read `doctor_cmd.py` 确认诊断命令的实际名称和参数。

- [ ] **Step 2: 写序章内容**

重写 `book/00-序章-启程之前.md`。保留现有内容中正确的部分（安装、初始化、配置模型、验证），但需要：
- 在开头添加「你在这里」导航标记（序章无位置，写"准备出发"）
- 确认所有命令名、文件路径、端口号与源码一致
- 在「我们将会经历什么」部分更新为新的 26 章大纲（8+6+5+7 结构）
- 添加术语栏（如无新术语可跳过）
- 字数目标：3000-4000 字（序章较短）

- [ ] **Step 3: 验证准确性**

确认文中提到的每个 CLI 命令、文件路径、端口号都能在源码中找到对应。验证方法：grep 文中提到的每个函数名/命令名，确认在源码中存在。

- [ ] **Step 4: 提交**

```bash
git add book/00-序章-启程之前.md
git commit -m "docs: rewrite prologue with accurate CLI commands and updated chapter outline"
```

---

### Task 2: 第 1 章——浏览器按下回车之后

**Files:**
- Create: `book/01-浏览器按下回车之后.md`
- Read: `src/qwenpaw/app/_app.py`、`src/qwenpaw/app/routers/console.py`、`src/qwenpaw/app/routers/__init__.py`、`src/qwenpaw/app/auth.py`

- [ ] **Step 1: 读源码，提取关键信息**

从 `_app.py` 提取：
- `DynamicMultiAgentRunner` 类：理解它如何通过 `X-Agent-Id` 头路由请求
- 中间件注册顺序：`AgentContextMiddleware` → `AuthMiddleware` → `CORSMiddleware`
- 路由注册：`api_router`、`agent_scoped_router`、`agent_app.router`
- `lifespan()` 函数：理解启动流程
- `app = FastAPI(...)` ：最终应用构造

从 `routers/console.py` 提取：
- `post_console_chat()` ：主聊天端点，返回 `StreamingResponse`
- `_extract_session_and_payload()` ：如何解析请求体
- `event_generator()` ：SSE 事件生成

从 `auth.py` 提取：认证中间件如何检查请求。

- [ ] **Step 2: 写章节内容**

创建 `book/01-浏览器按下回车之后.md`，包含：

1. **导航标记**：标注在"浏览器 → [HTTP/FastAPI] → Runner → Agent → ..."中的位置
2. **问题**：按下回车后发生了什么？
3. **术语栏**：HTTP（1 个）、FastAPI（1 个）、中间件（1 个）、SSE（1 个）
4. **探索**：
   - 浏览器发出的 HTTP 请求长什么样（用 curl 示例展示）
   - FastAPI 如何匹配路由（展示 `console.py` 的路由注册，<=15 行）
   - 中间件链如何处理请求（洋葱模型图）
   - 请求如何到达 `post_console_chat()` 处理函数
5. **实验**：用 `curl` 发送一条请求，观察 FastAPI 日志
6. **工程权衡**：为什么用 SSE 而非 WebSocket？为什么中间件是洋葱模型？
7. **常见误区**：为什么不把认证逻辑直接写在路由函数里？（引出中间件的价值）
8. **动手环节**（观察级）：用 `curl` 发请求，观察日志。预期输出：看到 SSE 事件流。自检：能找到请求对应的端点函数名。

**图解**：
- ASCII：请求从浏览器到 FastAPI 的路径图
- ASCII：中间件洋葱模型图

字数目标：8000-12000 字。

- [ ] **Step 3: 验证准确性**

确认所有函数名与源码一致。验证方法：grep 文中提到的每个函数名，确认在源码中存在。确认 curl 命令可执行。

- [ ] **Step 4: 提交**

```bash
git add book/01-浏览器按下回车之后.md
git commit -m "docs: write chapter 1 - HTTP request reaches FastAPI"
```

---

### Task 3: 第 2 章——请求到达 Runner

**Files:**
- Create: `book/02-请求到达Runner.md`
- Read: `src/qwenpaw/app/runner/runner.py`、`src/qwenpaw/app/runner/manager.py`、`src/qwenpaw/app/multi_agent_manager.py`、`src/qwenpaw/app/runner/session.py`、`src/qwenpaw/app/runner/task_tracker.py`、`src/qwenpaw/app/runner/command_dispatch.py`

- [ ] **Step 1: 读源码，提取关键信息**

从 `runner.py` 提取：
- `AgentRunner(Runner)` 类
- `query_handler()` ：主分发方法
- `_parse_skill_query()` ：`/<skill>` 命令解析
- `init_handler()` ：Session 初始化

从 `multi_agent_manager.py` 提取：
- `get_agent()` ：延迟加载 Agent 的逻辑
- `reload_agent()` ：零停机重载

从 `task_tracker.py` 提取：
- `TaskTracker` 类：如何管理后台运行状态

- [ ] **Step 2: 写章节内容**

创建 `book/02-请求到达Runner.md`，包含：

1. **导航标记**：标注在请求链路中 "Runner 调度" 的位置
2. **问题**：FastAPI 收到请求后怎么找到正确的 Agent？
3. **术语栏**：Runner、Session、命令分发
4. **探索**：
   - `DynamicMultiAgentRunner.stream_query()` → `_get_workspace()` → `MultiAgentManager.get_agent()` 的调用链
   - 命令分发：`/` 开头的命令 vs 普通消息
   - Session 的概念和生命周期
   - TaskTracker 如何管理并发请求
5. **实验**：启动 QwenPaw，发消息，观察 Runner 日志
6. **工程权衡**：为什么用延迟加载而非启动时全部加载？为什么 Session 要持久化？
7. **动手环节**（观察级）：启动时观察 Runner 日志

**图解**：
- ASCII：Runner 调度流程图
- ASCII：Session 生命周期图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/02-请求到达Runner.md
git commit -m "docs: write chapter 2 - Runner dispatches to Agent"
```

---

### Task 4: 第 3 章——Agent 的诞生

**Files:**
- Create: `book/03-Agent的诞生.md`
- Read: `src/qwenpaw/agents/react_agent.py`、`src/qwenpaw/agents/model_factory.py`

- [ ] **Step 1: 读源码**

从 `react_agent.py` 提取：
- `QwenPawAgent(ToolGuardMixin, ReActAgent)` 类声明和 MRO
- `__init__()` ：初始化流程
- `_create_toolkit()` ：18 个内置工具的注册
- `_register_skills()` ：技能加载
- `_build_sys_prompt()` ：系统提示词构建
- `_setup_memory_manager()` ：记忆系统设置
- `_register_hooks()` ：钩子注册

从 `model_factory.py` 提取：
- `create_model_and_formatter()` ：工厂入口
- `_create_formatter_instance()` ：格式化器创建

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：Agent 是什么？怎么被创建的？
3. **术语栏**：Agent、类与实例、工厂模式、Mixin
4. **探索**：
   - Agent 的继承链：`QwenPawAgent → ToolGuardMixin → ReActAgent`
   - `__init__` 做了哪些事（用伪代码展示，不超过 15 行）
   - ModelFactory 如何根据配置创建模型
   - 18 个工具是怎么注册到 Agent 的
5. **实验**：在源码中找到 `QwenPawAgent` 的创建位置
6. **工程权衡**：为什么用工厂模式创建模型？为什么工具要注册而非硬编码？
7. **动手环节**（观察级）：在 IDE 中打开 `react_agent.py`，浏览 `__init__` 方法

**图解**：
- Mermaid：Agent 继承链类图
- ASCII：Agent 创建流程图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/03-Agent的诞生.md
git commit -m "docs: write chapter 3 - Agent creation and initialization"
```

---

### Task 5: 第 4 章——系统提示词的拼装

**Files:**
- Create: `book/04-系统提示词的拼装.md`
- Read: `src/qwenpaw/agents/prompt.py`、工作目录下 `~/.qwenpaw/working/agents/` 中的 agent md 文件

- [ ] **Step 1: 读源码**

从 `prompt.py` 提取：
- `PromptConfig` ：`DEFAULT_FILES = ["AGENTS.md", "SOUL.md", "PROFILE.md"]`
- `PromptBuilder` 类：Builder 模式
- `_load_file()` ：加载文件并剥离 YAML frontmatter
- `_process_heartbeat_section()` ：心跳块过滤
- `_process_memory_section()` ：记忆块过滤
- `build()` ：最终拼装
- `build_system_prompt_from_working_dir()` ：顶层函数
- `build_multimodal_hint()` ：多模态提示

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：Agent 怎么知道自己是"谁"？
3. **术语栏**：System Prompt、模板拼装、工作区
4. **探索**：
   - AGENTS.md → SOUL.md → PROFILE.md 的加载顺序
   - YAML frontmatter 剥离
   - 心跳块和记忆块的特殊处理
   - 最终 Prompt 的结构（用什么拼、按什么顺序）
5. **实验**：打印实际发送给 LLM 的 System Prompt
6. **工程权衡**：为什么用多个文件而非一个大文件？为什么支持 frontmatter？
7. **动手环节**（观察级）：修改 `AGENTS.md`，观察 Agent 行为变化

**图解**：
- ASCII：Prompt 拼装流程图
- ASCII：最终 Prompt 结构图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/04-系统提示词的拼装.md
git commit -m "docs: write chapter 4 - system prompt assembly"
```

---

### Task 6: 第 5 章——进入 ReAct 循环

**Files:**
- Create: `book/05-进入ReAct循环.md`
- Read: `src/qwenpaw/agents/react_agent.py`（重点：`reply()`、`_reasoning()`、`_auto_continue_if_text_only()`）、`src/qwenpaw/agents/tool_guard_mixin.py`（重点：`_reasoning()`、`_acting()`）

- [ ] **Step 1: 读源码**

从 `react_agent.py` 提取：
- `reply()` ：入口点
- `_reasoning()` ：推理重写（媒体过滤）
- `_auto_continue_if_text_only()` ：自动续推

从 `tool_guard_mixin.py` 提取：
- `_reasoning()` ：安全拦截推理
- `_acting()` ：安全拦截工具执行

理解 MRO 调用链：`reply()` → `_reasoning()` → ToolGuardMixin._reasoning() → QwenPawAgent._reasoning() → super()._reasoning()

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：为什么 Agent 不是直接回答，而是"思考→行动→观察→再思考"？
3. **术语栏**：ReAct（Reasoning + Acting）、消息队列
4. **探索**：
   - ReAct 循环的核心：思考（LLM 生成）→ 行动（工具调用）→ 观察（工具结果）→ 再思考
   - MRO 如何让 ToolGuardMixin 在循环中插入安全检查
   - 循环终止条件：文本回复、最大迭代次数
5. **实验**：发送"现在几点了？"观察 Agent 调用 `get_current_time` 工具的完整循环
6. **工程权衡**：为什么用 ReAct 而非纯生成？为什么用 MRO 拦截而非在主循环中加 if 判断？
7. **动手环节**（观察级）：观察 ReAct 循环日志

**图解**：
- Mermaid：ReAct 循环时序图
- ASCII：思考→行动→观察流转图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/05-进入ReAct循环.md
git commit -m "docs: write chapter 5 - ReAct reasoning loop"
```

---

### Task 7: 第 6 章——调用大语言模型

**Files:**
- Create: `book/06-调用大语言模型.md`
- Read: `src/qwenpaw/providers/provider.py`、`src/qwenpaw/providers/openai_provider.py`、`src/qwenpaw/providers/provider_manager.py`、`src/qwenpaw/agents/model_factory.py`（重点：`create_model_and_formatter()`）

- [ ] **Step 1: 读源码**

从 `provider.py` 提取：
- `Provider(ProviderInfo, ABC)` 抽象基类
- 抽象方法列表：`check_connection()`、`fetch_models()`、`check_model_connection()`、`get_chat_model_instance()`

从 `openai_provider.py` 提取：
- `OpenAIProvider` 的具体实现
- `get_chat_model_instance()` 如何创建 OpenAI 客户端

从 `provider_manager.py` 提取：
- `get_provider()` ：Provider 查找逻辑
- `activate_model()` ：激活模型

从 `model_factory.py` 提取：
- `create_model_and_formatter()` 包装链：Provider → TokenRecording → RetryChatModel

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：Agent 的"思考"是怎么变成 LLM API 调用的？
3. **术语栏**：Provider、流式响应、Token
4. **探索**：
   - Provider 抽象层的必要性
   - 从 `create_model_and_formatter()` 到实际 API 调用的完整包装链
   - 流式响应的实现：SSE chunk 如何从 Provider 到浏览器
   - 重试和限流机制（RetryChatModel）
5. **实验**：切换 Provider（如 OpenAI → Ollama），观察日志差异
6. **工程权衡**：为什么用抽象层而非直接调用 SDK？为什么需要重试包装？
7. **动手环节**（观察级）：切换 Provider，对比日志

**图解**：
- Mermaid：Provider 抽象层类图
- ASCII：API 调用时序图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/06-调用大语言模型.md
git commit -m "docs: write chapter 6 - LLM provider call chain"
```

---

### Task 8: 第 7 章——工具的执行

**Files:**
- Create: `book/07-工具的执行.md`
- Read: `src/qwenpaw/agents/tools/` 目录（`shell.py`、`file_io.py`、`get_current_time.py`）、`src/qwenpaw/agents/tool_guard_mixin.py`（`_acting()`、`_decide_guard_action()`）

- [ ] **Step 1: 读源码**

从 `tools/shell.py` 提取：`execute_shell_command` 函数签名和参数。
从 `tools/file_io.py` 提取：`read_file`、`write_file` 函数签名。
从 `tools/get_current_time.py` 提取：最简单的工具参考实现。
从 `tool_guard_mixin.py` 提取：
- `_acting()` ：工具执行拦截
- `_decide_guard_action()` ：决定操作（auto_denied / preapproved / needs_approval）

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：LLM 说"我需要执行一个 Shell 命令"，然后呢？
3. **术语栏**：Function Calling、工具注册表、ToolGuard
4. **探索**：
   - Function Calling 机制：LLM 返回 JSON 格式的工具调用请求
   - 工具注册表：Agent 怎么知道有哪些工具
   - ToolGuard 如何在执行前检查安全性
   - 从 LLM 返回到工具执行再到结果返回的完整链路
5. **实验**：让 Agent 执行 `get_current_time`，观察工具调用日志
6. **工程权衡**：为什么需要 ToolGuard？为什么不让 AI 随意执行？
7. **动手环节**（观察级）：执行安全工具调用，观察日志

**图解**：
- ASCII：工具调用流程图
- ASCII：ToolGuard 检查链图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/07-工具的执行.md
git commit -m "docs: write chapter 7 - tool execution and security guard"
```

---

### Task 9: 第 8 章——响应的归途

**Files:**
- Create: `book/08-响应的归途.md`
- Read: `src/qwenpaw/app/runner/runner.py`（`_stream_printing_messages_interruptible()`）、`src/qwenpaw/app/routers/console.py`（`event_generator()`）、`src/qwenpaw/app/runner/task_tracker.py`

- [ ] **Step 1: 读源码**

从 `runner.py` 提取：
- `_stream_printing_messages_interruptible()` ：消息队列 + 流式输出
- `_PRINT_END_SIGNAL` ：流终止信号

从 `console.py` 提取：
- `event_generator()` ：SSE 事件格式化

从 `task_tracker.py` 提取：
- `TaskTracker` 如何管理多个订阅者的队列
- 断线重连的 buffer 回放机制

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：Agent 的回复怎么回到浏览器的？为什么能逐字显示？
3. **术语栏**：SSE（Server-Sent Events）
4. **探索**：
   - 消息队列机制：Agent 推送到 Queue → SSE 消费者从 Queue 取
   - SSE 事件格式：`data: {...}\n\n`
   - 流终止：`[END]` 信号
   - 断线重连：buffer 回放
   - **完整请求生命周期回顾**：串联 8 章所有站点
5. **实验**：用浏览器开发者工具 Network 面板观察 SSE 事件流
6. **工程权衡**：为什么用 SSE 而非 WebSocket？为什么需要 buffer？
7. **动手环节**（观察级）：观察 SSE 事件流

**图解**：
- ASCII：完整请求生命周期全景图（串联 8 章，这是全卷最重要的图）

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/08-响应的归途.md
git commit -m "docs: write chapter 8 - response streaming back to browser"
```

---

### Task 10: 更新 README + 卷一 review

**Files:**
- Modify: `book/README.md`

- [ ] **Step 1: 更新 README**

重写 `book/README.md`，反映新的设计：
- 更新全书结构表（序章 + 4 卷 + 附录）
- 更新章节列表（26 章 + 5 附录）
- 保留"阅读方式"、"你需要的准备"、"源码权威"等通用部分

- [ ] **Step 2: Review 卷一全部章节**

检查：
- 章节间衔接是否自然
- 术语栏是否覆盖了所有新概念
- 导航标记是否正确标注位置
- 代码引用是否与源码一致
- 图解是否清晰

- [ ] **Step 3: 提交**

```bash
git add book/README.md
git commit -m "docs: update book README with new 4-volume structure"
```

---

## Phase 2: 卷二·图纸（Ch 9-14）

### Task 11: 第 9 章——源码的地图

**Files:**
- Create: `book/09-源码的地图.md`
- Read: `src/qwenpaw/` 全目录结构、每个 `__init__.py` 的导出

- [ ] **Step 1: 读源码，梳理模块结构**

列出 `src/qwenpaw/` 下每个包的一句话职责。画出依赖方向图。

- [ ] **Step 2: 写章节内容**

1. **导航标记**：全景鸟瞰，高亮卷一走过的路径
2. **问题**：十几个文件夹之间是什么关系？
3. **术语栏**：模块化单体、依赖方向
4. **探索**：
   - 先回顾卷一走过的完整请求链路
   - 然后拉远镜头，鸟瞰整个模块结构
   - 每个包的职责和依赖方向
5. **工程权衡**：为什么用模块化单体而非微服务？为什么不允许循环依赖？
6. **动手环节**（验证级）：画出自己的模块关系图

**图解**：
- ASCII：源码模块全景图（高亮卷一路径）
- ASCII：洋葱架构层视图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/09-源码的地图.md
git commit -m "docs: write chapter 9 - source code map and architecture overview"
```

---

### Task 12: 第 10 章——Agent 的身世

**Files:**
- Create: `book/10-Agent的身世.md`
- Read: `src/qwenpaw/agents/react_agent.py`、`src/qwenpaw/agents/tool_guard_mixin.py`

- [ ] **Step 1: 读源码**

聚焦 MRO：`QwenPawAgent → ToolGuardMixin → ReActAgent`。理解每一层重写了哪些方法、为什么用 `super()` 调用链。

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：为什么中间插了一个 ToolGuardMixin？
3. **术语栏**：MRO、Mixin、开放封闭原则
4. **探索**：Python MRO 解析顺序、Mixin vs 继承 vs 组合的对比、ToolGuardMixin 如何"混入"安全能力
5. **工程权衡**：为什么选 Mixin 而非普通继承或组合？
6. **动手环节**（验证级）：写一个简单 Mixin 体验混入机制

**图解**：
- Mermaid：Agent 类继承链图（标注 MRO 顺序）
- ASCII：Mixin 注入能力示意图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

```bash
git add book/10-Agent的身世.md
git commit -m "docs: write chapter 10 - Mixin pattern and MRO"
```

---

### Task 13: 第 11 章——Provider 的棋局

**Files:**
- Create: `book/11-Provider的棋局.md`
- Read: `src/qwenpaw/providers/provider.py`、`src/qwenpaw/providers/openai_provider.py`、`src/qwenpaw/providers/anthropic_provider.py`、`src/qwenpaw/providers/provider_manager.py`

- [ ] **Step 1: 读源码**

对比 `Provider` ABC 和 2-3 个具体实现。理解 `ProviderManager._provider_from_data()` 的分派逻辑。

- [ ] **Step 2: 写章节内容**

1. **导航标记**
2. **问题**：为什么不直接调用 OpenAI SDK？
3. **术语栏**：策略模式、抽象基类（ABC）
4. **探索**：策略模式的应用、ABC 的契约、工厂+策略组合、ProviderManager 的分派
5. **工程权衡**：抽象层的代价（复杂度）vs 收益（可替换性）
6. **动手环节**（验证级）：阅读 Provider ABC 的方法列表

**图解**：
- Mermaid：Provider 抽象层类图
- ASCII：策略切换流程图

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 14: 第 12 章——Channel 的变装

**Files:**
- Create: `book/12-Channel的变装.md`
- Read: `src/qwenpaw/app/channels/base.py`、`src/qwenpaw/app/channels/console/channel.py`、`src/qwenpaw/app/channels/telegram/channel.py`、`src/qwenpaw/app/channels/manager.py`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（适配器模式、BaseChannel 契约、消息格式转换）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 15: 第 13 章——Security 的围栏

**Files:**
- Create: `book/13-Security的围栏.md`
- Read: `src/qwenpaw/security/tool_guard/engine.py`、`src/qwenpaw/security/tool_guard/guardians/rule_guardian.py`、`src/qwenpaw/security/tool_guard/guardians/file_guardian.py`、`src/qwenpaw/security/skill_scanner/scanner.py`、`src/qwenpaw/security/secret_store.py`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（拦截器模式、规则引擎、纵深防御）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 16: 第 14 章——Skills 的工坊

**Files:**
- Create: `book/14-Skills的工坊.md`
- Read: `src/qwenpaw/agents/skills_manager.py`、任意一个 Skill 目录（如 `skills/cron-en/`）

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（插件架构、Skill 生命周期、热插拔、Markdown 即代码）
- [ ] **Step 2b: 添加卷二→卷三过渡桥段**

在第 14 章末尾添加半引导式过渡练习："你已经看懂了 Skill 的插件架构。如果让你给 Skill 加一个'执行前确认'功能，你会改哪个文件？不用写代码，只需在源码中找到你会修改的位置，用一句话描述你的思路。"让读者心理上准备好从"看"切换到"做"。

- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

## Phase 3: 卷三·工坊（Ch 15-19）

### Task 17: 第 15 章——造一把新工具

**Files:**
- Create: `book/15-造一把新工具.md`
- Read: `src/qwenpaw/agents/tools/get_current_time.py`（最简单参考）、`src/qwenpaw/agents/tools/shell.py`（复杂参考）、`src/qwenpaw/agents/react_agent.py`（重点：`_create_toolkit()` 方法中的工具注册）

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Tool 接口规范、注册流程、Function Calling 端到端）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 18: 第 16 章——造一个新技能

**Files:**
- Create: `book/16-造一个新技能.md`
- Read: `src/qwenpaw/agents/skills_manager.py`、现有 Skill 目录

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Skill vs Tool、目录结构、Markdown 指令、Cron 调度）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 19: 第 17 章——接入一个新模型

**Files:**
- Create: `book/17-接入一个新模型.md`
- Read: `src/qwenpaw/providers/provider.py`（ABC）、`src/qwenpaw/providers/openai_provider.py`（参考）

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Provider 接口契约、OpenAI 兼容协议、配置集成）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 20: 第 18 章——接入一个新频道

**Files:**
- Create: `book/18-接入一个新频道.md`
- Read: `src/qwenpaw/app/channels/base.py`、`src/qwenpaw/app/channels/console/channel.py`、`src/qwenpaw/app/channels/telegram/channel.py`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（BaseChannel 契约、消息收发抽象、Webhook vs 长连接）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 21: 第 19 章——从零到 PR

**Files:**
- Create: `book/19-从零到PR.md`
- Read: `.github/workflows/tests.yml`、`.github/workflows/pre-commit.yml`、`CONTRIBUTING.md`（如存在）

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Git 工作流、代码风格、测试要求、CI 流程、PR 审查标准）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

## Phase 4: 卷四·纵深（Ch 20-26）

### Task 22: 第 20 章——配置的秘密

**Files:**
- Create: `book/20-配置的秘密.md`
- Read: `src/qwenpaw/config/config.py`、`src/qwenpaw/config/context.py`、`src/qwenpaw/config/timezone.py`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（配置加载、热更新 vs 冷更新、Context 模式）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 23: 第 21 章——记忆的宫殿

**Files:**
- Create: `book/21-记忆的宫殿.md`
- Read: `src/qwenpaw/agents/memory/base_memory_manager.py`、`src/qwenpaw/agents/memory/reme_light_memory_manager.py`、`src/qwenpaw/agents/memory/proactive/`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（记忆层次、Reme-Light 引擎、存取流程、触发机制）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 24: 第 22 章——自治任务

**Files:**
- Create: `book/22-自治任务.md`
- Read: `src/qwenpaw/agents/mission/` 目录

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Mission 模式 vs 普通对话、任务分解、安全边界）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 25: 第 23 章——多智能体协作

**Files:**
- Create: `book/23-多智能体协作.md`
- Read: `src/qwenpaw/app/multi_agent_manager.py`、`src/qwenpaw/agents/acp/` 目录、`src/qwenpaw/agents/tools/agent_management.py`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（多智能体架构、通信机制、ACP 协议）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 26: 第 24 章——插件系统

**Files:**
- Create: `book/24-插件系统.md`
- Read: `src/qwenpaw/plugins/` 目录

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（插件生命周期、API 暴露、沙箱、Plugin vs Skill）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 27: 第 25 章——命令行与部署

**Files:**
- Create: `book/25-命令行与部署.md`
- Read: `src/qwenpaw/cli/main.py`、`src/qwenpaw/cli/app_cmd.py`、`docker-compose.yml`、`Dockerfile`（如存在）

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（Click 懒加载、启动流程、Docker 部署）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

### Task 28: 第 26 章——测试与质量

**Files:**
- Create: `book/26-测试与质量.md`
- Read: `tests/` 目录、`.github/workflows/tests.yml`

- [ ] **Step 1: 读源码**
- [ ] **Step 2: 写章节内容**（测试金字塔、pytest 组织、CI/CD、为贡献写测试）
- [ ] **Step 3: 验证准确性**
- [ ] **Step 4: 提交**

---

## Phase 5: 附录

### Task 29: 附录 A+B（环境变量 + CLI 命令速查）

**Files:**
- Create: `book/附录A-环境变量速查.md`
- Create: `book/附录B-CLI命令速查.md`

- [ ] **Step 1: 从源码提取环境变量清单**

Read `src/qwenpaw/envs/` 和 `src/qwenpaw/config/`，列出所有环境变量。

- [ ] **Step 2: 从 CLI 源码提取命令清单**

Read `src/qwenpaw/cli/` 目录下所有命令文件，列出所有 CLI 命令、参数和说明。

- [ ] **Step 3: 写附录 A 和 B**

- [ ] **Step 4: 验证准确性**

grep 附录中提到的每个环境变量名和命令名，确认在源码中存在。

- [ ] **Step 5: 提交**

```bash
git add book/附录A-环境变量速查.md book/附录B-CLI命令速查.md
git commit -m "docs: write appendices A-B (env vars, CLI commands)"
```

---

### Task 29b: 附录 C+D+E（源码结构 + 错误代码 + 术语索引）

**Files:**
- Create: `book/附录C-源码结构总览.md`
- Create: `book/附录D-错误代码速查.md`
- Create: `book/附录E-术语索引.md`

- [ ] **Step 1: 写附录 C**

列出 `src/qwenpaw/` 下每个目录的一句话说明。

- [ ] **Step 2: 写附录 D**

从源码中提取错误代码和错误消息。

- [ ] **Step 3: 写附录 E（术语索引）**

汇总全书各章"术语其实很简单"栏目，按拼音排序，标注首次出现的章节号。

- [ ] **Step 4: 验证准确性**

- [ ] **Step 5: 提交**

```bash
git add book/附录C-源码结构总览.md book/附录D-错误代码速查.md book/附录E-术语索引.md
git commit -m "docs: write appendices C-E (source structure, error codes, terminology index)"
```

---

## Phase 6: 最终 Review

### Task 30: 章节间衔接 + 叙事连贯性检查

- [ ] **Step 1: 检查章节间衔接**

确认每章末尾自然过渡到下一章。确认卷间过渡（卷一→卷二、卷二→卷三、卷三→卷四）流畅。重点检查第 9 章"回顾与鸟瞰"的过渡效果，以及第 14 章末尾的半引导式桥段。

- [ ] **Step 2: 提交**

```bash
git add book/
git commit -m "docs: review chapter transitions and narrative continuity"
```

---

### Task 31: 术语一致性 + 代码引用准确性

- [ ] **Step 1: 检查术语一致性**

确认同一概念在不同章节使用相同术语。检查要点：Agent vs agent、Provider vs provider、Session vs 会话 等大小写/中英文混用的一致性。

- [ ] **Step 2: 检查代码引用准确性**

抽查每章的关键代码引用，验证方法：grep 文中提到的每个函数名/类名，确认在源码中存在且描述匹配。**不检查行号**（行号随版本变化是预期的）。

- [ ] **Step 3: 提交**

```bash
git add book/
git commit -m "docs: review terminology consistency and code reference accuracy"
```

---

### Task 32: 图解清晰度 + README 更新

- [ ] **Step 1: 检查图解清晰度**

确认所有 ASCII 图仅使用纯 ASCII 字符（无中文、无全角符号）。确认 Mermaid 语法在 GitHub 上可正确渲染。抽查每章至少一个图解的渲染效果。

- [ ] **Step 2: 更新 README 确保与实际内容一致**

更新 `book/README.md`：版本锚定声明、推荐阅读路径、26 章 + 5 附录结构表。

- [ ] **Step 3: 提交**

```bash
git add book/
git commit -m "docs: final review - diagrams, README, and polish"
```
