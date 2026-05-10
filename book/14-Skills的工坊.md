# 第十四章 Skills 的工坊——插件架构

```
浏览器 ─→ HTTP ─→ Runner ─→ Agent ─→ Prompt ─→ ReAct ─→ LLM ─→ Tool ─→ [Skill 插件]
                                                                              |
                                                                           你在这里
```

`[插件架构]` -- 第二卷的最后一站。

## 问题：为什么 Skill 放在工作目录下而非源码里？

在前面的章节里，我们追踪了一个完整的请求链路，理解了 Agent 怎么被创建、提示词怎么拼装、ReAct 循环怎么运转、工具怎么执行。第八章之后，我们进入了第二卷，开始拆解这些代码背后的设计模式。

现在，我们来看 QwenPaw 里一个与众不同的子系统：**Skill（技能）**。

Skill 和 Tool 不一样。Tool 是 Python 代码，写在 `src/qwenpaw/agents/tools/` 下，随源码一起发布。而 Skill 是 Markdown 文件，放在**用户的工作目录**下，可以在不修改源码、甚至不重启服务的情况下被添加、修改或删除。

这引出了几个追问：

Skill 的 Markdown 文件是怎么被系统"发现"并"理解"的？为什么不用 Python 写 Skill？用户在工作目录里放一个新文件夹，系统怎么知道它的存在？这一切背后的"插件架构"是怎么运转的？

这一章，我们走进 Skills 的工坊，看看一个以 Markdown 为载体的插件系统是怎么被设计、加载和执行的。

---

## 术语其实很简单

> **术语：插件架构（Plugin Architecture）**
> 想象一台电脑。你不用把所有功能焊死在主板上——你插一块显卡，它就能跑游戏；插一块声卡，它就能放音乐。插件架构就是这样一种设计：核心系统提供一套"插槽"，功能模块以"插件"的形式插入插槽。插槽是稳定的、定义好的接口；插件是可变的、可替换的。QwenPaw 的 Skill 就是一种插件：核心系统（Agent）提供加载和执行机制，Skill 以 Markdown 文件的形式"插入"到系统中。

> **术语：热插拔（Hot-plugging）**
> 想象你在电脑运行的时候拔掉一个 U 盘、再插上另一个。你不需要关机再开机。热插拔就是"在系统运行期间动态添加或移除组件"的能力。在 QwenPaw 中，你可以在 Agent 运行时往工作目录里放一个新的 Skill 文件夹，或者删掉一个旧的，下次请求到来时 Agent 就会自动加载新的 Skill 集合——不需要重启进程。

---

## 探索：Skills 的插件架构全景

### 一张全景图

在深入源码之前，让我们先建立对整个 Skill 系统的整体印象：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        QwenPaw 插件架构全景                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐      ┌──────────────────┐                     │
│  │  源码内置技能      │      │  用户自定义技能    │                     │
│  │  src/.../skills/  │      │  skill_pool/      │                     │
│  │  cron-en/         │      │  my_skill/        │                     │
│  │  news-en/         │      │  ...              │                     │
│  │  pdf-en/          │      └────────┬─────────┘                     │
│  │  ...              │               │                               │
│  └────────┬─────────┘               │  下载到工作区                   │
│           │ 初始导入                  ▼                               │
│           ▼              ┌──────────────────┐                        │
│  ┌──────────────────┐   │  工作区技能        │                        │
│  │  共享技能池        │──→│  workspace/skills/ │──→ Agent 运行时        │
│  │  skill_pool/      │   │  cron/            │    (Toolkit 注册)      │
│  │  cron/            │   │  news/            │                        │
│  │  pdf/             │   │  ...              │                        │
│  └──────────────────┘   └──────────────────┘                        │
│                                                                     │
│  每个 Skill 目录:                                                    │
│  ┌──────────────────┐                                               │
│  │  SKILL.md        │ ← YAML frontmatter (元数据) + Markdown (指令)  │
│  │  references/     │ ← 可选，参考文档                                │
│  │  scripts/        │ ← 可选，辅助脚本                                │
│  └──────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────┘
```

这张图展示了 Skill 从"出生"到"运行"的完整路径。让我们沿着这条路径逐一探索。

### Skill 的目录结构：Markdown 即代码

一个 Skill 的物理形态是什么？它就是一个文件夹，里面至少包含一个 `SKILL.md` 文件。以 `cron-en` 技能为例：

```
cron-en/
  SKILL.md        ← 唯一必需的文件
