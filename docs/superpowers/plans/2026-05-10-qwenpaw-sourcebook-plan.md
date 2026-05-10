# QwenPaw 源码探秘 — 书籍撰写计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 写出《QwenPaw 源码探秘》全书（序章 + 26 章 + 附录），完成后删除旧的 teaching/ 目录。

**Architecture:** 新书存放在 `book/` 目录。每章为独立 markdown 文件，按 "问题→探索→实验→工程权衡→动手环节" 结构编写。从现有 teaching/ 中提取可复用的源码路径引用、Mermaid 图和调用链分析，以追踪式叙事重新组织。每章写完即 commit。

**Tech Stack:** Markdown + Mermaid 图表 + Python 代码示例

---

## 目录结构

```
book/
├── README.md                    # 全书导航
├── 00-序章-启程之前.md
├── volume-1/
│   ├── 01-消息怎么到达QwenPaw.md
│   ├── 02-谁负责处理这条消息.md
│   ├── 03-Agent醒来后第一件事做什么.md
│   ├── 04-Agent怎么思考.md
│   ├── 05-大模型怎么回答.md
│   ├── 06-如果要调用工具呢.md
│   ├── 07-回复怎么回到用户眼前.md
│   └── 08-像Contributor一样调试.md
├── volume-2/
│   ├── 09-源码目录是怎么组织的.md
│   ├── 10-QwenPawAgent为什么这样设计.md
│   ├── 11-系统提示词是怎么组装出来的.md
│   ├── 12-模型调用链怎么做到可替换.md
│   ├── 13-工具调用链怎么做到可扩展.md
│   └── 14-整个项目用了哪些设计模式.md
├── volume-3/
│   ├── 15-技能怎么给Agent装上超能力.md
│   ├── 16-工具怎么让Agent有手.md
│   ├── 17-怎么换个脑子换模型.md
│   ├── 18-Agent怎么通过不同渠道对话.md
│   └── 19-怎么把扩展打包成插件.md
├── volume-4/
│   ├── 20-怎么防止Agent执行危险命令.md
│   ├── 21-所有配置项怎么协调工作.md
│   ├── 22-Agent的记忆怎么管理.md
│   ├── 23-多个Agent怎么协作.md
│   ├── 24-QwenPaw怎么部署和运维.md
│   ├── 25-怎么保证改了代码不坏.md
│   └── 26-从读者到Contributor.md
└── appendix/
    ├── A-环境变量速查.md
    ├── B-CLI命令参考.md
    ├── C-源码结构速查.md
    └── D-错误代码速查.md
```

## 每章写作模板

每章必须按以下 5 节结构编写，不可省略任何一节。

```markdown
# [章号] [追问式标题]

> 本章追踪的源码文件：[列出主要文件路径]

## 问题

[一章开头先提出一个具体的追问，让读者产生好奇心。200-400 字。]

## 探索

[沿源码追踪，展示真实调用链。包含代码引用（标注行号）、Mermaid 时序图/类图。这是本章主体，2000-4000 字。]

## 实验

[读者可以自己跑的验证命令：curl、pytest、Python 断点、日志搜索。每个实验附带预期的输出。]

## 工程权衡

[为什么这里这样设计？当初的 trade-off 是什么？200-500 字。]

## 动手环节

[本章对应的 Contributor 技能练习。具体的、可完成的、有成果输出的任务。]
```

## 源码素材映射

在写每章之前，先读取对应的 teaching/ 文件，提取可复用的源码路径、Mermaid 图和调用链分析。

### 序章
- **素材**: `teaching/level-2-getting-started/14-安装和运行.md`, `teaching/level-0-intro/01-QwenPaw是什么.md`
- **复用**: 安装命令、配置步骤、URL 引用

### 卷一（第 1-8 章）

| 新章 | 素材文件 |
|------|---------|
| 01-消息怎么到达QwenPaw | `teaching/level-4-application/26-FastAPI服务器.md` |
| 02-谁负责处理这条消息 | `teaching/level-4-application/27-请求处理器.md`, `28-会话管理.md` |
| 03-Agent醒来后第一件事做什么 | `teaching/level-3-agent-core/18-智能体架构.md` (init 段) |
| 04-Agent怎么思考 | `teaching/level-3-agent-core/19-ReAct模式.md` |
| 05-大模型怎么回答 | `teaching/level-5-model-security/32-Provider系统.md` |
| 06-如果要调用工具呢 | `teaching/level-3-agent-core/20-工具系统.md` |
| 07-回复怎么回到用户眼前 | `teaching/level-4-application/27-请求处理器.md` (streaming), `30-渠道实现.md` |
| 08-像Contributor一样调试 | `teaching/level-8-contributor/44-开发环境准备.md` |

