# 第 14 章：Skills 的工坊——插件架构

```
卷二：理解设计
[9] 源码地图 -> [10] Agent身世 -> [11] Provider棋局 -> [12] Channel变装 -> [13] Security围栏 -> [14] Skills工坊 <- you are here
```

第 7 章我们看了工具——`execute_shell_command`、`read_file` 这些可调用的 Python 函数。但 QwenPaw 还有另一种扩展机制——技能（Skills）。技能不是函数调用，而是提示注入。这一章我们看技能系统的设计：技能和工具有什么区别？技能怎么安装和管理？技能市场怎么工作？

---

## 问题

PDF 处理、浏览器自动化、Office 文档操作……这些功能很复杂，不适合写成单个 Python 函数。QwenPaw 怎么让 LLM 学会这些复杂能力？怎么从社区安装第三方技能？怎么保证安装的技能是安全的？

## 术语其实很简单

> **术语：技能（Skill）**
> 想象一本操作手册——告诉你怎么操作某台设备。技能就是 LLM 的"操作手册"——一个包含 `SKILL.md`（指令）、`references/`（参考文档）、`scripts/`（脚本）的目录。LLM 阅读手册后，用已有的工具（Shell、文件读写）完成任务。

> **术语：技能池（Skill Pool）**
> 想象一个公共图书馆——所有书都在这里，需要时借到工作区。技能池是跨工作区共享的技能存储——`SkillPoolService` 管理，技能可以被多个工作区复用。

## 探索

### 技能 vs 工具——两种扩展机制

这是理解技能系统的关键：

```
工具（Tool）：扩展 LLM "能做什么"
  注册方式：Toolkit.register_tool_function(fn)
  机制：函数调用——LLM 生成 {"name": "read_file", "input": {...}}
  示例：read_file、execute_shell_command、get_current_time

技能（Skill）：扩展 LLM "知道什么"
  注册方式：Toolkit.register_agent_skill(skill_dir)
  机制：提示注入——把 SKILL.md 的摘要追加到系统提示词
  示例：PDF 处理、浏览器自动化、Office 文档操作
```

技能不注册新函数——它告诉 LLM "你可以用现有工具做 X，步骤如下"。LLM 阅读技能的 `SKILL.md`，然后用 `execute_shell_command`、`read_file` 等已有工具执行。

这种设计的优势：技能只需要 Markdown 文件，不需要写 Python 代码。一个"PDF 处理"技能可能只包含 `SKILL.md`（怎么用 pdftotxt 提取文本）和 `scripts/convert.py`（辅助脚本），不需要修改 Agent 的工具注册表。

### 技能目录结构

一个典型的技能目录：

```
skills/pdf-en/
  SKILL.md              # 必须：YAML 前置元数据 + 技能指令
  LICENSE.txt            # 可选：许可证
  reference.md           # 可选：详细参考文档
  forms.md               # 可选：子主题参考
  scripts/               # 可选：辅助脚本
    convert_pdf_to_images.py
    extract_form_field_info.py
    fill_fillable_fields.py
```

`SKILL.md` 的格式：

```yaml
---
name: pdf
description: Use this skill whenever the user wants to do anything with PDF files...
metadata:
  builtin_skill_version: "1.1"
---

# PDF Processing Skill

## How to use
1. Check if the PDF is text-based or scanned
2. For text-based PDFs, use `pdftotext` command...
3. For form fields, run the script `scripts/extract_form_field_info.py`...
```

`name` 和 `description` 是必需字段——`register_agent_skill()` 解析前置元数据来构建提示：

```python
# agentscope Toolkit 内部逻辑
def register_agent_skill(self, skill_dir):
    # 解析 SKILL.md 的 YAML 前置元数据
    name, description = parse_frontmatter(skill_dir / "SKILL.md")
    self.skills.append(AgentSkill(name, description, skill_dir))
```

### 提示注入的工作方式

技能注册后，其信息被注入系统提示词：

```python
# agentscope _react_agent.py
@property
def sys_prompt(self):
    base = self._sys_prompt
    skill_prompt = self.toolkit.get_agent_skill_prompt()
    if skill_prompt:
        return base + "\n\n" + skill_prompt
    return base
```

`get_agent_skill_prompt()` 生成的提示格式：

