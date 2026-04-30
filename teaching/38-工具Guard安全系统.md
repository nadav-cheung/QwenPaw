# 工具 Guard 安全系统

## 概述

ToolGuard 是 QwenPaw 的三层安全守护系统，通过 **ToolGuardMixin** 拦截智能体的工具调用，实现文件路径保护、危险命令检测和 shell 混淆检测。

---

## 1. ToolGuardMixin — 三层守护架构

源码路径：`src/qwenpaw/agents/tool_guard_mixin.py:68`

### 1.1 类定义

```python
# src/qwenpaw/agents/tool_guard_mixin.py:68
class ToolGuardMixin:
    """Mixin，添加工具守护拦截到 ReActAgent。

    在运行时此类始终通过 MRO 与
    ``agentscope.agent.ReActAgent`` 组合，
    因此 super()._acting 和 super()._reasoning
    解析为具体的智能体方法。
    """
```

### 1.2 MRO 集成

```python
# src/qwenpaw/agents/react_agent.py:76
class QwenPawAgent(ToolGuardMixin, ReActAgent):
    """QwenPaw 智能体，集成工具、技能和记忆管理。

    MRO 说明
    ~~~~~~~~
    ``ToolGuardMixin`` 通过 Python MRO 覆盖 ``_acting`` 和 ``_reasoning``：
    QwenPawAgent → ToolGuardMixin → ReActAgent
    """
```

---

## 2. 三层守护架构

### 2.0 完整模块结构

```
┌─────────────────────────────────────────────────────────────────┐
│                        QwenPawAgent                              │
│                  (react_agent.py:76)                            │
│           ToolGuardMixin + ReActAgent (MRO组合)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ToolGuardMixin._acting()                      │
│               (tool_guard_mixin.py:291)                        │
│                                                                  │
│  决策流程:                                                        │
│  1. is_denied() → auto_denied                                  │
│  2. 预批准检查 → preapproved                                    │
│  3. engine.guard() → findings                                  │
│  4. needs_approval → 等待用户审批                               │
│  5. None → 正常执行                                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ToolGuardEngine                             │
│                  (engine.py:60-188)                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  guard() 方法核心逻辑 (engine.py:172-210)                │   │
│  │                                                          │   │
│  │  for guardian in guardians:                             │   │
│  │      findings = guardian.guard(tool_name, params)      │   │
│  │      result.findings.extend(findings)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ FilePath      │   │ RuleBased     │   │ ShellEvasion  │
│ Guardian      │   │ Guardian      │   │ Guardian      │
│               │   │               │   │               │
│ always_run=T  │   │ YAML正则规则  │   │ 混淆检测      │
│               │   │               │   │               │
│ file_guardian │   │ rule_guardian │   │ shell_evasion │
│ .py:184      │   │ .py:559      │   │ _guardian:499 │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 2.1 架构概览

```
_tool_guard_engine
  │
  ├── Layer 1: FilePathToolGuardian (always_run=True)
  │     保护敏感文件路径
  │
  ├── Layer 2: RuleBasedToolGuardian
  │     YAML 正则规则匹配
  │
  └── Layer 3: ShellEvasionGuardian
        检测混淆/逃避技术
```

### 2.2 Layer 1: FilePathToolGuardian

源码路径：`src/qwenpaw/security/tool_guard/guardians/file_guardian.py:184-364`

#### 关键常量

```python
# file_guardian.py:19-28
_TOOL_FILE_PARAMS: dict[str, tuple[str, ...]] = {
    "read_file": ("file_path",),
    "write_file": ("file_path",),
    "edit_file": ("file_path",),
    "append_file": ("file_path",),
    "send_file_to_user": ("file_path",),
    "view_text_file": ("file_path", "path"),
    "write_text_file": ("file_path", "path"),
}
```

#### 核心 guard 方法

```python
# file_guardian.py:313-364
def guard(self, tool_name: str, params: dict[str, Any]) -> list[GuardFinding]:
    if not self._enabled:
        return []
    if not self._sensitive_files and not self._sensitive_dirs:
        return []

    findings: list[GuardFinding] = []

    # Shell命令：从命令字符串提取路径
    if tool_name == "execute_shell_command":
        command = params.get("command")
        for raw_path in _extract_paths_from_shell_command(command):
            self._check_value(tool_name, "command", raw_path, findings, snippet=command)
        return findings

    # 已知文件工具：只检查文件路径参数
    known_params = _TOOL_FILE_PARAMS.get(tool_name)
    if known_params:
        for param_name in known_params:
            raw_value = params.get(param_name)
            self._check_value(tool_name, param_name, raw_value, findings)
        return findings

    # 其他工具：扫描所有看起来像路径的字符串参数
    for param_name, param_value in params.items():
        if not _looks_like_path_token(param_value):
            continue
        self._check_value(tool_name, param_name, param_value, findings)

    return findings
