# QwenPaw 源码探秘——设计规格书

> 日期：2026-05-10
> 状态：已批准

## 概述

写一本类似《网络是怎么连接的》风格的源码分析书，面向刚学完 Python 语法的初学者。主线是一条消息从浏览器出发，穿过 HTTP、路由、调度、Agent、LLM、工具层，最终回到屏幕。每到一站停下来深入讲解原理。

## 目标读者

刚学完 Python 语法，没有实际项目经验的初学者。不假设了解 FastAPI、异步编程、设计模式。遇到这些概念时在正文中自然引入并用图解讲透。

## 定位

完全独立成书，不假设读者读过 `teaching/` 目录中的教学书。

## 覆盖范围

Python 后端源码为主（`src/qwenpaw/`，411 个 Python 文件，约 13 万行）。前端（React 控制台）仅作为请求入口简单介绍。

## 篇幅目标

25 万字以上。26 章 + 附录，每章 8000-12000 字。

## 写作风格

图文并茂的原理讲解。每章围绕一个追问展开，用 ASCII 艺术图解讲清原理。类似《网络是怎么连接的》风格。

## 图解策略

全部使用 ASCII 艺术图，内嵌在 Markdown 中。每章至少 2-3 个核心图解：

- 流程图（请求走向）
- 架构图（模块关系）
- 时序图（调用顺序）
- 类图（继承/组合关系）

## 每章结构

每章包含五个部分：

1. **问题** — 一个让你产生好奇心的追问
2. **探索** — 沿源码追踪，展示真实调用链
3. **实验** — 读者可以自己跑的验证命令
4. **工程权衡** — 为什么这样设计？trade-off 是什么？
5. **动手环节** — 本章对应的 Contributor 技能练习

## 全书结构

### 叙事弧线

| 卷 | 主题 | 比喻 | 读完能做什么 | 章节 |
|---|---|---|---|---|
| 序章 | 安装与准备 | 出发前的装备检查 | 安装好 QwenPaw | 序章 |
| 卷一·启程 | 跟踪一条请求 | 像跟着一封信走过邮局、分拣中心、邮递员 | 能追踪请求流程、定位 bug、修小问题 | Ch 1-8 |
| 卷二·图纸 | 看懂设计模式 | 像看建筑蓝图，理解为什么这面墙在这 | 能理解设计模式、读懂任意模块 | Ch 9-14 |
| 卷三·工坊 | 动手造新模块 | 像给这栋楼加一间新房间——接好水电管线 | 能独立添加新功能模块 | Ch 15-19 |
| 卷四·纵深 | 理解工程权衡 | 像理解为什么选了钢结构而非混凝土 | 能参与架构讨论、理解设计权衡 | Ch 20-26 |
| 附录 | 速查参考 | 工具箱 | 随时翻阅 | A-D |

### 主线

用户在浏览器输入「你好，你能做什么？」，按下回车。跟着这句话穿过：

```
浏览器 → HTTP 请求 → FastAPI 路由 → Runner 调度 → Agent 创建
→ Prompt 拼装 → ReAct 循环 → LLM 调用 → Tool 执行 → SSE 响应 → 浏览器渲染
```

## 章节大纲

### 序章：启程之前

安装 QwenPaw、配置模型、发送第一条消息。为后续章节做准备。

---

### 卷一·启程（第 1-8 章）

#### 第 1 章：浏览器按下回车之后

- **问题**：你按下回车，浏览器做了什么？HTTP 请求是怎么到达 Python 代码的？
- **停留层**：HTTP → FastAPI
- **关键文件**：`_app.py`、`routers/console.py`
- **原理讲解**：HTTP 请求/响应模型、FastAPI 路由机制、中间件链（认证、Agent 上下文注入）、SSE 流式传输入门
- **图解**：请求从浏览器到 FastAPI 的完整路径图、中间件洋葱模型图
- **动手**：用 `curl` 发一条请求，观察 FastAPI 日志

#### 第 2 章：请求到达 Runner