```

以 `pdf-en` 技能为例，结构更丰富：

```
pdf-en/
  SKILL.md          ← 技能定义（YAML 元数据 + Markdown 指令）
  reference.md      ← 参考文档（详细的 API 说明）
  forms.md          ← 表单填写指南
  LICENSE.txt       ← 许可证
  scripts/          ← 辅助脚本
    check_bounding_boxes.py
    extract_form_field_info.py
    fill_pdf_form_with_annotations.py
    ...
```

核心是 `SKILL.md`。它的格式很独特：**YAML frontmatter + Markdown 正文**。这是从 Jekyll 博客系统借鉴来的格式。文件的开头用 `---` 包裹一段 YAML 元数据，后面是自由的 Markdown 内容。

让我们看看 `cron-en/SKILL.md` 的开头：

```yaml
---
name: cron
description: Use this skill only for scheduled or recurring tasks.
metadata:
  builtin_skill_version: "1.4"
  qwenpaw:
    emoji: "..."
---
```

YAML 部分声明了技能的**名字**、**描述**、**版本号**和**图标**。这些元数据会被程序解析，用于在界面中展示技能列表、判断版本是否需要更新。

Markdown 部分则是一份写给 AI Agent 的"操作手册"。它告诉 Agent：在什么场景下应该使用这个技能，使用时要注意什么规则，有哪些可用的命令。这份手册会被注入到 Agent 的系统提示词中，成为 Agent "知识"的一部分。

这就是"Markdown 即代码"的核心思想：**不写 Python，写文档。技能不是程序，而是指令。**

### Skill 的生命周期

一个 Skill 从被创建到被执行，要经历五个阶段：

```
  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ 发现    │───→│ 加载    │───→│ 注册    │───→│ 执行    │───→│ 卸载    │
  │ discover│    │ load    │    │register │    │ execute │    │ unload  │
  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
       │              │              │              │              │
       ▼              ▼              ▼              ▼              ▼
  扫描目录        解析 SKILL.md    写入 Toolkit   Agent 读取     从运行时
  找到含         读取 frontmatter  注册为         SKILL.md       移除注册
  SKILL.md       和 Markdown 正文  可用技能       内容并执行      下次不再加载
  的子目录        构建 SkillInfo
```

让我们逐一看看每个阶段发生了什么。

#### 第一阶段：发现（Discover）

发现的入口是 `skills_manager.py` 中的 `reconcile_workspace_manifest()` 函数。它的任务很简单：扫描工作目录下的 `skills/` 文件夹，找出所有包含 `SKILL.md` 文件的子目录。

核心逻辑只有几行：

```python
discovered = {
    path.name: path
    for path in workspace_skills_dir.iterdir()
    if path.is_dir() and (path / "SKILL.md").exists()
}
```

这行代码的意思是：遍历 `workspace/skills/` 下的每一项，如果是目录，且里面存在 `SKILL.md` 文件，就算"发现"了一个 Skill。发现的 key 是目录名，value 是目录路径。

这种设计非常简洁——**文件系统就是注册表**。不需要复杂的配置文件，不需要额外的数据库。你想添加一个 Skill？创建一个目录，放一个 `SKILL.md`，下次对账时它就会自动被发现。

#### 第二阶段：加载（Load）

发现之后是加载。加载的过程是读取 `SKILL.md` 文件，解析出元数据和内容。

解析使用的是 `python-frontmatter` 库，它能识别 YAML 头部和 Markdown 正文：

```python
post = frontmatter.loads(
    read_text_file_with_encoding_fallback(skill_md_path),
)
description = str(post.get("description", "") or "")
version_text = _extract_version(post)
```

解析结果被封装为一个 `SkillInfo` 对象。这个对象包含了技能的名字、描述、版本、完整内容、引用文件树和脚本文件树。

`_read_skill_from_dir()` 函数还负责读取可选的 `references/` 和 `scripts/` 子目录，把它们也纳入 `SkillInfo`：

```python
references_dir = skill_dir / "references"
scripts_dir = skill_dir / "scripts"
if references_dir.exists():
    references = _directory_tree(references_dir)