```

#### 从Shell命令提取路径

```python
# file_guardian.py:134-181
def _extract_paths_from_shell_command(command: str) -> list[str]:
    tokens = shlex.split(command, posix=True)
    candidates: list[str] = []
    for token in tokens:
        # 处理重定向操作符: >out.txt, 2>err.log
        if token.startswith(_SHELL_REDIRECT_OPERATORS):
            candidates.append(token[1:])
        # 检查是否像路径
        if _looks_like_path_token(token):
            candidates.append(token)
    return deduped  # 去重
```

**保护路径**：
- `.qwenpaw.secret`
- `.copaw.secret`
- 配置的敏感路径

**扫描范围**：
```python
# 扫描文件工具的路径参数
if tool_name in ("read_file", "write_file", "edit_file", ...):
    path = tool_input.get("path")

# 从 shell 命令提取路径
# 扫描所有其他字符串参数中的路径类标记
```

### 2.3 Layer 2: RuleBasedToolGuardian

源码路径：`src/qwenpaw/security/tool_guard/guardians/rule_guardian.py:559-757`

#### GuardRule 类

```python
# rule_guardian.py:331-424
class GuardRule:
    __slots__ = (
        "id", "tools", "params", "category", "severity",
        "patterns", "exclude_patterns", "description", "remediation",
        "compiled_patterns", "compiled_exclude_patterns",
    )

    def __init__(self, rule_data: dict[str, Any]) -> None:
        self.id: str = rule_data["id"]
        self.tools: list[str] = rule_data.get("tools", [])
        self.params: list[str] = rule_data.get("params", [])
        self.category = GuardThreatCategory(rule_data["category"])
        self.severity = GuardSeverity(rule_data["severity"])
        self.patterns: list[str] = rule_data.get("patterns", [])
        # 预编译正则表达式
        self.compiled_patterns: list[re.Pattern[str]] = [
            re.compile(pat, re.IGNORECASE) for pat in self.patterns
        ]

    def applies_to_tool(self, tool_name: str) -> bool: ...
    def applies_to_param(self, param_name: str) -> bool: ...
    def match(self, value: str) -> tuple[re.Match[str] | None, str | None]: ...
```

#### 危险规则（来自 `dangerous_shell_commands.yaml`）：

| 规则 ID | 危险命令 | 严重性 |
|---------|----------|--------|
| `TOOL_CMD_DANGEROUS_RM` | `rm -rf`, `del`, `Remove-Item` | HIGH |
| `TOOL_CMD_FS_DESTRUCTION` | `mkfs`, `dd` 到块设备 | CRITICAL |
| `TOOL_CMD_PIPE_TO_SHELL` | `curl \| bash` | CRITICAL |
| `TOOL_CMD_REVERSE_SHELL` | `/dev/tcp`, `nc -e`, `socat` | CRITICAL |
| `TOOL_CMD_PRIVILEGE_ESCALATION` | `sudo`, `su`, `pkexec` | CRITICAL |
| `TOOL_CMD_SYSTEM_REBOOT` | `reboot`, `shutdown` | CRITICAL |
| `TOOL_CMD_DOS_FORK_BOMB` | fork 炸弹 | CRITICAL |

### 2.4 Layer 3: ShellEvasionGuardian

源码路径：`src/qwenpaw/security/tool_guard/guardians/shell_evasion_guardian.py:499-545`

#### Quote 状态追踪

```python
# shell_evasion_guardian.py:61-91
class _QuoteState:
    """Tracks shell quoting context character-by-character."""
    __slots__ = ("in_single", "in_double", "escaped")

    def feed(self, char: str) -> None:
        if self.escaped:
            self.escaped = False
            return
        if char == "\\" and not self.in_single:
            self.escaped = True
            return
        if char == "'" and not self.in_double:
            self.in_single = not self.in_single
            return
        if char == '"' and not self.in_single:
            self.in_double = not self.in_double