- **问题**：FastAPI 收到请求后，怎么找到正确的 Agent 来处理？
- **停留层**：Runner 调度层
- **关键文件**：`runner/runner.py`、`runner/manager.py`、`multi_agent_manager.py`
- **原理讲解**：Manager 模式、命令分发（`/` 命令 vs 普通消息）、Session 的概念
- **图解**：Runner 调度流程图、Session 生命周期图
- **动手**：启动时观察 Runner 日志

#### 第 3 章：Agent 的诞生

- **问题**：Agent 是什么？它是怎么被创建出来的？
- **停留层**：Agent 实例化
- **关键文件**：`agents/react_agent.py`、`agents/model_factory.py`
- **原理讲解**：面向对象基础（类、实例、继承）、工厂模式、Mixin 入门
- **图解**：Agent 继承链图、ModelFactory 创建流程图
- **动手**：在源码中找到 Agent 创建的代码行

#### 第 4 章：系统提示词的拼装

- **问题**：Agent 怎么知道自己是"谁"？它怎么知道自己能做什么？
- **停留层**：Prompt 组装
- **关键文件**：`agents/prompt.py`、工作目录下的 `agent.md`
- **原理讲解**：系统提示词的作用和结构、模板拼装、工作区概念
- **图解**：Prompt 拼装流程图、最终 Prompt 结构图
- **动手**：修改自己的 `agent.md`，观察提示词变化

#### 第 5 章：进入 ReAct 循环

- **问题**：Agent 收到消息后做了什么？为什么不是直接回答，而是"思考→行动→观察→再思考"？
- **停留层**：ReAct 推理循环
- **关键文件**：agentscope 的 `ReActAgent`、`agents/react_agent.py` 中的重写方法
- **原理讲解**：ReAct 模式（Reasoning + Acting）、消息队列机制、循环终止条件
- **图解**：ReAct 循环时序图、思考→行动→观察的流转图
- **动手**：发送需要工具调用的消息，观察 ReAct 循环日志

#### 第 6 章：调用大语言模型

- **问题**：Agent 的"思考"其实是把提示词发给 LLM。这个调用是怎么发生的？
- **停留层**：LLM API 调用
- **关键文件**：`providers/provider.py`、`providers/openai_provider.py`
- **原理讲解**：Provider 抽象层、API 调用流程、流式响应（Streaming）、Token 计费概念
- **图解**：Provider 抽象层架构图、API 调用时序图
- **动手**：切换不同的 Provider，观察日志差异

#### 第 7 章：工具的执行

- **问题**：LLM 回复说"我需要执行一个 Shell 命令"，然后呢？
- **停留层**：Tool 执行 + 安全检查
- **关键文件**：`agents/tools/` 目录、`agents/tool_guard_mixin.py`
- **原理讲解**：Function Calling 机制、工具注册表、安全围栏（ToolGuard）
- **图解**：工具调用流程图、ToolGuard 检查链图
- **动手**：让 Agent 执行一个安全的工具调用，观察日志

#### 第 8 章：响应的归途

- **问题**：Agent 生成回复后，怎么回到浏览器的？为什么能看到逐字输出？
- **停留层**：响应流式传输 → 浏览器渲染
- **关键文件**：`runner/runner.py`（流式输出部分）、`routers/console.py`（SSE 端点）
- **原理讲解**：消息队列到 SSE 的转换、流式输出实现、完整请求生命周期回顾
- **图解**：完整请求生命周期全景图（串联前 8 章所有站点）
- **动手**：用浏览器开发者工具观察 SSE 事件流

---

### 卷二·图纸（第 9-14 章）

#### 第 9 章：源码的地图

- **问题**：`src/qwenpaw/` 下面有十几个文件夹，它们之间是什么关系？
- **关键文件**：整个 `src/qwenpaw/` 目录结构
- **原理讲解**：模块化单体架构、包的职责划分、依赖方向
- **图解**：源码模块全景图、洋葱架构层视图

#### 第 10 章：Agent 的身世——Mixin 与继承

- **问题**：为什么 QwenPawAgent 中间插了一个 ToolGuardMixin？
- **关键文件**：`react_agent.py`、`tool_guard_mixin.py`、agentscope 的 `ReActAgent`
- **原理讲解**：MRO（方法解析顺序）、Mixin vs 继承 vs 组合、开放封闭原则
- **图解**：Agent 类继承链图、Mixin 注入能力示意图

