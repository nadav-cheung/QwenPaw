# 《QwenPaw 实战与源码解读》重构方案

## 当前状态分析

### 现有结构问题

| 问题 | 描述 |
|------|------|
| 编号跳跃 | part4 有 07, 09, 18-27；缺少 08, 10-17 |
| 重复章节 | 23-Model系统 同时出现在 part4 和 part5 |
| 结构混乱 | Agent核心(18-27) 和 应用系统(23-67) 混在 part4/part5 |
| 依赖不清晰 | 前置知识引用混乱 |
| 新旧不匹配 | 00-书籍结构-新.md 提议的 Level 结构未实施 |

### 现有 book-published/ 结构

```
part1: 01-11 (编程基础)         ✅
part2: 11-1 到 11-6 (Python进阶) ✅
part3: 12-16 (QwenPaw入门)      ✅
part4: 07, 09, 18-27 (Agent核心) ⚠️ 编号混乱
part5: 23-67 (高级内容)         ⚠️ 内容混杂
part6: 29-36 (架构)             ⚠️ 部分内容重复
part7: 34-36 (DevOps)          ⚠️ 与part6重复
appendix: A1-A5                ✅
```

---

## 新结构设计

### 目录结构

```
teaching/
├── level-0-intro/           # Level 0: 前言与介绍
│   ├── 00-本书介绍.md
│   ├── 01-QwenPaw是什么.md
│   └── 02-源码架构概览.md
├── level-1-programming/      # Level 1: 编程基础
│   ├── 03-编程是什么.md
│   ├── 04-搭建Python环境.md
│   ├── 05-你好世界.md
│   ├── 06-变量和数据.md
│   ├── 07-条件和分支.md
│   ├── 08-循环.md
│   ├── 09-函数.md
│   ├── 10-列表和字典.md
│   ├── 11-面向对象.md
│   ├── 12-异常处理.md
│   └── 13-模块和包.md
├── level-2-getting-started/  # Level 2: QwenPaw入门
│   ├── 14-安装和运行.md
│   ├── 15-控制台使用.md
│   ├── 16-技能系统入门.md
│   └── 17-项目结构.md
├── level-3-agent-core/      # Level 3: 智能体核心
│   ├── 18-智能体架构.md
│   ├── 19-ReAct模式.md
│   ├── 20-工具系统.md
│   ├── 21-记忆系统.md
│   ├── 22-技能系统.md
│   ├── 23-Mission模式.md
│   ├── 24-模板与钩子.md
│   └── 25-多智能体协作.md
├── level-4-application/      # Level 4: 应用系统
│   ├── 26-FastAPI服务器.md
│   ├── 27-请求处理器.md
│   ├── 28-会话管理.md
│   ├── 29-消息渠道架构.md
│   ├── 30-渠道实现.md
│   └── 31-ACP协议.md
├── level-5-model-security/   # Level 5: 模型与安全
│   ├── 32-Provider系统.md
│   ├── 33-OpenAIProvider.md
│   ├── 34-本地模型Provider.md
│   ├── 35-安全架构.md
│   ├── 36-ToolGuard系统.md
│   ├── 37-密钥存储.md
│   └── 38-技能安全扫描.md
├── level-6-config-plugins/   # Level 6: 配置与插件
│   ├── 39-配置系统.md
│   └── 40-插件系统.md
├── level-7-cli-ops/          # Level 7: CLI与运维
│   ├── 41-CLI命令系统.md
│   ├── 42-定时任务.md
│   └── 43-部署与运维.md
├── level-8-contributor/     # Level 8: 贡献者指南
│   ├── 44-开发环境准备.md
│   ├── 45-贡献代码.md
│   └── 46-综合实战.md
└── appendix/                 # 附录
    ├── A-环境变量速查.md
    ├── B-CLI命令参考.md
    ├── C-源码结构速查.md
    ├── D-Python速查表.md
    └── E-错误代码速查.md
```

---

## 内容迁移映射

### Level 0: 前言与介绍

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 00 | 00-本书介绍.md | 新建 | - |
| 01 | 01-QwenPaw是什么.md | book-published/part3/12-QwenPaw是什么.md | `__version__.py`, `constant.py` |
| 02 | 02-源码架构概览.md | 新建 | 全部模块 |