```

**检测函数**：

| 函数 | 检测技术 |
|------|----------|
| `_check_command_substitution` | `$()`, backticks, `<()` |
| `_check_obfuscated_flags` | ANSI-C quoting `$'...'` |
| `_check_backslash_escaped_whitespace` | `echo\ test` |
| `_check_backslash_escaped_operators` | `\;`, `\|`, `\&` |
| `_check_newlines` | 隐藏命令的换行符 |
| `_check_comment_quote_desync` | 注释内的引号字符 |

---

## 3. 工具验证流程

### 3.1 完整执行流程图

```
用户/Agent发起工具调用
        │
        ▼
┌───────────────────────────────────┐
│  ToolGuardMixin._acting()        │  tool_guard_mixin.py:291
│                                   │
│  tool_call = {name, arguments}   │
└──────────────────┬────────────────┘
                   │
                   ▼
┌───────────────────────────────────┐
│  _decide_guard_action()          │  tool_guard_mixin.py:346
│                                   │
│  1. 检查 denied_tools → 拒绝      │
│  2. 检查 preapproved → 放行      │
│  3. 运行 ToolGuardEngine.guard() │
│  4. 判断是否需要审批              │
└──────────────────┬────────────────┘
                   │
        ┌──────────┼──────────┐
        │          │          │
        ▼          ▼          ▼
   auto_denied  needs_approval  None
        │          │          │
        │          │          ▼
        │          │    super()._acting()
        │          │    执行实际工具
        │          │
        ▼          ▼
   返回拒绝      等待用户审批
   消息         (approval.py)
                    │
          ┌─────────┼─────────┐
          ▼         ▼         ▼
      APPROVED   DENIED   TIMEOUT
          │         │         │
          ▼         ▼         ▼
    执行工具    返回拒绝   返回超时
```

### 3.2 _acting 拦截

```python
# src/qwenpaw/agents/tool_guard_mixin.py:291
async def _acting(self, tool_call) -> dict | None:
    """拦截敏感工具调用在执行前。

    1. 如果工具在 denied_tools 中，无条件自动拒绝
    2. 如果工具在 guarded scope，检查预审批
    3. 对于非 guarded 工具，仅运行 always_run 守护
    4. 如果有发现，进入审批流程
    5. 否则委托给 super()._acting
    """
```

### 3.3 _decide_guard_action

```python
# src/qwenpaw/agents/tool_guard_mixin.py:346
async def _decide_guard_action(self, tool_call) -> "_GuardAction | None":
    # Layer 1: 显式拒绝的工具
    if engine.is_denied(tool_name):
        return _GuardAction("auto_denied", ...)

    # Layer 2: 预审批检查
    if guarded and await self._consume_preapproval(tool_name, tool_input):
        return _GuardAction("preapproved", ...)

    # Layer 3: 运行所有守护
    guard_result = engine.guard(tool_name, tool_input, ...)
    if guard_result.findings:
        if self._should_require_approval():
            return _GuardAction("needs_approval", ...)
    return None
