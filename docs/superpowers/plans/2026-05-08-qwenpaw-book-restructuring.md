# QwenPaw 书籍重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 78 个 teaching 文件重构为《QwenPaw 智能体开发实战》可发版书籍

**Architecture:** 三篇结构（入门篇 5-8 章 → 进阶篇 15-20 章 → 实战篇 3-5 章），新编号体系（1.1, 1.2, 2.1...），输出到 `docs/book/`

**Tech Stack:** Markdown, MKDocs (用于最终渲染)

---

## 阶段划分

```
Phase 1: 分析与规划（1-2 天）
├── Task 1: 扫描 78 个文件，建立问题清单
├── Task 2: 制定章节映射表（原编号 → 新编号）
└── Task 3: 创建目录结构

Phase 2: 入门篇重构（3-4 天）
├── Task 4: 重构 1.1 QwenPaw 概述
├── Task 5: 重构 1.2 环境搭建
├── Task 6: 重构 1.3 Python 指南
├── Task 7: 重构 1.4 智能体核心概念
├── Task 8: 重构 1.5 技能系统入门
└── Task 9: 重构 1.6 消息渠道基础

Phase 3: 进阶篇重构（10-14 天）
├── Task 10: 重构 2.1 Agent 核心架构
├── Task 11: 重构 2.2 Runner 与请求处理
├── Task 12: 重构 2.3 Memory 记忆系统
├── Task 13: 重构 2.4 Provider 与模型层
├── Task 14: 重构 2.5 Channel 消息渠道
├── Task 15: 重构 2.6 Guard 安全系统
├── Task 16: 重构 2.7 Skill 技能系统
├── Task 17: 重构 2.8 MCP 扩展机制
├── Task 18: 重构 2.9 Plugin 插件系统
├── Task 19: 重构 2.10 多智能体协作
├── Task 20: 重构 2.11 消息路由与分发
├── Task 21: 重构 2.12 定时任务与心跳
├── Task 22: 重构 2.13 生命周期管理
├── Task 23: 重构 2.14 配置热重载
└── Task 24: 重构 2.15 密钥与安全

Phase 4: 实战篇编写（5-7 天）
├── Task 25: 编写 3.1 个人资讯助手
├── Task 26: 编写 3.2 智能客服系统
├── Task 27: 编写 3.3 自动化工作流
└── Task 28: 编写 3.4 企业知识库问答

Phase 5: 附录与收尾（2-3 天）
├── Task 29: 编写附录 A-E
├── Task 30: 创建目录索引
└── Task 31: 交叉评审与修正

Phase 6: 发布准备（1-2 天）
├── Task 32: 配置 MKDocs
└── Task 33: 生成 HTML 预览
```

---

## Task 1: 扫描 78 个文件，建立问题清单

**目标:** 全面了解现有文件状况，建立优化问题数据库

**文件:**
- 创建: `docs/book/ANALYSIS.md` - 问题清单汇总

**步骤:**

- [ ] **Step 1: 扫描所有 teaching 文件**

```bash
# 统计文件数量
ls teaching/*.md | wc -l

# 列出所有文件及大小
ls -la teaching/*.md

# 提取每个文件的标题、前置知识、难度等级
for f in teaching/*.md; do
  echo "=== $f ==="
  head -20 "$f" | grep -E "^\#|学习目标|前置知识|预计时长|难度等级"
done
```

- [ ] **Step 2: 识别重复内容**

```bash
# 检查疑似重复的章节
# 28 vs 51 (Workspace 隔离)
# 22 vs 100 (架构设计)
# 65 vs 40 (FastAPI)
# 71 vs 85 (模型探测)
```

- [ ] **Step 3: 建立问题清单文档**

在 `docs/book/ANALYSIS.md` 中记录：
- 每个文件的状态（待优化/可直接迁移/需合并）
- 发现的具体问题（格式/内容/错误/重复）
- 源码路径有效性检查

- [ ] **Step 4: 提交**

```bash
git add docs/book/ANALYSIS.md
git commit -m "docs: add initial analysis of teaching files"
```