if scripts_dir.exists():
    scripts = _directory_tree(scripts_dir)
```

注意这里只读取了目录树（文件名列表），并没有读取文件内容。文件内容是在 Agent 执行时按需读取的。

#### 第三阶段：注册（Register）

注册发生在 `react_agent.py` 的 `_register_skills()` 方法中。它的工作是把"有效的"Skill 注册到 Agent 的工具集（Toolkit）里。

```python
def _register_skills(self, toolkit: Toolkit) -> None:
    ensure_skills_initialized(workspace_dir)
    effective_skills = resolve_effective_skills(
        workspace_dir, channel_name,
    )
    for skill_name in effective_skills:
        skill_dir = working_skills_dir / skill_name
        if skill_dir.exists():
            toolkit.register_agent_skill(str(skill_dir))
```

这里有一步关键操作：**`resolve_effective_skills()`**。不是所有发现的 Skill 都会被注册。只有满足两个条件的 Skill 才是"有效的"：

1. 在 `skill.json` 清单中被标记为 `enabled: true`
2. 该 Skill 的 `channels` 列表包含当前请求的渠道名（如 `console`、`discord`），或者列表中包含 `"all"`

这意味着同一个 Skill 可以被配置为只在特定渠道生效。比如你可以让"新闻查询"技能只在 Discord 渠道可用，在控制台不可用。

#### 第四阶段：执行（Execute）

执行阶段发生在 ReAct 循环中。当大语言模型决定使用某个 Skill 时，它会读取该 Skill 的 `SKILL.md` 内容（包括所有参考文档和脚本），然后按照其中的指令行动。

Skill 的执行方式与 Tool 不同。Tool 是一段 Python 代码，有明确的输入输出类型。Skill 是一段自然语言指令，Agent 通过"理解"这些指令来决定如何行动。Skill 可能指导 Agent 调用一个或多个 Tool，也可能指导 Agent 使用特定的命令行工具。

比如 `news-en` 技能的 SKILL.md 中包含一张新闻源 URL 表格。它告诉 Agent：当用户问"最新新闻"时，用浏览器工具打开这些 URL，抓取内容，然后汇总给用户。Agent 按照这份"操作手册"来行动。

#### 第五阶段：卸载（Unload）

Skill 的卸载是隐式的。QwenPaw 并没有一个显式的"卸载"操作。每次新请求到来时，`ensure_skills_initialized()` 会重新对账（reconcile）工作目录和清单。如果你删除了一个 Skill 的目录，或者在 `skill.json` 中把它设为 `enabled: false`，下次请求时它就不会被注册。

这就是热插拔的实现方式：**不是通过动态加载/卸载代码，而是通过每次请求时重新读取配置**。这种设计牺牲了一点性能（每次都要重新扫描），换来了极大的灵活性。

### 双语技能：-en 和 -zh 变体

如果你浏览 `src/qwenpaw/agents/skills/` 目录，会发现一个规律：每个技能都有两个版本。

```
skills/
  cron-en/          ← 英文版
  cron-zh/          ← 中文版
  news-en/
  news-zh/
  pdf-en/
  pdf-zh/
  ...