### Level 1: 编程基础

| 新编号 | 新文件名 | 源文件 |
|--------|----------|--------|
| 03 | 03-编程是什么.md | book-published/part1/01-编程是什么.md |
| 04 | 04-搭建Python环境.md | book-published/part1/02-搭建Python环境.md |
| 05 | 05-你好世界.md | book-published/part1/03-你好世界.md |
| 06 | 06-变量和数据.md | book-published/part1/04-变量和数据.md |
| 07 | 07-条件和分支.md | book-published/part1/05-条件和分支.md |
| 08 | 08-循环.md | book-published/part1/06-循环.md |
| 09 | 09-函数.md | book-published/part1/07-函数.md |
| 10 | 10-列表和字典.md | book-published/part1/08-列表和字典.md |
| 11 | 11-面向对象.md | book-published/part1/09-面向对象.md |
| 12 | 12-异常处理.md | book-published/part1/10-异常处理.md |
| 13 | 13-模块和包.md | book-published/part1/11-模块和包.md |

### Level 2: QwenPaw入门

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 14 | 14-安装和运行.md | book-published/part3/13-安装和运行QwenPaw.md | `cli/main.py`, `cli/init_cmd.py` |
| 15 | 15-控制台使用.md | book-published/part3/14-使用QwenPaw.md | `app/server.py` |
| 16 | 16-技能系统入门.md | book-published/part3/15-技能系统.md | `agents/skills_manager.py` |
| 17 | 17-项目结构.md | book-published/part3/16-项目结构.md | 全部模块 |

### Level 3: 智能体核心

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 18 | 18-智能体架构.md | book-published/part4/07-智能体核心架构.md | `agents/react_agent.py` |
| 19 | 19-ReAct模式.md | 拆分自 18-智能体架构.md | `agents/react_agent.py` |
| 20 | 20-工具系统.md | book-published/part4/18-工具与记忆系统.md (工具部分) | `agents/tools/` |
| 21 | 21-记忆系统.md | book-published/part4/25-记忆系统深入.md | `agents/memory/` |
| 22 | 22-技能系统.md | book-published/part4/09-技能扩展系统.md | `agents/skills_manager.py`, `agents/skills_hub.py` |
| 23 | 23-Mission模式.md | book-published/part4/23-Mission模式详解.md | `agents/mission/` |
| 24 | 24-模板与钩子.md | book-published/part4/19-模板模型与钩子.md | `agents/templates.py`, `agents/hooks/` |
| 25 | 25-多智能体协作.md | book-published/part5/27-多智能体协作.md | `agents/multi_agent_manager.py` |

### Level 4: 应用系统

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 26 | 26-FastAPI服务器.md | book-published/part5/45-API路由系统详解.md (服务器部分) | `app/server.py` |
| 27 | 27-请求处理器.md | book-published/part5/26-请求处理与Runner.md | `app/runner/runner.py` |
| 28 | 28-会话管理.md | book-published/part5/47-会话与状态管理.md | `app/runner/session.py` |
| 29 | 29-消息渠道架构.md | book-published/part4/21-消息渠道系统.md | `app/channels/` |
| 30 | 30-渠道实现.md | book-published/part5/49-Console渠道详解.md | `app/channels/console/` |
| 31 | 31-ACP协议.md | book-published/part5/41-ACP智能体通信协议.md | `app/acp/` |

### Level 5: 模型与安全

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 32 | 32-Provider系统.md | book-published/part5/52-Provider系统深度解析.md | `providers/provider_manager.py` |
| 33 | 33-OpenAIProvider.md | book-published/part5/23-Model系统与LLM提供商.md | `providers/openai_provider.py` |
| 34 | 34-本地模型Provider.md | book-published/part5/38-本地模型管理系统.md | `providers/ollama_provider.py` |
| 35 | 35-安全架构.md | book-published/part5/24-安全系统详解.md | `security/` |
| 36 | 36-ToolGuard系统.md | book-published/part5/34-工具Guard安全系统.md | `security/tool_guard/` |
| 37 | 37-密钥存储.md | book-published/part5/37-密钥存储加密系统.md | `security/secret_store.py` |
| 38 | 38-技能安全扫描.md | book-published/part5/24-安全系统详解.md (扫描部分) | `security/skill_scanner/` |

