✅ 内容增强完成

# Mission Mode 详解：自主迭代式复杂任务执行

## 概述

Mission Mode 是 QwenPaw 的**自主迭代式任务执行模式**，专为复杂、长期、多步骤的软件开发任务设计。与普通对话模式不同，Mission Mode 将任务分解为结构化的 PRD（产品需求文档），通过两阶段执行（Phase 1: 需求分析 → Phase 2: 迭代执行）完成。

**源码路径**: `src/qwenpaw/agents/mission/`

**核心文件**:
| 文件 | 职责 |
|------|------|
| `handler.py` | 命令解析、状态文件初始化、Phase 1 触发 |
| `mission_runner.py` | Phase 1/2 执行引擎、PRD 验证、工具限制 |
| `state.py` | 任务目录管理、PRD/配置文件读写、Git 上下文检测 |
| `prompts.py` | Master prompt 模板构建 |

---

## 1. 核心概念

### 1.1 两阶段执行模型

```
┌─────────────────────────────────────────────────────────────┐
│                     Mission Mode                              │
├─────────────────────────────────────────────────────────────┤
│  Phase 1: PRD 生成                                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ • Agent 探索代码库                                  │    │
│  │ • 生成 prd.json（userStories 格式）                │    │
│  │ • 用户确认后进入 Phase 2                           │    │
│  │ • 所有工具可用                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                           ↓ 用户确认                         │
│  Phase 2: 迭代执行                                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ • 实现工具被禁用（edit_file, browser_use 等）       │    │
│  │ • Master Agent 作为控制器，通过 worker 执行         │    │
│  │ • 每个 story 有独立的 verifier                     │    │
│  │ • 迭代直到所有 story 通过或达到 max_iterations     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 状态文件布局

```
{workspace_dir}/missions/{loop_id}/
├── loop_config.json   # 环境元数据（git、路径、阶段）
├── prd.json           # 任务列表（worker 更新 passes 字段）
├── progress.txt       # 追加式迭代日志
└── task.md           # 原始任务描述（只读）
```

---

## 2. 命令处理：handler.py

**源码路径**: `src/qwenpaw/agents/mission/handler.py`

### 2.1 命令检测

```python
# handler.py:37-43
MISSION_COMMANDS = frozenset({"/mission"})

def is_mission_command(query: str | None) -> bool:
    """Return True if the query starts with a mission trigger command."""
    if not query or not isinstance(query, str):
        return False
    token = query.strip().split(None, 1)[0].lower()
    return token in MISSION_COMMANDS
```

### 2.2 参数解析

```python
# handler.py:46-89
def _parse_mission_args(query: str) -> dict[str, Any]:
    """Parse ``/mission [task text] [--verify CMD] [--max-iterations N]``."""
    args: dict[str, Any] = {
        "task_text": "",
        "verify_commands": "",
        "max_iterations": _DEFAULT_MAX_ITERATIONS,  # 20
    }
    # 支持 --verify 和 --max-iterations 选项
    # max_iterations 范围: 1-100
```

### 2.3 异步处理入口

```python
# handler.py:92-220
async def handle_mission_command(
    query: str,
    msgs: list,
    workspace_dir: Path,
    agent_id: str,
    rewrite_fn: Any,
    session_id: str = "",
) -> str | dict[str, Any]:
    """处理 /mission 命令"""
    args = _parse_mission_args(query)
    task_text = args["task_text"]

    # 子命令：status, list, help
    if task_text.strip().lower() == "status":
        return _get_status_text(...)
    if task_text.strip().lower() == "list":
        return _get_list_text(...)

    # 无效查询拦截
    if not task_text or len(task_text.strip()) < 5:
        return "用法说明..."

    # 元查询拦截（"什么是 Mission Mode"等）
    if any(kw in task_text.lower() for kw in meta_keywords):
        return "这不是一个任务..."

    # 创建状态目录和文件
    loop_dir = create_loop_dir(workspace_dir)
    write_task_md(loop_dir, task_text)
    init_progress_txt(loop_dir)

    # 检测 Git 上下文
    git_ctx = await detect_git_context(workspace_dir)

    # 写入 loop_config.json
    loop_config: dict[str, Any] = {
        "git_installed": git_ctx["git_installed"],
        "is_git_repo": git_ctx["is_git_repo"],
        "max_iterations": max_iterations,
        "current_phase": "prd_generation",
        "session_id": session_id,
        "verify_commands": args["verify_commands"],
        ...
    }
    write_loop_config(loop_dir, loop_config)

    # 返回 Phase 1 启动信息
    return {
        "mission_phase": 1,
        "loop_dir": str(loop_dir),
        "max_iterations": max_iterations,
    }