```

这不是巧合。源码中有一个正则表达式专门用来解析这种命名：

```python
_BUILTIN_SKILL_DIR_RE = re.compile(
    r"^(?P<name>.+)-(?P<language>en|zh)$",
)
```

目录名的格式是 `{技能名}-{语言代码}`。`cron-en` 表示"cron 技能的英文版"，`cron-zh` 表示"cron 技能的中文版"。

系统会根据用户的语言偏好来选择合适的变体。语言偏好的读取逻辑在 `get_builtin_skill_language_preference()` 中：先看 `settings.json` 中的 `builtin_skill_language` 字段，如果没有，就看 `language` 字段（如果以 `zh` 开头就用中文，否则用英文），再没有就默认英文。

当内置技能被导入到技能池时，系统会根据这个偏好选择对应的语言版本复制过去。

### 热插拔的实现：对账机制

热插拔的核心是**对账（reconcile）**。整个系统有两层对账：

**第一层：技能池对账（`reconcile_pool_manifest()`）**

扫描 `WORKING_DIR/skill_pool/` 目录，把文件系统上的实际技能和 `skill_pool/skill.json` 清单进行比对。新出现的目录会被加入清单，消失的目录会被移除。已有条目的元数据（描述、版本等）会从磁盘上的 `SKILL.md` 重新读取。

**第二层：工作区对账（`reconcile_workspace_manifest()`）**

扫描 `workspace/skills/` 目录，同样和 `workspace/skill.json` 比对。它还会保留用户的配置（是否启用、渠道列表、自定义配置），只更新元数据部分。

两层对账的共同设计原则是：**文件系统是真相的来源，清单是描述性的**。如果你手动在技能池目录里放一个新的 Skill 文件夹，下次对账时它会被自动发现并加入清单。如果你手动删除一个文件夹，它会被从清单中移除。

这种设计保证了**文件系统和清单始终一致**，即使在出现磁盘操作错误或手动干预的情况下也能自我修复。

### 安全扫描：在加载前把关

在 Skill 被正式写入工作目录之前，系统会对它进行安全扫描。这发生在 `_scan_skill_dir_or_raise()` 中：

```python
def _scan_skill_dir_or_raise(skill_dir: Path, skill_name: str) -> None:
    scan_skill_directory(skill_dir, skill_name=skill_name)
```

安全扫描（由 `security/skill_scanner.py` 实现）会检查 Skill 目录中是否存在潜在危险的文件：符号链接穿越、可执行二进制文件、隐藏的系统文件等。如果扫描不通过，整个创建或导入操作会被拒绝。

这是一个"先扫后写"（scan-before-write）的模式。即使 Skill 是 Markdown 格式，也不能完全信任用户上传的内容——攻击者可以在 zip 包里藏匿恶意文件。

### 清单的并发安全

当多个请求同时修改同一个 `skill.json` 时，怎么保证数据不损坏？答案是**文件锁**。

`skills_manager.py` 实现了一个跨平台的文件锁机制：

```python
@contextmanager
def _file_write_lock(lock_path: Path) -> Iterator[None]:
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        if fcntl is not None:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        elif msvcrt is not None:
            lock_file.seek(0)
            msvcrt.locking(lock_file.fileno(), msvcrt.LK_LOCK, 1)
        try:
            yield
        finally:
            # 释放锁