### Level 6: 配置与插件

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 39 | 39-配置系统.md | book-published/part5/25-配置系统详解.md | `config/` |
| 40 | 40-插件系统.md | book-published/part4/26-插件系统.md | `plugins/` |

### Level 7: CLI与运维

| 新编号 | 新文件名 | 源文件 | 源码映射 |
|--------|----------|--------|----------|
| 41 | 41-CLI命令系统.md | book-published/part5/46-CLI命令系统详解.md | `cli/` |
| 42 | 42-定时任务.md | book-published/part6/33-定时任务与心跳.md | `agents/crons/` |
| 43 | 43-部署与运维.md | book-published/part5/28-部署与运维.md | `app/server.py` |

### Level 8: 贡献者指南

| 新编号 | 新文件名 | 源文件 |
|--------|----------|--------|
| 44 | 44-开发环境准备.md | book-published/part7/34-开发环境准备.md |
| 45 | 45-贡献代码.md | book-published/part7/35-贡献代码.md |
| 46 | 46-综合实战.md | book-published/part7/36-综合实战.md |

### 附录

| 新编号 | 新文件名 | 源文件 |
|--------|----------|--------|
| A | A-环境变量速查.md | book-published/appendix/A1-项目介绍.md (整合) |
| B | B-CLI命令参考.md | book-published/appendix/A2-快速开始.md (整合) |
| C | C-源码结构速查.md | book-published/appendix/A3-项目架构.md |
| D | D-Python速查表.md | book-published/appendix/A4-技能系统.md |
| E | E-错误代码速查.md | book-published/appendix/A5-消息渠道.md |

---

## 重组原则

### 1. 编号连续性
- Level 0: 00-02
- Level 1: 03-13 (11章)
- Level 2: 14-17 (4章)
- Level 3: 18-25 (8章)
- Level 4: 26-31 (6章)
- Level 5: 32-38 (7章)
- Level 6: 39-40 (2章)
- Level 7: 41-43 (3章)
- Level 8: 44-46 (3章)
- 附录: A-E

### 2. 依赖关系
```
Level 0 → Level 1 → Level 2 → Level 3 → Level 4 → Level 5 → Level 6 → Level 7 → Level 8
  ↓          ↓          ↓          ↓          ↓          ↓          ↓          ↓
Intro    Python基础  QwenPaw     Agent核心   应用系统    模型安全    配置插件    CLI运维
                               ↑
                               ├── 20-工具系统
                               ├── 21-记忆系统
                               └── 22-技能系统
```

### 3. 源码映射规则
每个章节必须明确标注对应的源码路径，格式：
```markdown
**源码路径**: `src/qwenpaw/<module>/<file>.py`
```

---

## 实施步骤

### Phase 1: 创建目录结构 ✅
- [x] 创建 level-0-intro 到 level-8-contributor 目录
- [x] 创建 appendix 目录

### Phase 2: 内容迁移 ✅
- [x] 迁移 Level 0 (00-02)
- [x] 迁移 Level 1 (03-13)
- [x] 迁移 Level 2 (14-17)
- [x] 迁移 Level 3 (18-25)
- [x] 迁移 Level 4 (26-31)
- [x] 迁移 Level 5 (32-38)
- [x] 迁移 Level 6 (39-40)
- [x] 迁移 Level 7 (41-43)
- [x] 迁移 Level 8 (44-46)
- [x] 迁移附录 (A-E)

### Phase 3: 链接更新 ✅ (部分完成)
- [x] 修复章节标题编号与文件名一致
- [x] 修复 level-0 目录内的相对路径
- [ ] 批量检查并修复跨级引用
- [ ] 更新所有"前置知识"引用
- [ ] 更新所有"下一章预告"引用

### Phase 4: 质量审查
- [ ] 源码一致性检查
- [ ] 教学路径检查
- [ ] 术语统一检查

---

*重构方案创建时间：2026-05-10*
*状态：准备实施*