```
# Agent Skills
The agent skills are a collection of instructions, scripts, and resources...

## pdf
Use this skill whenever the user wants to do anything with PDF files...
Check "skills/pdf-en/SKILL.md" for how to use this skill.

## browser
Use this skill for web automation tasks...
Check "skills/browser-en/SKILL.md" for how to use this skill.
```

LLM 看到这段提示后，就知道有哪些技能可用。当用户问"帮我提取这个 PDF 的文本"，LLM 会：
1. 识别出需要 `pdf` 技能
2. 用 `read_file` 读取 `skills/pdf-en/SKILL.md`
3. 按照指令用 `execute_shell_command` 调用 `pdftotxt`
4. 用 `read_file` 读取结果并回复用户

### SkillService——工作区级别的技能管理

`SkillService` 管理单个工作区的技能生命周期：

```python
class SkillService:
    def __init__(self, workspace_dir):
        self.workspace_dir = workspace_dir

    # 核心方法
    def create_skill(self, name, content, ...) -> str | None
    def enable_skill(self, name) -> dict
    def disable_skill(self, name) -> dict
    def delete_skill(self, name) -> bool
    def save_skill(self, *, skill_name, content, ...) -> dict
    def import_from_zip(self, data, ...) -> dict
```

技能启用时，`enable_skill()` 会先运行安全扫描（第 13 章的 SkillScanner），确认安全后才更新清单：

```python
def enable_skill(self, name):
    # 1. 安全扫描
    scan_result = scanner.scan_skill(skill_dir, skill_name=name)
    if scan_result.has_high_findings() and mode == "block":
        return {"error": "unsafe skill"}

    # 2. 更新清单
    manifest["skills"][name]["enabled"] = True
    save_manifest(manifest)
```

### 工作区清单——技能的状态注册表

每个工作区有一个 `skill.json` 清单，记录所有技能的状态：

```json
{
  "schema_version": "workspace-skill-manifest.v1",
  "skills": {
    "pdf": {
      "enabled": true,
      "channels": ["all"],
      "source": "builtin",
      "metadata": {"name": "pdf", "description": "..."},
      "requirements": {"require_bins": [], "require_envs": []}
    },
    "browser": {
      "enabled": false,
      "channels": ["console", "dingtalk"],
      "source": "hub"
    }
  }
}
```

`channels` 字段控制技能在哪些渠道可见——默认 `["all"]`，也可以限制只在特定渠道生效。

### SkillPoolService——跨工作区共享

`SkillPoolService` 管理全局技能池，允许多个工作区共享同一份技能：

```python
class SkillPoolService:
    # 池级操作
    def upload_from_workspace(self, workspace_dir, skill_name) -> dict
    def download_to_workspace(self, skill_name, workspace_dir) -> dict
```

工作流：
1. 用户在 A 工作区创建了一个技能
2. `upload_from_workspace` 把技能复制到全局池
3. 用户在 B 工作区 `download_to_workspace` 安装同一技能
4. 两个工作区共享同一份技能代码，但状态（enabled/disabled）独立

### SkillsHub——技能市场

`skills_hub.py` 实现了多源技能市场，支持 6 个平台：

| 平台 | URL 模式 | 说明 |
|---|---|---|
| ClawHub | `clawhub.ai` | QwenPaw 官方市场 |
| GitHub | `github.com/owner/repo` | 直接从仓库安装 |
| skills.sh | `skills.sh/owner/repo/skill` | 社区市场 |
| LobeHub | `lobehub.com/skills/...` | LobeChat 生态 |
| ModelScope | `modelscope.cn/skills/@owner/skill` | 国内平台 |
| SkillsMP | `skillsmp.com` | 社区聚合 |

安装流程：

```python
def install_skill_from_hub(*, workspace_dir, bundle_url, ...):
    # 1. 解析 URL，识别平台
    # 2. 下载技能包（GitHub 用 Contents API）
    # 3. 标准化为统一格式 {name, content, references, scripts}
    # 4. 调用 SkillService.create_skill() 安装到工作区
    # 5. 可选：自动启用
```

所有平台的数据最终被 `_normalize_bundle()` 统一为 `{name, content, references, scripts, extra_files}` 格式——不同平台的差异在这一层被抹平。

### 中英文本地化

内置技能提供中文和英文两个版本：

```
skills/
  pdf-en/    # 英文版
  pdf-zh/    # 中文版
  browser-en/
  browser-zh/
  ...
```

语言偏好从 `settings.json` 的 `builtin_skill_language` 或 `language` 字段推断。选择逻辑：

