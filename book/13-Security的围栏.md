# 第 13 章：Security 的围栏——拦截器与规则引擎

```
卷二：理解设计
[9] 源码地图 -> [10] Agent身世 -> [11] Provider棋局 -> [12] Channel变装 -> [13] Security围栏 <- you are here
```

第 7 章我们跟工具调用走过一遍，看到了 ToolGuardMixin 在 `_acting()` 中做安全检查。这一章深入 Security 系统的设计——ToolGuardEngine 怎么调度三个 Guardian？YAML 规则怎么检测危险命令？Shell 混淆检测用的什么算法？密钥怎么加密存储？技能安装前怎么扫描安全风险？

---

## 问题

LLM 可能生成危险的 Shell 命令（`rm -rf /`），可能读取敏感文件（`/etc/shadow`），可能被注入在技能包里植入恶意代码。QwenPaw 怎么在不限制 Agent 能力的前提下，防御这些安全风险？

## 术语其实很简单

> **术语：Guardian（守卫）**
> 想象机场安检——行李过 X 光机（规则守卫），液体单独检查（路径守卫），可疑行为人工复查（混淆检测守卫）。每个 Guardian 是一类安全检查，独立运行，各司其职。

> **术语：YAML 规则（YAML Rules）**
> 想象一份黑名单——写着"禁止携带打火机、刀具、易燃物"。YAML 规则就是安全检查的"黑名单"——用正则表达式定义什么模式是危险的。新增检查不需要改代码，只需加一条 YAML 规则。

## 探索

### Security 系统的三个防线

```
防线一：工具调用守卫（Tool Guard）
  在工具执行前拦截——第 7 章讲过的 ToolGuardMixin
  检查：LLM 要执行的操作是否安全？

防线二：密钥加密存储（Secret Store）
  在配置读写时保护——Fernet 加密 API Key
  检查：敏感信息是否加密存储？

防线三：技能安全扫描（Skill Scanner）
  在技能安装时扫描——正则规则匹配恶意代码
  检查：第三方技能包是否包含恶意代码？
```

### ToolGuardEngine——三个 Guardian 的调度员

`ToolGuardEngine` 是工具安全检查的核心，它调度三个 Guardian：

```python
class ToolGuardEngine:
    def __init__(self, guardians=None, *, enabled=None):
        self._guardians = guardians or self._default_guardians()

    @staticmethod
    def _default_guardians():
        return [
            FilePathToolGuardian(),     # 检查敏感文件路径
            RuleBasedToolGuardian(),     # YAML 正则规则匹配
            ShellEvasionGuardian(),      # Shell 命令混淆检测
        ]
```

`guard()` 方法遍历所有 Guardian，收集检查结果：

```python
def guard(self, tool_name, params, *, only_always_run=False):
    findings = []
    for g in self._guardians:
        if only_always_run and not g.always_run:
            continue
        if not g.applies_to_tool(tool_name):
            continue
        findings.extend(g.guard(tool_name, params))
    return ToolGuardResult(findings=findings)
```

`ToolGuardResult.is_safe` 检查是否有 CRITICAL 或 HIGH 级别的发现。如果 `is_safe` 为 False，工具调用被拦截。

### Guardian 一：RuleBasedToolGuardian——YAML 规则引擎

`RuleBasedToolGuardian` 从 YAML 文件加载正则规则：

```yaml
# rules/dangerous_shell_commands.yaml
- id: TOOL_CMD_DANGEROUS_RM
  tools: [execute_shell_command]    # 只检查 Shell 工具
  params: [command]                  # 只检查 command 参数
  category: command_injection
  severity: HIGH
  patterns:
    - "\\brm\\b"                    # 匹配 rm 命令
    - "\\bdel\\b"                    # 匹配 del 命令
  exclude_patterns:
    - "^\\s*#"                       # 注释行排除
  description: "危险的删除命令"
  remediation: "请确认删除目标在工作区内"
```

规则引擎的匹配流程：

```
1. 过滤：rule.applies_to_tool(tool_name)?
2. 过滤：rule.applies_to_param(param_name)?
3. 匹配：rule.match(value) -> 正则搜索
4. 排除：exclude_patterns 排除误报
5. 汇总：收集所有匹配的 GuardFinding
```

18 条内置规则覆盖：rm/mv、文件系统破坏、fork 炸弹、管道注入、反向 Shell、权限篡改、进程杀戮、特权提升等。

特殊处理：`TOOL_CMD_DANGEROUS_RM` 规则不仅检查正则匹配，还会用 `_check_rm_targets_outside_workspace()` 验证删除目标是否在工作区外——工作区内允许删除，工作区外必须审批。

### Guardian 二：FilePathToolGuardian——敏感路径检查

`FilePathToolGuardian` 是唯一设置了 `always_run=True` 的 Guardian——即使工具不在 `guarded_tools` 列表中，它也始终运行。