```

---

## 4. 默认配置

### 4.1 默认 guarded 工具

```python
# src/qwenpaw/security/tool_guard/utils.py:19
_DEFAULT_GUARDED_TOOLS = frozenset({
    "execute_shell_command",
    "read_file",
    "write_file",
    "edit_file",
    "append_file",
    "send_file_to_user",
    "view_text_file",
    "write_text_file",
})
```

### 4.2 优先级

```python
# src/qwenpaw/security/tool_guard/utils.py:99
# 优先级：
# 1. constructor-provided user_defined
# 2. QWENPAW_TOOL_GUARD_DENIED_TOOLS 环境变量
# 3. config.json → security.tool_guard.denied_tools
# 4. 内置默认（空）
```

### 4.3 resolve_denied_tools 解析逻辑

源码路径：`src/qwenpaw/security/tool_guard/utils.py:99`

```python
# src/qwenpaw/security/tool_guard/utils.py:99
def resolve_denied_tools(
    user_defined: set[str] | list[str] | tuple[str, ...] | None = None,
) -> set[str]:
    """解析无条件拒绝的工具集合。

    优先级：
    1. constructor-provided user_defined
    2. QWENPAW_TOOL_GUARD_DENIED_TOOLS 环境变量（逗号分隔）
    3. config.json → security.tool_guard.denied_tools
    4. 内置默认（空集合）
    """
    if user_defined is not None:
        return set(user_defined)

    raw = EnvVarLoader.get_str("QWENPAW_TOOL_GUARD_DENIED_TOOLS") or None
    if raw is not None:
        return {t.strip() for t in raw.split(",") if t.strip()}

    cfg = _load_config_tool_guard()
    if cfg is not None and cfg.denied_tools:
        return set(cfg.denied_tools)

    return set()
```

### 4.4 log_findings 结构化日志

源码路径：`src/qwenpaw/security/tool_guard/utils.py:129`

```python
# src/qwenpaw/security/tool_guard/utils.py:129
def log_findings(tool_name: str, result: "ToolGuardResult") -> None:
    """为每个发现发出结构化日志。"""
    from .models import GuardSeverity

    _HIGH_SEVERITIES = (GuardSeverity.CRITICAL, GuardSeverity.HIGH)

    for finding in result.findings:
        if finding.severity in _HIGH_SEVERITIES:
            log_fn = logger.warning
        else:
            log_fn = logger.info

        log_fn(
            "[TOOL GUARD] %s | tool=%s param=%s rule=%s | %s | matched=%r",
            finding.severity.value,
            tool_name,
            finding.param_name or "*",
            finding.rule_id,
            finding.description,
            finding.matched_value,
        )

    summary_fn = (
        logger.warning
        if result.max_severity in _HIGH_SEVERITIES
        else logger.info
    )
    summary_fn(
        "[TOOL GUARD] Summary for tool '%s': %d finding(s), "
        "max_severity=%s, duration=%.3fs",
        tool_name,
        result.findings_count,
        result.max_severity.value,
        result.guard_duration_seconds,
    )
```

**日志输出示例**：
```
[TOOL GUARD] HIGH | tool=execute_shell_command param=command rule=TOOL_CMD_DANGEROUS_RM | Detected dangerous rm pattern | matched='rm -rf /'
[TOOL GUARD] Summary for tool 'execute_shell_command': 1 finding(s), max_severity=HIGH, duration=0.012s
```

---

## 5. 设计模式

### 5.1 always_run 守护

```python
# 即使工具不在 guarded 列表，也运行 always_run 守护
guardians = (
    [g for g in self._guardians if g.always_run]
    if only_always_run
    else self._guardians
)
```

### 5.2 审批流程

```
工具调用
    ↓
ToolGuardMixin._acting()
    ↓
_decide_guard_action()
    ↓
├── auto_denied → 拒绝执行
├── preapproved → 直接执行
├── needs_approval → 暂停等待用户审批
└── None → 正常执行
```

---

## 6. 审批决策枚举

源码路径：`src/qwenpaw/security/tool_guard/approval.py:16`

```python
# src/qwenpaw/security/tool_guard/approval.py:16
class ApprovalDecision(str, Enum):
    APPROVED = "approved"    # 用户批准
    DENIED = "denied"      # 用户拒绝
    TIMEOUT = "timeout"     # 审批超时（默认10分钟）
```

### 审批格式化函数

```python
# src/qwenpaw/security/tool_guard/approval.py:24
def format_findings_summary(result, *, max_items=3) -> str:
    """将发现格式化为简洁的 Markdown 摘要"""
```

---

## 7. 审批工作流

### 7.1 等待审批时 _reasoning 暂停

```python
# src/qwenpaw/agents/tool_guard_mixin.py:662
async def _reasoning(self, world_state: WorldState) -> str:
    """重写 ReActAgent._reasoning，暂停工具调用推理直到审批。"""
    while True:
        if self._guard_awaiting_approval:
            # 等待用户审批...
            await self._guard_approval_event.wait()
        ...