**验收标准:** `docs/book/ANALYSIS.md` 包含所有 78 个文件的问题清单

---

## Task 2: 制定章节映射表（原编号 → 新编号）

**目标:** 建立清晰的原章节到新书籍章节的映射关系

**文件:**
- 创建: `docs/book/CHAPTER_MAPPING.md`

**步骤:**

- [ ] **Step 1: 创建映射表**

```markdown
# 章节映射表

## 入门篇

| 新编号 | 原编号 | 标题 | 状态 |
|--------|--------|------|------|
| 1.1 | 01 | 项目介绍 | 待重构 |
| 1.2 | 02 | 快速开始 | 待重构 |
| 1.3 | 06 | Python基础教程 | 待重构 |
| 1.4 | 07 | 智能体核心架构 | 待重构 |
| 1.5 | 04 | 技能系统 | 待重构 |
| 1.6 | 05 | 消息渠道 | 待重构 |

## 进阶篇

| 新编号 | 原编号 | 标题 | 状态 |
|--------|--------|------|------|
| 2.1 | 07 | Agent核心架构（精选） | 待重构 |
| 2.2 | 21 | Runner与请求处理 | 待重构 |
| ... | ... | ... | ... |
```

- [ ] **Step 2: 提交**

```bash
git add docs/book/CHAPTER_MAPPING.md
git commit -m "docs: add chapter mapping table"
```

**验收标准:** `docs/book/CHAPTER_MAPPING.md` 包含所有章节的一一映射

---

## Task 3: 创建目录结构

**目标:** 建立 `docs/book/` 的完整目录框架

**文件:**
- 创建: `docs/book/` 目录结构

**步骤:**

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p docs/book/{frontmatter,part1-intro,part2-advanced/{core,collaboration},part3-project,appendix}
```

- [ ] **Step 2: 创建 README.md**

在 `docs/book/README.md` 中包含：
- 书籍简介
- 目录结构说明
- 阅读指南
- 贡献方式

- [ ] **Step 3: 创建书籍元数据**

```yaml
# docs/book/book.yml
title: "QwenPaw智能体开发实战"
subtitle: "Java开发者的AI Agent转型指南"
version: "1.0.0"
status: "draft"
author: "QwenPaw Community"
```

- [ ] **Step 4: 提交**

```bash
git add docs/book/
git commit -m "docs: create book directory structure"
```

**验收标准:** `docs/book/` 目录结构完整，可通过 MKDocs 渲染

---

## Task 4-9: 入门篇重构（6 个任务）

**通用模式 (以 Task 4 为例):**

### Task 4: 重构 1.1 QwenPaw 概述

**文件:**
- 创建: `docs/book/part1-intro/1.1-qwenpaw-overview.md`
- 参考: `teaching/01-项目介绍.md`, `teaching/03-项目架构.md`

**步骤:**

- [ ] **Step 1: 阅读原文件，提取核心内容**

读取 `teaching/01-项目介绍.md` 和 `teaching/03-项目架构.md`，确定需要迁移的内容。

- [ ] **Step 2: 按新模板重写**

使用标准章节模板：
```markdown
# 第 1.1 章 QwenPaw 概述

## 本章导览

| 项目 | 内容 |
|------|------|
| **学习目标** | 1) ... 2) ... 3) ... |
| **前置知识** | 无 |
| **预计时长** | XX 分钟 |
| **难度等级** | ⭐ |
| **核心关键词** | `关键词1` `关键词2` |

> **本章概述**：...

---

## 1. 概念引入

## 2. 源码分析

## 3. 实战应用

## 4. 常见问题

## 5. 知识检查

## 本章小结