#### 第 11 章：Provider 的棋局——策略模式与抽象层

- **问题**：为什么 Agent 不直接调用 OpenAI 的 SDK？
- **关键文件**：`providers/provider.py`、`providers/openai_provider.py`、`providers/provider_manager.py`
- **原理讲解**：策略模式、抽象基类（ABC）、工厂 + 策略组合
- **图解**：Provider 抽象层类图、策略切换流程图

#### 第 12 章：Channel 的变装——适配器模式

- **问题**：同一个 Agent 怎么同时接入钉钉、飞书、Telegram、Discord？
- **关键文件**：`app/channels/base.py`、`app/channels/manager.py`、两个具体 Channel 实现
- **原理讲解**：适配器模式、BaseChannel 契约、注册表模式
- **图解**：Channel 适配器模式图、消息格式转换流程图

#### 第 13 章：Security 的围栏——拦截器与规则引擎

- **问题**：如果 Agent 想执行 `rm -rf /`，系统怎么拦住它？
- **关键文件**：`security/tool_guard/engine.py`、`security/skill_scanner/scanner.py`、`security/secret_store.py`
- **原理讲解**：拦截器模式、规则引擎、纵深防御、Skill 安全扫描
- **图解**：ToolGuard 检查链图、安全围栏全景图

#### 第 14 章：Skills 的工坊——插件架构

- **问题**：为什么 Skill 放在工作目录下而非源码里？
- **关键文件**：`agents/skills_manager.py`、任意一个 Skill 目录
- **原理讲解**：插件架构、Skill 生命周期、热插拔、Markdown 即代码
- **图解**：Skill 生命周期图、插件架构全景图

---

### 卷三·工坊（第 15-19 章）

#### 第 15 章：造一把新工具（Tool）

- **问题**：我想让 Agent 能查询天气，怎么写一个新 Tool？
- **关键文件**：`agents/tools/` 下的参考实现、`agents/react_agent.py`（工具注册）
- **原理讲解**：Tool 接口规范、工具注册流程、Function Calling 端到端流程
- **动手项目**：从零写一个 `weather_tool.py`，注册到 Agent，测试调用

#### 第 16 章：造一个新技能（Skill）

- **问题**：Skill 和 Tool 有什么区别？怎么写一个新闻摘要 Skill？
- **关键文件**：`agents/skills_manager.py`、现有 Skill 目录
- **原理讲解**：Skill vs Tool 定位区别、Skill 目录结构规范、Markdown 指令文件、Cron 调度
- **动手项目**：写一个完整的 Skill，含 Markdown 指令和 Cron 配置

#### 第 17 章：接入一个新模型（Provider）

- **问题**：市场上出了新 LLM 服务，怎么让 QwenPaw 支持它？
- **关键文件**：`providers/provider.py`、`providers/openai_provider.py`
- **原理讲解**：Provider 接口契约、OpenAI 兼容协议、流式响应实现要求、配置集成
- **动手项目**：实现一个最小化 Provider

#### 第 18 章：接入一个新频道（Channel）

- **问题**：怎么让 QwenPaw 支持一个新的聊天平台？
- **关键文件**：`app/channels/base.py`、两个不同风格的 Channel 实现
- **原理讲解**：BaseChannel 接口契约、消息收发抽象、Webhook vs 长连接、Channel 注册
- **动手项目**：实现一个简单 Channel（如 IRC 或 Webhook）

#### 第 19 章：从零到 PR——完整贡献流程

- **问题**：代码写好了，怎么提交给项目？
- **关键文件**：`.github/` 目录、`CONTRIBUTING.md`
- **原理讲解**：Git 工作流、代码风格、测试要求、CI 流程、PR 审查标准
- **动手项目**：把前几章的项目整理成可提交的 PR

---

### 卷四·纵深（第 20-26 章）

#### 第 20 章：配置的秘密——从 YAML 到运行时

- **问题**：改了 `config.yaml` 的配置项，改动怎么生效的？
- **关键文件**：`config/config.py`、`config/context.py`、`config/timezone.py`
- **原理讲解**：配置加载流程、热更新 vs 冷更新、Context 模式、时区处理
- **图解**：配置加载流程图、配置项传播路径图