```

### 7.2 审批超时机制

```python
# src/qwenpaw/security/tool_guard/approval.py:16
class ApprovalDecision(str, Enum):
    APPROVED = "approved"    # 用户批准
    DENIED = "denied"       # 用户拒绝
    TIMEOUT = "timeout"     # 审批超时（默认10分钟）
```

---

## 8. 数据模型

源码路径：`src/qwenpaw/security/tool_guard/models.py`

### GuardSeverity 枚举 (line 30)

| 等级 | 说明 |
|------|------|
| `CRITICAL` | 严重威胁，立即拒绝 |
| `HIGH` | 高威胁，需要审批 |
| `MEDIUM` | 中威胁，警告后可通过 |
| `LOW` | 低威胁，警告 |
| `INFO` | 信息级别 |
| `SAFE` | 安全 |

### GuardThreatCategory 枚举 (line 45)

| 类别 | 说明 |
|------|------|
| `COMMAND_INJECTION` | 命令注入 |
| `PATH_TRAVERSAL` | 路径遍历 |
| `SENSITIVE_FILE_ACCESS` | 敏感文件访问 |
| `CREDENTIAL_EXPOSURE` | 凭证泄露 |
| `PROMPT_INJECTION` | 提示词注入 |

### GuardFinding 数据类 (line 75)

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `str` | 唯一标识 |
| `rule_id` | `str` | 触发的规则ID |
| `category` | `GuardThreatCategory` | 威胁类别 |
| `severity` | `GuardSeverity` | 严重等级 |
| `title` | `str` | 标题 |
| `description` | `str` | 描述 |
| `tool_name` | `str` | 工具名称 |
| `param_name` | `str` | 参数名称 |
| `matched_value` | `str` | 匹配的值 |
| `remediation` | `str` | 修复建议 |

### ToolGuardResult 数据类 (line 115)

```python
# models.py:101-151
@dataclass
class ToolGuardResult:
    tool_name: str
    params: dict[str, Any]
    findings: list[GuardFinding] = field(default_factory=list)
    guardians_used: list[str] = field(default_factory=list)
    guard_duration_seconds: float = 0.0

    @property
    def is_safe(self) -> bool:
        """无 CRITICAL/HIGH 发现时为 True"""
        return not any(
            f.severity in (GuardSeverity.CRITICAL, GuardSeverity.HIGH)
            for f in self.findings
        )

    @property
    def max_severity(self) -> GuardSeverity:
        """返回最高严重等级"""
        ...

    @property
    def findings_count(self) -> int:
        return len(self.findings)
```

---

## 9. 应用场景

### 9.1 敏感文件保护

**场景**：防止智能体读取 `.qwenpaw.secret` 等敏感文件。

**实现**：
- `FilePathToolGuardian` 扫描所有文件操作
- 检测到访问敏感路径时返回 `CRITICAL` 发现
- 工具调用被自动拒绝

### 9.2 危险命令拦截

**场景**：防止执行 `rm -rf /` 等危险命令。

**实现**：
- `RuleBasedToolGuardian` 加载 `dangerous_shell_commands.yaml`
- 检测到危险模式时返回 `CRITICAL/HIGH` 发现
- 根据配置自动拒绝或进入审批流程

### 9.3 Shell 混淆检测

**场景**：防止通过混淆技术绕过命令检测。

**检测的混淆技术**：
- `$()` 命令替换
- ANSI-C quoting (`$'...'`)
- 反斜杠转义 (`echo\ test`)
- 隐藏在注释中

### 9.4 自定义规则

**场景**：企业需要添加自定义安全规则。

**实现**：
1. 在 `dangerous_shell_commands.yaml` 中添加规则：

```yaml
- id: CUSTOM_RULE
  tools: ["execute_shell_command"]
  params: ["command"]
  category: COMMAND_INJECTION
  severity: HIGH
  patterns:
    - "custom_dangerous_pattern"
  description: "Custom dangerous pattern"
  remediation: "Use safe alternative"