## 延伸阅读
```

- [ ] **Step 3: 验证内容准确性**

对照 `src/qwenpaw/` 源码验证描述是否准确。

- [ ] **Step 4: 提交**

```bash
git add docs/book/part1-intro/1.1-qwenpaw-overview.md
git commit -m "docs(book): add chapter 1.1 QwenPaw overview"
```

---

**类似执行 Task 5-9:**
- Task 5: 重构 1.2 环境搭建（来源：02-快速开始.md）
- Task 6: 重构 1.3 Python 指南（来源：06-Python基础教程.md + 06.1-Python进阶教程.md）
- Task 7: 重构 1.4 智能体核心概念（来源：07-智能体核心架构.md）
- Task 8: 重构 1.5 技能系统入门（来源：04-技能系统.md + 09-技能扩展系统.md）
- Task 9: 重构 1.6 消息渠道基础（来源：05-消息渠道.md + 08-消息渠道系统.md）

**每任务验收标准:** 
- 新编号文件存在
- 内容符合模板规范
- 源码路径有效
- 提交记录完整

---

## Task 10-24: 进阶篇重构（15 个任务）

**通用模式:**

### Task 10: 重构 2.1 Agent 核心架构

**文件:**
- 创建: `docs/book/part2-advanced/core/2.1-agent-core.md`
- 参考: `teaching/07-智能体核心架构.md`, `teaching/23-智能体钩子系统.md`

**步骤:**

- [ ] **Step 1: 阅读原文件**

读取相关源文件，分析需要合并/精简的内容。

- [ ] **Step 2: 按新模板重写，侧重原理**

```markdown
# 第 2.1 章 Agent 核心架构

## 本章导览

| 项目 | 内容 |
|------|------|
| **学习目标** | 1) 分析 Agent 的初始化流程... |
| **前置知识** | 第 1.4 章 |
| **预计时长** | XX 分钟 |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `ReAct` `QwenPawAgent` `Toolkit` |

---

## 1. 概念引入

### 1.1 ReAct 模式
...

### 1.2 类层次结构
...

## 2. 源码分析

### 2.1 QwenPawAgent 核心类
**源码路径**: `src/qwenpaw/agents/react_agent.py:1`

```python
# 关键代码片段（不超过 50 行）
```

### 2.2 初始化流程
...

## 3. 设计意图

### 3.1 为什么这样设计
...

### 3.2 权衡取舍
...

## 4. 常见问题

## 5. 知识检查

## 本章小结
```

- [ ] **Step 3: 提交**

```bash
git add docs/book/part2-advanced/core/2.1-agent-core.md
git commit -m "docs(book): add chapter 2.1 Agent core architecture"
```

---

**类似执行 Task 11-24:**

| 任务 | 新编号 | 标题 | 主要来源 |
|------|--------|------|---------|
| Task 11 | 2.2 | Runner 与请求处理 | 21-请求处理与Runner.md |
| Task 12 | 2.3 | Memory 记忆系统 | 12-记忆系统深入.md, 32-记忆管理系统.md |
| Task 13 | 2.4 | Provider 与模型层 | 11-Model系统与LLM提供商.md, 82-Provider系统深度解析.md |
| Task 14 | 2.5 | Channel 消息渠道 | 08-消息渠道系统.md, 64-消息系统详解.md |
| Task 15 | 2.6 | Guard 安全系统 | 19-安全系统详解.md, 38-工具Guard安全系统.md |
| Task 16 | 2.7 | Skill 技能系统 | 09-技能扩展系统.md, 04-技能系统.md |
| Task 17 | 2.8 | MCP 扩展机制 | 13-MCP系统.md, 34-MCP模块.md |
| Task 18 | 2.9 | Plugin 插件系统 | 18-插件系统.md, 27-应用启动与插件系统.md |
| Task 19 | 2.10 | 多智能体协作 | 14-多智能体协作.md, 58-ACP智能体通信协议.md |
| Task 20 | 2.11 | 消息路由与分发 | 77-跨渠道消息路由.md |
| Task 21 | 2.12 | 定时任务与心跳 | 17-心跳系统.md, 25-定时任务与心跳.md |
| Task 22 | 2.13 | 生命周期管理 | 94-生命周期管理.md, 65-FastAPI应用结构与启动流程.md |
| Task 23 | 2.14 | 配置热重载 | 37-配置热重载机制.md, 86-热重载机制详解.md |
| Task 24 | 2.15 | 密钥与安全 | 39-密钥存储加密系统.md, 89-加密与密钥管理.md |

---

## Task 25-28: 实战篇编写

### Task 25: 编写 3.1 个人资讯助手

**文件:**
- 创建: `docs/book/part3-project/3.1-personal-news-assistant.md`

**步骤:**

- [ ] **Step 1: 设计项目架构**

```
项目：个人资讯助手
功能：
  - 定时抓取科技/新闻网站
  - AI 摘要生成
  - 多渠道推送（飞书/钉钉/邮件）