```python
def get_builtin_skill_language_preference():
    # 1. 显式配置
    if settings.get("builtin_skill_language"):
        return settings["builtin_skill_language"]
    # 2. 根据 UI 语言推断
    if settings.get("language", "").startswith("zh"):
        return "zh"
    return "en"
```

## 实验

在源码中追踪技能的注册和使用：

1. 打开 `src/qwenpaw/agents/skills_manager.py`，搜索 `class SkillService`
2. 打开 `src/qwenpaw/agents/skills_manager.py`，搜索 `enable_skill`
3. 在 `.venv/site-packages/agentscope/tool/_toolkit.py` 中搜索 `register_agent_skill`
4. 打开 `src/qwenpaw/agents/skills/pdf-en/SKILL.md`，看技能的前置元数据和指令

预期结果：能看到 SkillService 的生命周期方法、`register_agent_skill` 解析 YAML 前置元数据的逻辑、PDF 技能的完整结构。

## 工程权衡

### 为什么技能用提示注入而非函数调用？

PDF 处理、浏览器自动化这些任务很复杂——涉及多个步骤、条件判断、错误处理。写成单个 Python 函数会非常庞大且难以维护。提示注入让 LLM "学会"怎么做，然后灵活运用已有工具组合完成任务。代价是执行不如函数调用可靠（LLM 可能不遵循指令），但胜在灵活性和可维护性。

### 为什么技能池和工作区分开？

多工作区是 QwenPaw 的核心功能——每个 Agent 有自己的工作区。如果技能只存在于工作区内，每个工作区都要维护一份副本。技能池让"安装一次，多工作区使用"成为可能。代价是额外的管理复杂度（上传/下载/同步），但在多 Agent 场景下省了大量重复安装。

### 为什么支持 6 个技能市场？

不同用户有不同的技能来源偏好——国内用户用 ModelScope，海外用户用 GitHub，社区用户用 skills.sh。支持多平台降低了技能获取的门槛。代价是每个平台需要独立的 URL 解析和下载逻辑，但 `_normalize_bundle()` 把差异收敛到一层。

## 常见误区

> **误区：技能就是工具的另一个名字？**
>
> 不是。工具是 Python 函数，LLM 通过 function calling 调用。技能是 Markdown 文档，LLM 通过阅读系统提示词"学会"使用。技能依赖已有工具来执行——一个 PDF 技能可能只是告诉 LLM "用 `pdftotxt` 命令提取文本"，实际执行还是靠 `execute_shell_command` 工具。技能扩展 LLM 的知识，工具扩展 LLM 的能力。

> **误区：技能安装后立刻生效？**
>
> 技能需要 `enable` 才会生效。`enable_skill()` 会运行安全扫描（SkillScanner），如果有 CRITICAL/HIGH 级别的发现且模式是 "block"，安装会失败。即使用户手动编辑 `skill.json` 启用了技能，下次 `reconcile_workspace_manifest()` 也会重新检查。

## 动手环节

**任务**：阅读一个完整技能的目录结构和 SKILL.md 内容。

**步骤**：
1. 打开 `src/qwenpaw/agents/skills/` 目录，看所有技能目录
2. 打开 `src/qwenpaw/agents/skills/pdf-en/SKILL.md`，阅读前置元数据和指令
3. 打开 `src/qwenpaw/agents/skills/pdf-en/scripts/` 目录，看辅助脚本
4. 打开 `src/qwenpaw/agents/skills_hub.py`，搜索 `install_skill_from_hub`

**预期输出**：
- `pdf-en/SKILL.md` 有 YAML 前置元数据（name、description）和详细指令
- `scripts/` 目录有多个辅助 Python 脚本
- `install_skill_from_hub` 展示了多平台安装流程

**自检**：
- [ ] 理解了技能和工具的区别：提示注入 vs 函数调用
- [ ] 知道 `register_agent_skill` 把技能信息注入系统提示词
- [ ] 知道技能清单 `skill.json` 记录每个技能的状态
- [ ] 知道 SkillsHub 支持 6 个技能市场平台

---

卷二"理解设计"完成。我们看了 Agent 的 Mixin 继承、Provider 的策略模式、Channel 的适配器模式、Security 的拦截器架构、Skills 的插件设计。下一卷"工坊"，我们动手——造一把新工具、造一个新技能、接入一个新模型、接入一个新频道、从零提交一个 PR。