#### 第 21 章：记忆的宫殿——Agent 如何记住过去

- **问题**：Agent 怎么记住你昨天说过的话？
- **关键文件**：`agents/memory/base_memory_manager.py`、`agents/memory/reme_light_memory_manager.py`、`agents/memory/proactive/`
- **原理讲解**：记忆层次（短期/长期/主动）、Reme-Light 引擎、记忆存取流程、触发机制
- **图解**：记忆系统架构图、记忆存取时序图

#### 第 22 章：自治任务——Mission 模式

- **问题**：给 Agent 一个复杂任务，它怎么自己分步骤完成？
- **关键文件**：`agents/mission/` 目录
- **原理讲解**：Mission 模式 vs 普通对话、自治执行安全边界、人机协作
- **图解**：Mission 执行流程图、任务分解树状图

#### 第 23 章：多智能体协作——群策群力

- **问题**：两个 Agent 怎么合作完成任务？
- **关键文件**：`app/multi_agent_manager.py`、`agents/acp/` 目录
- **原理讲解**：多智能体架构、通信机制、任务分发与汇聚、ACP 入门
- **图解**：多智能体协作架构图、消息传递时序图

#### 第 24 章：插件系统——可扩展的骨架

- **问题**：Plugin 和 Skill 有什么区别？
- **关键文件**：`plugins/registry.py`、`plugins/loader.py`、`plugins/api.py`、`plugins/runtime.py`
- **原理讲解**：插件生命周期、API 暴露机制、插件沙箱、Plugin vs Skill 权衡
- **图解**：插件系统架构图、插件生命周期图

#### 第 25 章：命令行与部署——从开发到生产

- **问题**：`qwenpaw app` 做了什么？怎么部署到服务器？
- **关键文件**：`cli/main.py`、`cli/app_cmd.py`、`deploy/`、`docker-compose.yml`
- **原理讲解**：CLI 框架（Click 懒加载）、启动流程、部署模式、生产配置最佳实践
- **图解**：CLI 启动流程图、Docker 部署架构图

#### 第 26 章：测试与质量——如何保证代码是对的

- **问题**：411 个文件，怎么保证改了这里不会破坏那里？
- **关键文件**：`tests/` 目录、`Makefile`、`.github/workflows/`
- **原理讲解**：测试金字塔、pytest 组织、覆盖率、CI/CD 流水线、为贡献写测试
- **图解**：测试金字塔图、CI 流水线图

---

### 附录

- **A**：环境变量速查
- **B**：CLI 命令速查
- **C**：源码结构总览（`src/qwenpaw/` 每个目录的一句话说明）
- **D**：错误代码速查

## 文件组织

```
book/
├── README.md                    # 本设计文档
├── 00-序章-启程之前.md            # 序章（已有）
├── 01-浏览器按下回车之后.md
├── 02-请求到达Runner.md
├── 03-Agent的诞生.md
├── 04-系统提示词的拼装.md
├── 05-进入ReAct循环.md
├── 06-调用大语言模型.md
├── 07-工具的执行.md
├── 08-响应的归途.md
├── 09-源码的地图.md
├── 10-Agent的身世.md
├── 11-Provider的棋局.md
├── 12-Channel的变装.md
├── 13-Security的围栏.md
├── 14-Skills的工坊.md
├── 15-造一把新工具.md
├── 16-造一个新技能.md
├── 17-接入一个新模型.md
├── 18-接入一个新频道.md
├── 19-从零到PR.md
├── 20-配置的秘密.md
├── 21-记忆的宫殿.md
├── 22-自治任务.md
├── 23-多智能体协作.md
├── 24-插件系统.md
├── 25-命令行与部署.md
├── 26-测试与质量.md
├── 附录A-环境变量速查.md
├── 附录B-CLI命令速查.md
├── 附录C-源码结构总览.md
└── 附录D-错误代码速查.md
```

## 源码权威

本书所有内容以 `src/qwenpaw/` 下的实际代码为唯一事实来源。如果书中描述与源码不一致，以源码为准。