技术栈：
  - QwenPaw Agent
  - MCP Server（网页抓取）
  - Channel（消息推送）
  - Cron（定时任务）
```

- [ ] **Step 2: 编写完整项目文档**

```markdown
# 第 3.1 章 个人资讯助手

## 项目概述

### 功能需求
...

### 技术方案
...

## 实现步骤

### 步骤 1: 环境准备
...

### 步骤 2: 配置 MCP 工具
...

### 步骤 3: 实现摘要生成
...

### 步骤 4: 配置定时任务
...

### 步骤 5: 配置消息渠道
...

## 完整代码

### config.yaml
```yaml
...
```

### agent.py
```python
...
```

## 运行与测试

### 测试用例
...

### 常见问题
...
```

- [ ] **Step 3: 提交**

```bash
git add docs/book/part3-project/3.1-personal-news-assistant.md
git commit -m "docs(book): add project 3.1 personal news assistant"
```

---

**类似执行 Task 26-28:**
- Task 26: 编写 3.2 智能客服系统
- Task 27: 编写 3.3 自动化工作流
- Task 28: 编写 3.4 企业知识库问答

---

## Task 29: 编写附录 A-E

**文件:**
- 创建: `docs/book/appendix/`

**步骤:**

- [ ] **Step 1: 附录 A - Python 快速参考**

```markdown
# 附录 A: Python 快速参考

## A.1 常用语法速查

| Python | Java | 说明 |
|--------|------|------|
| `def foo(x):` | `void foo(Type x) {}` | 函数定义 |
| `x if cond else y` | `cond ? x : y` | 三元表达式 |
| `with open(f) as fh:` | `try (...)` | 上下文管理 |
| ... | ... | ... |

## A.2 异步编程
...

## A.3 类型提示
...
```

- [ ] **Step 2: 附录 B-F**

类似结构创建：
- B: 配置项索引
- C: 命令行参考
- D: 源码目录结构
- E: 常见问题解答

- [ ] **Step 3: 提交**

```bash
git add docs/book/appendix/
git commit -m "docs(book): add appendices A-E"
```

---

## Task 30: 创建目录索引

**文件:**
- 创建: `docs/book/SUMMARY.md`

**步骤:**

- [ ] **Step 1: 生成完整目录**

```markdown
# 《QwenPaw 智能体开发实战》目录

## 前言
...

## 第一篇：入门篇

### 第 1.1 章 QwenPaw 概述
### 第 1.2 章 环境搭建
...

## 第二篇：进阶篇

### 核心机制

#### 第 2.1 章 Agent 核心架构
...

#### 第 2.2 章 Runner 与请求处理
...

### 协作机制

#### 第 2.10 章 多智能体协作
...

## 第三篇：实战篇

### 第 3.1 章 个人资讯助手
...

## 附录

### 附录 A: Python 快速参考
...
```

- [ ] **Step 2: 提交**

```bash
git add docs/book/SUMMARY.md
git commit -m "docs(book): add book summary table of contents"
```

---

## Task 31: 交叉评审与修正

**目标:** 全面审查，发现并修正问题

**步骤:**

- [ ] **Step 1: 检查所有源码路径**

```bash
# 提取所有源码路径
grep -rh "源码路径" docs/book/ | sed 's/.*`\(.*\)`.*/\1/' | sort -u