检查策略分三种：

```python
# 工具到参数的映射
_TOOL_FILE_PARAMS = {
    "read_file": ("file_path",),
    "write_file": ("file_path",),
    "edit_file": ("file_path",),
    "execute_shell_command": None,  # 特殊处理
    # ... 其他文件工具
}
```

**文件工具**：直接检查映射的参数值是否指向敏感路径。

**Shell 命令**：用 `_extract_paths_from_shell_command()` 从命令字符串中提取路径——处理重定向（`> out.txt`）、管道、参数中的路径。

**其他工具**：扫描所有字符串参数，用 `_looks_like_path_token()` 启发式判断是否是路径。

敏感路径配置：
```python
# 默认敏感目录
_sensitive_dirs = {
    "/etc", "/root", "/var/log",
    "~/.ssh", "~/.gnupg",
    "~/.qwenpaw.secret/",  # QwenPaw 密钥目录
}
```

用户可以通过 `config.json` 的 `security.file_guard.sensitive_files` 添加自定义敏感路径。

### Guardian 三：ShellEvasionGuardian——Shell 混淆检测

`ShellEvasionGuardian` 是最有技术含量的 Guardian。它检测 LLM 试图通过 Shell 技巧绕过安全检查的行为。

核心是一个 `_QuoteState` 引号状态机——逐字符跟踪当前是在单引号内、双引号内、还是无引号状态：

```python
class _QuoteState:
    in_single: bool = False
    in_double: bool = False
    escaped: bool = False
```

7 个检查函数按顺序执行：

| 检查 | 检测什么 | 示例 |
|---|---|---|
| `_check_command_substitution` | 命令替换 | `$(whoami)`、反引号、进程替换 `<()` |
| `_check_obfuscated_flags` | 混淆标志 | `$'\x2d\x72'`（ANSI-C 引码绕过） |
| `_check_backslash_escaped_whitespace` | 反斜杠转义空格 | `r\m`（绕过 rm 关键字匹配） |
| `_check_backslash_escaped_operators` | 反斜杠转义操作符 | `\;`、`\|`（隐藏管道） |
| `_check_newlines` | 隐藏换行 | `\r` 后跟隐藏命令 |
| `_check_comment_quote_desync` | 注释中引号不同步 | `# it's` 导致引号状态错乱 |
| `_check_quoted_newline` | 引号内换行 | 多行命令伪装成单行 |

关键设计：`_extract_outside_single_quotes()` 函数剥离单引号内容但保留双引号内容——因为 Shell 会在双引号内展开变量和命令替换，单引号内不会。

### SecretStore——Fernet 加密存储

API Key 等敏感信息用 Fernet 对称加密存储在磁盘上：

```python
# 密钥管理优先级
def _get_master_key():
    # 1. 进程内缓存（最快）
    # 2. OS 密钥环（keyring 库）
    # 3. 文件 ~/.qwenpaw.secret/.master_key
    # 4. 自动生成新密钥
```

加密后的值以 `ENC:` 前缀标记：

```python
def encrypt(plaintext: str) -> str:
    return f"ENC:{fernet.encrypt(plaintext.encode()).decode()}"

def decrypt(value: str) -> str:
    if not value.startswith("ENC:"):
        return value  # 未加密，直接返回
    return fernet.decrypt(value[4:].encode()).decode()
```

批量加密用于 Provider 配置：

```python
PROVIDER_SECRET_FIELDS = {"api_key"}
encrypt_dict_fields(provider_data, PROVIDER_SECRET_FIELDS)
# api_key: "sk-xxx" -> api_key: "ENC:gAAAAA..."
```

### SkillScanner——技能安装前的安检

`SkillScanner` 在安装第三方技能时扫描安全风险：

```python
class SkillScanner:
    def scan_skill(self, skill_dir, *, skill_name=None):
        # 1. 发现文件（防路径穿越）
        files = self._discover_files(skill_dir)
        # 2. 运行所有分析器
        for analyzer in self._analyzers:
            findings.extend(analyzer.analyze(skill_dir, files, ...))
        # 3. 去重并返回
        return ScanResult(findings=deduplicated)
```

`PatternAnalyzer` 从 7 个 YAML 规则文件加载正则签名：

```
rules/signatures/
  command_injection.yaml    # 命令注入
  data_exfiltration.yaml    # 数据泄露
  hardcoded_secrets.yaml    # 硬编码密钥
  obfuscation.yaml          # 代码混淆
  prompt_injection.yaml     # 提示注入
  social_engineering.yaml   # 社会工程
  supply_chain.yaml         # 供应链攻击
  unauthorized_tool_use.yaml # 未授权工具使用
```

`ScanResult.is_safe` 检查是否有 CRITICAL/HIGH 级别发现。扫描模式由配置控制：