### 卷二（第 9-14 章）

| 新章 | 素材文件 |
|------|---------|
| 09-源码目录是怎么组织的 | `teaching/level-0-intro/02-源码架构概览.md`, `appendix/C-源码结构速查.md` |
| 10-QwenPawAgent为什么这样设计 | `teaching/level-3-agent-core/18-智能体架构.md` (MRO/design) |
| 11-系统提示词是怎么组装出来的 | `teaching/level-3-agent-core/24-模板与钩子.md` |
| 12-模型调用链怎么做到可替换 | `teaching/level-5-model-security/32-Provider系统.md`, `33-OpenAIProvider.md`, `34-本地模型Provider.md` |
| 13-工具调用链怎么做到可扩展 | `teaching/level-3-agent-core/20-工具系统.md` |
| 14-整个项目用了哪些设计模式 | 综合多章素材 |

### 卷三（第 15-19 章）

| 新章 | 素材文件 |
|------|---------|
| 15-技能怎么给Agent装上超能力 | `teaching/level-3-agent-core/22-技能系统.md`, `appendix/D-技能系统.md` |
| 16-工具怎么让Agent有手 | `teaching/level-3-agent-core/20-工具系统.md` |
| 17-怎么换个脑子换模型 | `teaching/level-5-model-security/32-Provider系统.md`, `33-OpenAIProvider.md` |
| 18-Agent怎么通过不同渠道对话 | `teaching/level-4-application/29-消息渠道架构.md`, `30-渠道实现.md` |
| 19-怎么把扩展打包成插件 | `teaching/level-6-config-plugins/40-插件系统.md` |

### 卷四（第 20-26 章）

| 新章 | 素材文件 |
|------|---------|
| 20-怎么防止Agent执行危险命令 | `teaching/level-5-model-security/35-安全架构.md`, `36-ToolGuard系统.md` |
| 21-所有配置项怎么协调工作 | `teaching/level-6-config-plugins/39-配置系统.md` |
| 22-Agent的记忆怎么管理 | `teaching/level-3-agent-core/21-记忆系统.md` |
| 23-多个Agent怎么协作 | `teaching/level-3-agent-core/25-多智能体协作.md`, `23-Mission模式.md` |
| 24-QwenPaw怎么部署和运维 | `teaching/level-7-cli-ops/41-CLI命令系统.md`, `42-定时任务.md`, `43-部署与运维.md` |
| 25-怎么保证改了代码不坏 | `teaching/level-8-contributor/44-开发环境准备.md`, `45-贡献代码.md` |
| 26-从读者到Contributor | `teaching/level-8-contributor/45-贡献代码.md`, `46-综合实战.md` |

### 附录

- **A** — 从 `teaching/appendix/A-环境变量速查.md` 精炼
- **B** — 从 `teaching/appendix/B-CLI命令参考.md` 精炼
- **C** — 从 `teaching/appendix/C-源码结构速查.md` 精炼
- **D** — 从 `teaching/appendix/E-错误代码速查.md` 精炼（原 D 技能系统内容并入第 15 章）

## 写作顺序与并行策略

```
阶段0: 创建目录结构 + 写 README.md
  ↓
阶段1: 序章 (需先写，定位全书基调)
  ↓
阶段2: 卷一 8 章 (可以 2 个 Agent 并行，各负责 4 章)
  ↓  [卷一完稿后，回顾风格一致性]
阶段3: 卷二 6 章 (可以 2 个 Agent 并行，各负责 3 章)
  ↓
阶段4: 卷三 5 章 (可以 2 个 Agent 并行)
  ↓
阶段5: 卷四 7 章 (可以 2 个 Agent 并行)
  ↓
阶段6: 附录 4 篇 (可以 2 个 Agent 并行)
  ↓
阶段7: 全书审校 + 删除 teaching/ 目录
```

每写完一卷，人工审阅风格一致性后再继续下一卷。

---