```

在 Linux/macOS 上使用 `fcntl.flock`，在 Windows 上使用 `msvcrt.locking`。每次修改清单时，先获取锁，修改完成后再释放。

清单的写入还使用了**原子写入**模式：先写到一个临时文件，然后用 `replace()` 原子性地替换目标文件。这保证了即使在写入过程中进程崩溃，也不会留下一个半损坏的 JSON 文件。

---

## 实验：阅读一个完整 Skill 的目录结构

让我们用 `pdf-en` 技能做一个完整的"解剖实验"。这个技能比 `cron-en` 更复杂，包含了参考文档和脚本子目录。

首先，查看目录结构：

```bash
# pdf-en 的完整目录树
find src/qwenpaw/agents/skills/pdf-en -type f | sort
```

你会看到如下输出：

```
src/qwenpaw/agents/skills/pdf-en/LICENSE.txt
src/qwenpaw/agents/skills/pdf-en/SKILL.md
src/qwenpaw/agents/skills/pdf-en/forms.md
src/qwenpaw/agents/skills/pdf-en/reference.md
src/qwenpaw/agents/skills/pdf-en/scripts/check_bounding_boxes.py
src/qwenpaw/agents/skills/pdf-en/scripts/check_fillable_fields.py
src/qwenpaw/agents/skills/pdf-en/scripts/convert_pdf_to_images.py
src/qwenpaw/agents/skills/pdf-en/scripts/create_validation_image.py
src/qwenpaw/agents/skills/pdf-en/scripts/extract_form_field_info.py
src/qwenpaw/agents/skills/pdf-en/scripts/extract_form_structure.py
src/qwenpaw/agents/skills/pdf-en/scripts/fill_fillable_fields.py
src/qwenpaw/agents/skills/pdf-en/scripts/fill_pdf_form_with_annotations.py
```

每个文件的职责如下：

| 文件 | 职责 |
|------|------|
| `SKILL.md` | 核心定义。YAML 头部声明名字、描述、版本；Markdown 正文是给 Agent 的操作手册 |
| `reference.md` | 详细参考文档。包含更多 API 说明和代码示例 |
| `forms.md` | 专门针对 PDF 表单填写的指南 |
| `LICENSE.txt` | 许可证声明 |
| `scripts/*.py` | 辅助脚本。Agent 可以通过命令行调用这些脚本来完成特定任务 |

接下来，读取 `SKILL.md` 的 YAML 头部：

```bash
head -8 src/qwenpaw/agents/skills/pdf-en/SKILL.md
```

你会看到：

```yaml
---
name: pdf
description: Use this skill whenever the user wants to do anything
  with PDF files.
license: Proprietary. LICENSE.txt has complete terms
metadata:
  builtin_skill_version: "1.1"
---
```

这里有一个值得注意的设计：`description` 字段是给系统用的（用于展示技能列表），而 Markdown 正文是给 Agent 用的（用于指导执行）。同一个文件同时服务于两个受众：人类用户（通过界面看描述）和 AI Agent（通过提示词看指令）。

现在，让我们验证系统是怎么发现和加载这个技能的。假设你有一个工作区，且 `pdf` 技能已经被启用：

```bash
# 查看工作区的技能清单
cat workspaces/<your_workspace>/skill.json | python3 -m json.tool
```

在清单中，你会看到类似这样的条目：

```json
{
  "pdf": {
    "enabled": true,
    "channels": ["all"],
    "source": "builtin",
    "metadata": {
      "name": "pdf",
      "description": "Use this skill whenever...",
      "version_text": "1.1"
    },
    "requirements": {
      "require_bins": ["qpdf", "pdftotext"],
      "require_envs": []
    }
  }
}
```

注意 `requirements` 字段。它声明了这个技能需要的系统命令（`qpdf`、`pdftotext`）。如果这些命令不在系统 PATH 中，技能可能无法正常工作。需求信息是从 `SKILL.md` 的 frontmatter 中解析出来的。

这就是一个完整 Skill 从文件到运行时的全貌。

---

## 工程权衡：热插拔的代价

Skill 系统的设计中有几个明显的权衡，值得仔细思考。

### 权衡一：每次请求都重新对账 vs 缓存

当前的设计是每次调用 `ensure_skills_initialized()` 时都执行一次 `reconcile_workspace_manifest()`。这意味着每次用户发消息，系统都会扫描工作区的 `skills/` 目录，读取每个 `SKILL.md` 的 frontmatter，更新清单。

**好处**：真正的热插拔。你在文件系统上的任何修改（添加、删除、编辑）都会在下次请求时立即生效。

**代价**：额外的 I/O 开销。如果工作区有几十个 Skill，每次请求都要读取几十个文件。

这是一个"以性能换灵活性"的决策。对于 QwenPaw 的典型使用场景（对话式交互，请求之间有几秒的间隔），这点 I/O 开销是可以接受的。但如果 Skill 数量增长到几百个，或者请求频率非常高，可能需要引入缓存机制——比如只在文件修改时间变化时才重新读取。

### 权衡二：Markdown vs Python

为什么不直接用 Python 来写 Skill？如果 Skill 是 Python 模块，执行效率会更高，类型检查也会更严格。

原因有三点：

1. **安全性**。执行用户提供的 Python 代码是一个巨大的安全风险。即使用沙箱隔离，也难以完全防范。Markdown 是纯数据，不是代码——它只能"指导"Agent，不能"命令"系统。

2. **可编辑性**。Markdown 是人类可读的。用户可以用任何文本编辑器打开 `SKILL.md`，阅读并修改技能的行为。Python 代码的门槛要高得多。

3. **模型兼容性**。Skill 的本质是"给大语言模型看的指令"。Markdown 是大语言模型最擅长理解的格式之一。如果换成 Python，模型的"理解"准确率可能会下降。

### 权衡三：目录名作为标识 vs frontmatter 中的名字

你可能注意到了一个微妙的设计：Skill 的"名字"有两个来源。一个是目录名（如 `cron-en`），另一个是 frontmatter 中的 `name` 字段（如 `cron`）。

系统在运行时使用的是**目录名**，而不是 frontmatter 中的名字。`SkillInfo` 的 `name` 字段直接取自 `skill_dir.name`。

为什么要这样做？因为 frontmatter 是可以被修改的。如果用户不小心把 `name: cron` 改成了 `name: scheduler`，系统不应该因此找不到这个技能。目录名是文件系统级别的标识，更稳定、更不容易被意外修改。

frontmatter 中的 `name` 字段主要用于 zip 导入场景——当从压缩包导入技能时，系统会用它来确定技能的"逻辑名称"。

---

## 动手：阅读一个 Skill 的完整目录

这一章的动手环节很简单：选一个你感兴趣的 Skill，读遍它目录下的所有文件。

**步骤一：选择一个 Skill**

选择一个比较复杂的内置技能，比如 `pdf-en` 或 `xlsx-en`：

```bash
ls src/qwenpaw/agents/skills/pdf-en/
```

**步骤二：阅读 SKILL.md 的 frontmatter**

只看文件的前 10 行左右，理解这个技能声明了哪些元数据：

```bash
head -10 src/qwenpaw/agents/skills/pdf-en/SKILL.md
```

**步骤三：浏览 Markdown 正文**

通读 `SKILL.md` 的剩余部分。注意它的结构：什么时候用、怎么用、常见错误。试着从 Agent 的视角来理解——如果你是一个 AI Agent，收到这份指令后你会怎么做。

**步骤四：查看参考文档和脚本**

如果目录里有 `references/` 或 `scripts/` 子目录，浏览一下文件名列表：

```bash
ls src/qwenpaw/agents/skills/pdf-en/scripts/
```

这些文件名本身就是"文档"——它们告诉你这个技能在底层依赖哪些辅助操作。

**步骤五：对比两个语言变体**

挑一个技能，同时打开它的 `-en` 和 `-zh` 版本：

```bash
diff <(head -8 src/qwenpaw/agents/skills/cron-en/SKILL.md) \
     <(head -8 src/qwenpaw/agents/skills/cron-zh/SKILL.md)
```

你会发现 frontmatter 的结构完全相同，只是正文的语言不同。这验证了"技能内容是可本地化的"这一设计。

完成这个练习后，你应该能回答以下问题：

- 一个 Skill 目录中哪些文件是必需的，哪些是可选的？
- `SKILL.md` 的 YAML 部分声明了哪些字段，分别用于什么目的？
- `scripts/` 子目录里的文件在什么时候会被使用？
- 同一个技能的 `-en` 和 `-zh` 版本之间有什么异同？

---

## 卷二结语：设计模式的地图

这是第二卷的最后一章。

在过去的六章里，我们从第九章走到第十四章，逐步拆解了 QwenPaw 源码中的核心设计模式：

- **事件驱动与异步管道**：理解了消息如何在各层之间流动
- **Agent 工厂模式**：理解了配置驱动、按需创建的 Agent 生命周期
- **工具注册表模式**：理解了 Tool 怎么被发现、注册和调用
- **提示词拼装模式**：理解了系统提示词的分层组装策略
- **ReAct 循环模式**：理解了"思考-行动-观察"的迭代推理
- **插件架构模式**：理解了 Skill 的发现、加载、注册和热插拔

走到这里，你已经具备了一项关键能力：**拿到任何一个源码模块，都能快速定位它的设计模式，理解它的职责和边界**。

你可能还不能写出新模块——那是第三卷的内容。但你现在可以读懂任何一个模块，理解它为什么这样设计，以及它和系统的其他部分是怎么协作的。

第三卷，我们将从"阅读者"变成"建设者"。你将学会如何添加新的 Tool、新的 Skill、新的 Provider、新的 Channel——从零开始构建 QwenPaw 的新能力。

准备好了吗？