```

---

## 3. 状态管理：state.py

**源码路径**: `src/qwenpaw/agents/mission/state.py`

### 3.1 Git 上下文检测（异步）

```python
# state.py:47-103
async def detect_git_context(workspace_dir: Path) -> dict[str, Any]:
    """探测 Git 可用性（异步）"""
    ctx: dict[str, Any] = {
        "git_installed": False,
        "is_git_repo": False,
        "default_branch": "",
        "current_branch": "",
        "repo_root": "",
    }

    if shutil.which("git") is None:
        return ctx

    # 并发执行多个 git 查询
    toplevel_task = _git_cmd("rev-parse", "--show-toplevel", cwd=cwd)
    branch_task = _git_cmd("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd)
    main_task = _git_cmd("rev-parse", "--verify", "refs/heads/main", cwd=cwd)
    master_task = _git_cmd("rev-parse", "--verify", "refs/heads/master", cwd=cwd)

    (rc_top, out_top), (rc_br, out_br), ... = await asyncio.gather(...)

    # 确定默认分支
    if rc_main == 0:
        ctx["default_branch"] = "main"
    elif rc_master == 0:
        ctx["default_branch"] = "master"
```

### 3.2 目录与文件操作

```python
# state.py:106-190
def create_loop_dir(workspace_dir: Path) -> Path:
    """创建新的任务目录"""
    loop_id = f"mission-{_ts()}"  # mission-20260430-143052
    loop_dir = workspace_dir / "missions" / loop_id
    loop_dir.mkdir(parents=True, exist_ok=True)
    return loop_dir

def write_loop_config(loop_dir: Path, config: dict[str, Any]) -> Path:
    """持久化环境元数据"""
    p = loop_dir / "loop_config.json"
    p.write_text(json.dumps(config, indent=2, ensure_ascii=False))
    return p

def read_loop_config(loop_dir: Path) -> dict[str, Any]:
    """读取 loop_config.json"""
    p = loop_dir / "loop_config.json"
    if not p.exists():
        return {}
    return json.loads(p.read_text())

def write_prd_json(loop_dir: Path, prd: dict[str, Any]) -> Path:
    """写入结构化任务列表"""
    p = loop_dir / "prd.json"
    ...

def read_prd(loop_dir: Path) -> dict[str, Any]:
    """读取 prd.json"""
    ...

def get_active_loop_dir(workspace_dir: Path, session_id: str = "") -> Path | None:
    """返回当前会话的最新任务目录"""
    # 扫描最近 20 个目录，匹配 session_id
```

---

## 4. 执行引擎：mission_runner.py

**源码路径**: `src/qwenpaw/agents/mission/mission_runner.py`

### 4.1 PRD 验证

```python
# mission_runner.py:92-137
_REQUIRED_PRD_FIELDS = {"userStories"}
_REQUIRED_STORY_FIELDS = {"id", "title", "description", "acceptanceCriteria", "priority", "passes"}

class PrdValidationError(ValueError):
    """prd.json 不符合预期 schema 时抛出"""

def validate_prd(prd: dict[str, Any]) -> list[str]:
    """验证 PRD dict，返回问题列表（空 = 有效）"""
    problems: list[str] = []

    if "userStories" not in prd:
        problems.append("Missing top-level 'userStories' array")
        return problems

    stories = prd["userStories"]
    if not isinstance(stories, list) or len(stories) == 0:
        problems.append("'userStories' must be a non-empty array")
        return problems

    for i, story in enumerate(stories):
        missing = _REQUIRED_STORY_FIELDS - set(story.keys())
        if missing:
            problems.append(f"userStories[{i}] missing: {', '.join(sorted(missing))}")

    return problems
```

### 4.2 Phase 1: PRD 生成

```python
# mission_runner.py:277-360
async def run_mission_phase1(
    agent: Any,
    msgs: list,
    loop_dir: Path,
    max_iterations: int = 20,
    agent_id: str = None,
) -> AsyncGenerator[tuple[Msg, bool], None]:
    """执行 Phase 1（PRD 生成/用户确认）"""

    async for msg, last in stream_printing_messages(
        agents=[agent],
        coroutine_task=agent(msgs),
    ):
        yield msg, last

    # 检查是否用户确认进入 Phase 2
    cfg = read_loop_config(loop_dir)
    if cfg.get("current_phase") == "execution_confirmed":
        # 验证 PRD 后过渡到 Phase 2
        prd = read_prd(loop_dir)
        problems = validate_prd(prd)
        if problems:
            yield error_msg, True
            return
        async for msg, last in run_mission_phase2(...):
            yield msg, last
        return

    # 自动修复 PRD 格式错误（最多 2 次）
    for attempt in range(1, _MAX_PRD_FIX_ATTEMPTS + 1):
        prd = read_prd(loop_dir)
        problems = validate_prd(prd)
        if not problems:
            return
        # 注入修正提示，让 agent 重写
        yield fix_msg, False
        ...
```

### 4.3 Phase 2: 迭代执行

```python
# mission_runner.py:362-480
async def run_mission_phase2(
    agent: Any,
    msgs: list,
    loop_dir: Path,
    max_iterations: int = 20,
    agent_id: str = None,
) -> AsyncGenerator[tuple[Msg, bool], None]:
    """执行 Phase 2（迭代循环，代码级控制）"""

    # 验证 PRD
    prd = read_prd(loop_dir)
    if not prd or validate_prd(prd):
        yield error_msg, True
        return

    # 禁用实现工具
    set_phase2_tool_restrictions(agent)

    try:
        for iteration in range(1, max_iterations + 1):
            # Agent 执行一次
            async for msg, last in stream_printing_messages(...):
                yield msg, last

            # 代码级完成检查
            prd = read_prd(loop_dir)
            stories = prd.get("userStories", [])

            if all(s.get("passes") for s in stories):
                # 全部通过
                yield completion_msg, True
                return

            # 注入继续消息
            msgs = [remaining_summary_msg]

    finally:
        restore_tools(agent)
```

### 4.4 工具限制机制

```python
# mission_runner.py:73-88
MISSION_IMPL_GROUP = "mission_impl"

# Phase 2 禁用的工具
IMPLEMENTATION_TOOLS = frozenset({
    "edit_file",
    "browser_use",
    "desktop_screenshot",
})

def set_phase2_tool_restrictions(agent: Any) -> None:
    """将实现工具移入专用组并禁用"""
    migrate_tools_to_group(agent)
    agent.toolkit.update_tool_groups([MISSION_IMPL_GROUP], active=False)

def restore_tools(agent: Any) -> None:
    """重新启用实现工具（清理/Phase 1）"""
    if MISSION_IMPL_GROUP in agent.toolkit.groups:
        agent.toolkit.update_tool_groups([MISSION_IMPL_GROUP], active=True)
```

### 4.5 Master Prompt 构建

```python
# prompts.py
def build_master_prompt(
    loop_dir: str,
    agent_id: str,
    max_iterations: int,
    verify_commands: str,
    git_context: dict[str, Any],
    workspace_dir: str,
) -> str:
    """构建 Phase 1 的 Master Prompt"""
    # 包含：
    # - 任务目录路径
    # - PRD schema 要求
    # - Git 上下文信息
    # - 验证命令（如果有）
    # - Phase 1/2 行为规范
```

---

## 5. 执行流程图

### 5.1 命令解析流程

```
用户输入 "/mission 实现用户认证"
    ↓
is_mission_command() → True
    ↓
_parse_mission_args() 解析参数
    ↓
handle_mission_command()
    ├── 子命令检测（status/list）→ 返回文本
    ├── 有效性检查（长度 < 5）→ 返回用法
    ├── 元查询拦截 → 返回提示
    └── 正常任务
        ├── create_loop_dir() 创建目录
        ├── write_task_md() 写入 task.md
        ├── detect_git_context() 异步检测 Git
        ├── write_loop_config() 写入配置
        └── 返回 {"mission_phase": 1, "loop_dir": ..., "max_iterations": 20}
            ↓
            Runner 检测到 mission_info，启动 Phase 1
```

### 5.2 Phase 1 流程

```
Phase 1: PRD 生成
    ↓
Agent 收到 full_prompt（包含 Master Prompt）
    ↓
Agent 探索代码库，生成 prd.json
    ↓
用户审查 PRD
    ↓
用户确认（或 agent 自动修正）
    ↓
写入 loop_config.json: current_phase = "execution_confirmed"
    ↓
validate_prd() 验证通过
    ↓
过渡到 Phase 2
```

### 5.3 Phase 2 流程

```
Phase 2: 迭代执行
    ↓
set_phase2_tool_restrictions() 禁用实现工具
    ↓
for iteration in range(1, max_iterations):
    ↓
Agent 作为控制器，运行一次
    ↓
    ↓  dispatch workers 执行 story
    ↓  dispatch verifiers 验证
    ↓  更新 prd.json: passes = true/false
    ↓
read_prd() 检查所有 passes
    ↓
全部通过 → Mission 完成
    ↓
达到 max_iterations → 终止，返回进度
```

---

## 6. 安全与限制

### 6.1 Phase 2 工具禁用

```python
# Phase 2 Master Agent 无法直接：
# - edit_file（必须通过 worker）
# - browser_use（必须通过 worker）
# - desktop_screenshot（必须通过 worker）

# 但仍可使用：
# - execute_shell_command（调度 worker）
# - write_file（更新 prd.json / progress.txt）
```

### 6.2 安全警告

```python
# handler.py:160-168
"""
⚠️ **Security Warning**:
- Worker agents bypass security guards (auto-disabled via --background)
- Sensitive operations (shell, file writes) execute without approval
- **Only use in trusted codebases**
"""
```

---

## 7. 配置参数

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| `--max-iterations` | 20 | 1-100 | Phase 2 最大迭代次数 |
| `--verify` | "" | 命令字符串 | 每个 story 的验证命令 |

---

## 8. 与 Runner 的集成

**源码**: `runner.py:529-592`

```python
# Runner Stage 5: Mission Mode 检测
mission_result = await maybe_handle_mission_command(
    query=query,
    msgs=msgs,
    workspace_dir=_ws,
    agent_id=self.agent_id,
    rewrite_fn=self._rewrite_last_message_text,
    session_id=session_id,
)

if isinstance(mission_result, dict):
    mission_info = mission_result
    # 绕过工具守卫
    # auto-inject context reminder
```

---

## 9. 常见问题

### Q1: 如何中断 Mission？

**A**: 发送 `/stop` 命令或在 Phase 2 中达到 `max_iterations`。

### Q2: Phase 2 中 agent 无法编辑文件？

**A**: 这是设计行为。Master Agent 作为控制器，所有实现工作通过 `qwenpaw agents chat --background` 分发给 worker。

### Q3: PRD 格式错误怎么办？

**A**: Phase 1 会自动尝试修正（最多 2 次）。如果仍失败，用户需要手动修正 `prd.json`。

---

## 10. 相关文件索引

| 组件 | 文件路径 |
|------|----------|
| Mission Handler | `src/qwenpaw/agents/mission/handler.py` |
| Mission Runner | `src/qwenpaw/agents/mission/mission_runner.py` |
| Mission State | `src/qwenpaw/agents/mission/state.py` |
| Mission Prompts | `src/qwenpaw/agents/mission/prompts.py` |
| Runner 集成 | `src/qwenpaw/app/runner/runner.py:529-592` |

---

## 11. 练习题

### 练习 1: 创建 Mission 任务

**目标**: 使用 `/mission` 命令创建一个简单的任务。

```bash
# 练习: 在 QwenPaw 中执行以下命令
/mission 为项目添加 README.md 文件

# 预期行为:
# 1. Phase 1 启动，Agent 生成 PRD
# 2. 用户审查 prd.json
# 3. 用户确认后进入 Phase 2
# 4. Agent 执行任务
```

### 练习 2: 分析 PRD 结构

**目标**: 理解 Mission Mode 的 PRD (Product Requirements Document) 格式。

```python
# 练习: 编写一个验证 PRD 格式的程序

prd_example = {
    "userStories": [
        {
            "id": "story-1",
            "title": "添加 README",
            "description": "为项目创建一个 README.md 文件",
            "acceptanceCriteria": [
                "README.md 包含项目名称",
                "README.md 包含安装说明"
            ],
            "priority": "high",
            "passes": False
        }
    ]
}

# 验证函数
def validate_prd(prd: dict) -> list[str]:
    """验证 PRD 格式是否正确"""
    problems = []
    required_fields = {"userStories"}
    story_fields = {"id", "title", "description", "acceptanceCriteria", "priority", "passes"}

    # 检查顶层字段
    for field in required_fields:
        if field not in prd:
            problems.append(f"Missing required field: {field}")

    # 检查每个 story
    for i, story in enumerate(prd.get("userStories", [])):
        for field in story_fields:
            if field not in story:
                problems.append(f"Story {i} missing field: {field}")

    return problems

print(validate_prd(prd_example))
```

### 练习 3: 实现工具限制

**目标**: 理解 Phase 2 中的工具限制机制。

```python
# 练习: 模拟 Phase 2 的工具限制

IMPLEMENTATION_TOOLS = frozenset({
    "edit_file",
    "browser_use",
    "desktop_screenshot"
})

def check_tool_available(tool_name: str, phase: int) -> bool:
    """检查工具在指定阶段是否可用"""
    if phase == 1:
        # Phase 1: 所有工具可用
        return True
    elif phase == 2:
        # Phase 2: 实现工具被禁用
        return tool_name not in IMPLEMENTATION_TOOLS
    return False

# 测试
print(check_tool_available("execute_shell_command", 1))  # True
print(check_tool_available("edit_file", 1))  # True
print(check_tool_available("edit_file", 2))  # False
print(check_tool_available("execute_shell_command", 2))  # True
```

### 练习 4: Git 上下文检测

**目标**: 实现异步 Git 上下文检测。

```python
# 练习: 实现 Git 上下文检测（简化版）

import asyncio
import shutil
from pathlib import Path
from typing import Optional

async def detect_git_context(workspace_dir: Path) -> dict:
    """检测 Git 上下文（简化实现）"""
    ctx = {
        "git_installed": False,
        "is_git_repo": False,
        "default_branch": "main",
        "current_branch": "",
        "repo_root": ""
    }

    # 检查 git 是否安装
    if shutil.which("git") is None:
        return ctx

    ctx["git_installed"] = True

    # 使用 asyncio 创建子进程执行 git 命令
    proc = await asyncio.create_subprocess_exec(
        "git", "rev-parse", "--show-toplevel",
        cwd=str(workspace_dir),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await proc.communicate()

    if proc.returncode == 0:
        ctx["is_git_repo"] = True
        ctx["repo_root"] = stdout.decode().strip()

    return ctx

# 测试
async def main():
    ctx = await detect_git_context(Path("."))
    print(f"Git installed: {ctx['git_installed']}")
    print(f"Is git repo: {ctx['is_git_repo']}")
    print(f"Repo root: {ctx['repo_root']}")

asyncio.run(main())
```

---

## 12. 如果你来自 Java...

### Java 开发者对照表

| Java 概念 | QwenPaw Mission Mode 实现 | 说明 |
|-----------|---------------------------|------|
| `ExecutorService` | Phase 1/2 两阶段执行 | 任务分解与执行分离 |
| `Future` / `CompletableFuture` | PRD + worker 模式 | 异步任务与结果验证 |
| `ThreadPoolExecutor` | Master Agent + workers | 控制器 + 执行器模式 |
| `CountDownLatch` | `passes` 字段 | 任务完成计数 |
| `ScheduledExecutorService` | `max_iterations` | 迭代次数限制 |
| `ForkJoinPool` | Mission Mode 架构 | 分而治之的任务执行 |

### 关键设计模式对比

**1. 两阶段执行模型**

```java
// Java: 分阶段任务处理
ExecutorService executor = Executors.newFixedThreadPool(2);
Future<PRD> phase1Future = executor.submit(() -> generatePRD(task));
PRD prd = phase1Future.get();
executor.shutdown();
```

```python
# Python: Mission Mode 两阶段执行
# Phase 1: Agent 生成 PRD
async for msg, last in run_mission_phase1(agent, msgs, loop_dir):
    yield msg, last

# Phase 2: 迭代执行
async for msg, last in run_mission_phase2(agent, msgs, loop_dir):
    yield msg, last
```

**2. 控制器-执行器模式**

```java
// Java: ExecutorService + Runnable
class MasterAgent {
    void execute(Task task) {
        for (Story story : task.getStories()) {
            executor.submit(new Worker(story));
        }
    }
}
```

```python
# Python: Master Agent + workers
# Master Agent 通过 shell 分发任务给 worker
worker_cmd = f"qwenpaw agents chat --background --task '{story}'"
await run_command_async(worker_cmd.split())
```

**3. 结果验证模式**

```java
// Java: Callable + Future 验证
Future<Boolean> verifyFuture = executor.submit(() -> {
    return verifier.verify(story);
});
boolean passes = verifyFuture.get(timeout, TimeUnit.SECONDS);
```

```python
# Python: verifier 执行后更新 prd.json
# 每个 story 有独立的 verifier
# passes 字段由 verifier 更新
stories = prd.get("userStories", [])
if all(s.get("passes") for s in stories):
    yield completion_msg, True
```

### Java 开发者注意事项

1. **PRD 即契约**: PRD (Product Requirements Document) 类似于 Java 中的接口定义，定义了任务的契约。

2. **Worker 是无状态的**: Worker agent 与 Java 的 `Runnable` 类似，每次执行都是独立的任务。

3. **工具限制是安全边界**: Phase 2 禁用的工具类似于 Java 中的安全管理器限制。

4. **文件状态持久化**: Mission Mode 使用文件系统持久化状态，类似于 Java 的持久化队列。

5. **异步迭代循环**: Phase 2 的迭代模型类似于 Java 的 `while(!isComplete() && hasMoreIterations())` 循环。