```

2. 热重载使规则立即生效

---

## 10. 最佳实践

### 10.1 always_run 守护

`FilePathToolGuardian` 设置 `always_run=True`，确保即使非 guarded 工具也受保护：

```python
# 即使不在 guarded 列表，也保护敏感文件
guardians = (
    [g for g in self._guardians if g.always_run]
    if only_always_run
    else self._guardians
)
```

### 10.2 规则编写规范

```yaml
# 好的实践：明确指定工具和参数
- id: EFFECTIVE_RULE
  tools: ["execute_shell_command"]  # 明确指定
  params: ["command"]               # 明确指定
  patterns:
    - "dangerous_pattern"
```

### 10.3 审批超时配置

```python
# 合理设置超时
class ApprovalDecision(str, Enum):
    APPROVED = "approved"
    DENIED = "denied"
    TIMEOUT = "timeout"  # 默认10分钟
```

### 10.4 错误处理

```python
# 好的实践：异常时拒绝（安全优先）
except Exception:
    logger.exception("guard check failed")
    return [GuardFinding(...)]  # 返回拒绝
```

---

## 11. 常见问题

### Q1: 合法操作被拦截？

**原因**：规则过于严格或误匹配。

**解决方案**：
1. 检查触发的规则 ID
2. 调整规则的 `exclude_patterns`
3. 将该操作添加到 `preapproved_tools`

### Q2: 规则未生效？

**排查**：
1. 确认 YAML 格式正确
2. 检查规则是否加载（查看日志）
3. 确认热重载已触发

### Q3: 审批流程卡住？

**排查**：
1. 检查 `_guard_approval_event` 是否正确设置
2. 确认审批超时配置
3. 查看是否有死锁

### Q4: 如何禁用 ToolGuard？

**方式**：
1. 设置环境变量 `QWENPAW_TOOL_GUARD_ENABLED=false`
2. 在配置中设置 `security.tool_guard.enabled: false`

### Q5: 多层守护冲突？

**场景**：不同守护返回不同结果。

**说明**：`ToolGuardEngine.guard()` 汇总所有守护结果，最终根据最高严重性决定。

---

## ★ Insight ─────────────────────────────────────
**三层守护的协作设计**：`always_run=True` 的 `FilePathToolGuardian` 每次都会运行，即使工具不在 `guarded_tools` 列表中。这意味着敏感文件保护永远不会漏过，哪怕管理员只配置了 `denied_tools` 黑名单。

**审批不是终点**：当用户批准一个工具调用后，`ToolGuardMixin` 会消费 `preapproval token`。但这个 token 只对**完全相同**的参数有效（`consume_approval` 会比较 `tool_params`），防止 "rm foo.txt" 的审批被用于 "rm -rf /"。

**ShellEvasionGuardian 的 QuoteState**：这是一个状态机，逐字符跟踪单引号、双引号、反斜杠转义状态。只有在引号**之外**检测到的 `$()` 才算命令替换，这是它能区分 `echo '$foo'`（无害）和 `echo $(whoami)`（危险）的原因。
─────────────────────────────────────────────────

## 12. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| ToolGuardMixin | `src/qwenpaw/agents/tool_guard_mixin.py:68` |
| _acting 拦截 | `src/qwenpaw/agents/tool_guard_mixin.py:291` |
| _decide_guard_action | `src/qwenpaw/agents/tool_guard_mixin.py:346` |
| ToolGuardEngine | `src/qwenpaw/security/tool_guard/engine.py:54` |
| FilePathToolGuardian | `src/qwenpaw/security/tool_guard/guardians/file_guardian.py:184` |
| RuleBasedToolGuardian | `src/qwenpaw/security/tool_guard/guardians/rule_guardian.py:559` |
| ShellEvasionGuardian | `src/qwenpaw/security/tool_guard/guardians/shell_evasion_guardian.py:499` |
| ApprovalDecision | `src/qwenpaw/security/tool_guard/approval.py:16` |
| 数据模型 | `src/qwenpaw/security/tool_guard/models.py` |
| 危险规则 | `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml` |
| QwenPawAgent MRO | `src/qwenpaw/agents/react_agent.py:76` |