```python
class SkillScannerConfig(BaseModel):
    mode: Literal["block", "warn", "off"] = "warn"
    # block: 发现高风险直接阻止安装
    # warn:  只记录警告，允许安装
    # off:   不扫描
```

### SecurityConfig——可配置的安全策略

所有安全配置集中在 `SecurityConfig`：

```python
class SecurityConfig(BaseModel):
    tool_guard: ToolGuardConfig      # 工具守卫配置
    file_guard: FileGuardConfig      # 文件路径保护
    skill_scanner: SkillScannerConfig # 技能扫描配置

class ToolGuardConfig(BaseModel):
    enabled: bool = True             # 总开关
    guarded_tools: Optional[List[str]]  # 受保护的工具列表
    denied_tools: List[str]          # 无条件拒绝的工具
    custom_rules: List[ToolGuardRuleConfig]  # 自定义规则
    disabled_rules: List[str]        # 禁用的规则 ID
```

用户可以通过 Web UI 或直接编辑 `config.json` 调整安全策略——不需要改代码。

## 实验

在源码中追踪安全检查的完整流程：

1. 打开 `src/qwenpaw/security/tool_guard/engine.py`，搜索 `def guard`
2. 打开 `src/qwenpaw/security/tool_guard/guardians/shell_evasion_guardian.py`，搜索 `_check_command_substitution`
3. 打开 `src/qwenpaw/security/secret_store.py`，搜索 `def encrypt`
4. 打开 `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml`，看规则格式

预期结果：能看到 `guard()` 遍历 Guardian 的逻辑、Shell 混淆检测的正则模式、Fernet 加密的实现、YAML 规则的格式。

## 工程权衡

### 为什么用 YAML 规则而非硬编码检查？

新增安全检查不需要改 Python 代码——只需在 YAML 里加一条规则。运维人员可以自定义规则而不需要开发环境。代价是正则表达式的可读性不如 Python 代码，但 YAML 的注释和结构化字段（description、remediation）弥补了这个缺陷。

### 为什么 ShellEvasionGuardian 用状态机而非正则？

Shell 命令中的引号和转义是上下文相关的——`"rm"` 在双引号内是安全的字符串，但在无引号状态下是危险的命令。纯正则无法跟踪引号状态，必须用字符级状态机。状态机的复杂度换取了检测的准确性。

### 为什么 FilePathToolGuardian 设置 always_run=True？

文件路径泄露（如读取 `/etc/shadow`）是高风险操作，不应该因为工具不在 `guarded_tools` 列表就跳过检查。即使新增了一个未在列表中的文件操作工具，`FilePathToolGuardian` 也会检查它——因为路径检查对所有文件操作都适用。

## 常见误区

> **误区：安全检查会拖慢工具执行速度？**
>
> 每次工具调用都运行三个 Guardian，看起来开销大。但实际上 Guardian 的检查都是字符串匹配和正则搜索——对于单条命令或路径，耗时在微秒级。只有 `ShellEvasionGuardian` 的字符级状态机稍慢，但也只在 `execute_shell_command` 时触发。整体开销可以忽略。

> **误区：SecretStore 的 Fernet 加密绝对安全？**
>
> Fernet 是对称加密——安全性取决于主密钥的保管。如果攻击者拿到了 `~/.qwenpaw.secret/.master_key` 文件，就能解密所有密钥。QwenPaw 优先使用 OS 密钥环（macOS Keychain、Linux Secret Service），文件只是降级方案。在共享服务器上，建议配置密钥环存储。

## 动手环节

**任务**：阅读 ShellEvasionGuardian 的一个检查函数，理解引号状态机的工作方式。

**步骤**：
1. 打开 `src/qwenpaw/security/tool_guard/guardians/shell_evasion_guardian.py`
2. 搜索 `_check_command_substitution`
3. 阅读 `_QuoteState` 类和 `_extract_outside_single_quotes` 函数
4. 打开 `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml`，阅读规则格式

**预期输出**：
- `_check_command_substitution` 检测 `$(...)`、反引号、进程替换
- `_QuoteState` 跟踪单引号、双引号、转义状态
- YAML 规则有 id、tools、params、patterns、severity 等字段

**自检**：
- [ ] 理解了 ToolGuardEngine 调度三个 Guardian 的方式
- [ ] 知道 YAML 规则的格式和匹配流程
- [ ] 知道 ShellEvasionGuardian 用引号状态机检测混淆
- [ ] 知道 SecretStore 用 Fernet 加密，优先用 OS 密钥环

---

Security 的三道防线清楚了。下一章我们看 Skills 的工坊——技能和工具有什么区别？技能怎么通过提示注入扩展 Agent 的能力？技能市场怎么从 GitHub 和 ClawHub 安装技能？