# 验证路径是否存在
for path in $(grep -rh "源码路径" docs/book/ | sed 's/.*`\(.*\)`.*/\1/'); do
  if [ ! -e "$path" ] && [ ! -e "src/$path" ]; then
    echo "MISSING: $path"
  fi
done
```

- [ ] **Step 2: 检查交叉引用**

```bash
# 检查所有延伸阅读链接是否有效
grep -rh "\.\.\/" docs/book/ | grep "\.md" | sort -u
```

- [ ] **Step 3: 格式一致性检查**

确保所有章节使用相同模板。

- [ ] **Step 4: 提交修正**

```bash
git add docs/book/
git commit -m "docs(book): fix cross-review issues"
```

---

## Task 32: 配置 MKDocs

**文件:**
- 创建: `docs/book/mkdocs.yml`

**步骤:**

- [ ] **Step 1: 创建 MKDocs 配置**

```yaml
site_name: QwenPaw智能体开发实战
theme:
  name: material
  language: zh
  features:
    - navigation.tabs
    - navigation.sections
    - toc.integrate

nav:
  - 简介: index.md
  - 第一篇：入门篇:
    - 1.1 QwenPaw 概述: part1-intro/1.1-qwenpaw-overview.md
    ...
  - 第二篇：进阶篇:
    ...
  - 第三篇：实战篇:
    ...
  - 附录:
    ...
```

- [ ] **Step 2: 本地预览测试**

```bash
cd docs/book
pip install mkdocs mkdocs-material
mkdocs serve
```

- [ ] **Step 3: 提交**

```bash
git add docs/book/mkdocs.yml
git commit -m "docs(book): add MKDocs configuration"
```

---

## Task 33: 生成 HTML 预览

**目标:** 生成可预览的 HTML 版本

**步骤:**

- [ ] **Step 1: 构建 HTML**

```bash
cd docs/book
mkdocs build --clean
```

- [ ] **Step 2: 本地验证**

```bash
# 检查输出
ls site/
```

- [ ] **Step 3: GitHub Pages 部署（如需要）**

```bash
mkdocs gh-deploy
```

- [ ] **Step 4: 最终提交**

```bash
git add docs/book/
git commit -m "docs(book): complete book restructuring - v1.0"
git tag -a v1.0 -m "Book v1.0 release"
git push origin main --tags
```

---

## 实施检查清单

### Phase 1 完成标志
- [ ] `docs/book/ANALYSIS.md` 存在且完整
- [ ] `docs/book/CHAPTER_MAPPING.md` 映射表完整
- [ ] `docs/book/` 目录结构创建完成

### Phase 2 完成标志
- [ ] 入门篇 6 个章节全部完成
- [ ] 所有文件使用统一模板
- [ ] 所有源码路径有效

### Phase 3 完成标志
- [ ] 进阶篇 15 个章节全部完成
- [ ] 原理优先，代码片段不超过 50 行
- [ ] 消除重复内容

### Phase 4 完成标志
- [ ] 实战篇 4 个项目全部完成
- [ ] 每个项目包含完整可运行的代码示例
- [ ] 包含测试验证步骤

### Phase 5 完成标志
- [ ] 附录 A-E 全部完成
- [ ] `SUMMARY.md` 目录索引完整
- [ ] 交叉评审问题已修正

### Phase 6 完成标志
- [ ] MKDocs 配置完成
- [ ] HTML 预览可正常访问
- [ ] Git tag v1.0 已创建

---

## 风险与应对

| 风险 | 影响 | 应对方案 |
|------|------|---------|
| 78 个文件优化工作量巨大 | 时间超出预期 | 优先处理核心章节，非核心章节简化处理 |
| 源码路径可能过时 | 内容失效 | CI 自动检查路径有效性 |
| 实战项目代码量大 | 维护成本高 | 使用 GitHub Codespaces，降低读者门槛 |
| 多文件交叉引用复杂 | 链接失效 | 自动化检查脚本验证所有链接 |

---

*计划版本: 1.0*
*创建日期: 2026-05-08*
*状态: 待执行*
