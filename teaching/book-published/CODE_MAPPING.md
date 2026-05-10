# 代码与书籍映射表

## 理念

**代码即权威**。书籍内容必须与代码一一对应。每章讲解的代码模块，必须与实际代码文件对应。

---

## QwenPaw 源码结构

```
src/qwenpaw/
├── agents/              # 智能体核心
│   ├── react_agent.py   # QwenPawAgent 核心类（ReAct 模式）
│   ├── tool_guard_mixin.py  # ToolGuard 安全混入
│   ├── model_factory.py # 模型工厂
│   ├── routing_chat_model.py  # 路由模型
│   ├── templates.py     # 智能体模板
│   ├── hooks/           # 生命周期钩子
│   │   ├── bootstrap.py
│   │   └── memory_compaction.py
│   ├── memory/          # 记忆系统
│   │   ├── agent_md_manager.py
│   │   ├── base_memory_manager.py
│   │   ├── reme_light_memory_manager.py
│   │   └── proactive/
│   ├── mission/         # Mission 模式
│   │   ├── handler.py
│   │   ├── mission_runner.py
│   │   └── state.py
│   ├── skills/          # 技能系统
│   │   ├── skills_manager.py
│   │   ├── skills_hub.py
│   │   └── (browser_cdp, chat_with_agent, cron, file_reader, etc.)
│   ├── tools/           # 内置工具
│   │   ├── file_io.py
│   │   ├── shell.py
│   │   ├── file_search.py
│   │   └── (agent_management, browser_control, delegate_external_agent, etc.)
│   ├── channels/        # 消息渠道（在 app/ 下）
│   ├── multi_agent_manager.py  # 多智能体管理
│   ├── agent_context.py
│   ├── agent_config_watcher.py
│   ├── auth.py
│   ├── approvals/
│   ├── crons/
│   └── console_push_store.py
├── app/                 # 应用系统
│   ├── server.py        # FastAPI 服务器
│   ├── runner/          # 请求处理器
│   │   ├── runner.py
│   │   ├── task_tracker.py
│   │   ├── session.py
│   │   └── models.py
│   ├── channels/        # 消息渠道
│   │   ├── manager.py
│   │   ├── registry.py
│   │   ├── renderer.py
│   │   ├── schema.py
│   │   └── (feishu, dingtalk, wecom, telegram, matrix, etc.)
│   ├── routers/         # API 路由
│   ├── hooks/           # 应用钩子
│   ├── acp/             # ACP 协议
│   ├── command_handler.py
│   ├── query_error_dump.py
│   └── md_files/
├── providers/           # LLM 提供商
│   ├── provider_manager.py  # 提供商管理
│   ├── openai_provider.py   # OpenAI
│   ├── ollama_provider.py   # Ollama
│   ├── anthropic_provider.py  # Anthropic
│   ├── gemini_provider.py   # Google Gemini
│   ├── lmstudio_provider.py  # LM Studio
│   ├── openrouter_provider.py  # OpenRouter
│   ├── retry_chat_model.py   # 重试逻辑
│   ├── rate_limiter.py       # 限流器
│   └── capability_baseline.py
├── security/            # 安全系统
│   ├── secret_store.py  # 密钥存储
│   ├── skill_scanner/   # 技能安全扫描
│   │   ├── scanner.py
│   │   └── rules.py
│   └── tool_guard/      # 工具守卫
│       ├── guard.py
│       └── rules.py
├── cli/                 # 命令行工具
│   ├── main.py          # 主入口
│   ├── app_cmd.py       # 应用命令
│   ├── agents_cmd.py    # 智能体命令
│   ├── providers_cmd.py # 提供商命令
│   ├── skills_cmd.py    # 技能命令
│   ├── channels_cmd.py  # 渠道命令
│   ├── cron_cmd.py      # 定时任务命令
│   ├── task_cmd.py      # 任务命令
│   ├── mission_cmd.py   # Mission 命令
│   ├── doctor_cmd.py    # 诊断命令
│   ├── init_cmd.py      # 初始化命令
│   └── (daemon_cmd, desktop_cmd, plugin_commands, etc.)
├── config/              # 配置系统
│   ├── config.py        # 配置管理
│   ├── context.py        # 配置上下文
│   └── timezone.py       # 时区配置
├── plugins/             # 插件系统
│   ├── api.py
│   ├── architecture.py
│   ├── loader.py
│   ├── registry.py
│   └── runtime.py
├── utils/               # 工具函数
├── constant.py          # 常量定义
├── exceptions.py        # 异常定义
└── __version__.py       # 版本信息
```

---

## 代码模块到书籍章节映射

### 第一部分：编程基础（对应 code: 无 — 纯教学）

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 01 | part1/01-编程是什么.md | - | ✅ |
| 02 | part1/02-搭建Python环境.md | - | ✅ |
| 03 | part1/03-你好世界.md | - | ✅ |
| 04 | part1/04-变量和数据.md | - | ✅ |
| 05 | part1/05-条件和分支.md | - | ✅ |
| 06 | part1/06-循环.md | - | ✅ |
| 07 | part1/07-函数.md | - | ✅ |
| 08 | part1/08-列表和字典.md | - | ✅ |
| 09 | part1/09-面向对象.md | - | ✅ |
| 10 | part1/10-异常处理.md | - | ✅ |
| 11 | part1/11-模块和包.md | - | ✅ |

### 第二部分：Python 进阶（对应 code: 无 — 纯教学）

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 11-1 | part2/11-1-装饰器.md | - | ✅ |
| 11-2 | part2/11-2-上下文管理器.md | - | ✅ |
| 11-3 | part2/11-3-迭代器和生成器.md | - | ✅ |
| 11-4 | part2/11-4-类型注解进阶.md | - | ✅ |
| 11-5 | part2/11-5-Python基础教程.md | - | ✅ |
| 11-6 | part2/11-6-Python进阶教程.md | - | ✅ |

### 第三部分：QwenPaw 入门

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 12 | part3/12-QwenPaw是什么.md | `__version__.py`, `constant.py` | ✅ |
| 13 | part3/13-安装和运行QwenPaw.md | `cli/main.py`, `cli/init_cmd.py` | ✅ |
| 14 | part3/14-使用QwenPaw.md | `app/server.py` | ✅ |
| 15 | part3/15-技能系统.md | `agents/skills/`, `agents/skills_manager.py` | ✅ |
| 16 | part3/16-项目结构.md | 全部模块 | ✅ |

### 第四部分：智能体核心（agents/）

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 17 | part4/07-智能体核心架构.md | `agents/react_agent.py` | ✅ |
| 18 | part4/18-工具与记忆系统.md | `agents/tools/`, `agents/memory/` | ✅ |
| 19 | part4/19-模板模型与钩子.md | `agents/templates.py`, `agents/model_factory.py`, `agents/hooks/` | ✅ |
| 20 | part4/09-技能扩展系统.md | `agents/skills_hub.py`, `agents/skills/` | ✅ |
| 21 | part4/21-消息渠道系统.md | `app/channels/` | ✅ |
| 22 | part4/22-MCP系统.md | `app/mcp/`, `app/routers/mcp.py` | ✅ |
| 23 | part4/23-Mission模式详解.md | `agents/mission/` | ✅ |
| 24 | part4/24-任务追踪系统.md | `app/runner/task_tracker.py` | ✅ |
| 25 | part4/25-记忆系统深入.md | `agents/memory/` | ✅ |
| 26 | part4/26-插件系统.md | `plugins/` | ✅ |
| - | part4/27-应用启动与插件系统.md | `app/_app.py`, `plugins/` | ⚠️ 额外章节 |

### 第五部分：应用与基础设施

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 27 | part5/27-多智能体协作.md | `agents/multi_agent_manager.py`, `app/acp/` | ✅ |
| 28 | part5/23-Model系统与LLM提供商.md | `providers/` | ✅ |
| 29 | part5/24-安全系统详解.md | `security/` | ✅ |
| 30 | part5/25-配置系统详解.md | `config/` | ✅ |
| 31 | part5/26-请求处理与Runner.md | `app/runner/` | ✅ |
| 32 | part5/28-部署与运维.md | `cli/`, `app/server.py` | ✅ |
| 33 | part5/34-工具Guard安全系统.md | `security/tool_guard/` | ✅ |
| 34 | part5/35-智能体钩子系统.md | `agents/hooks/` | ✅ |
| 35 | part5/36-心跳系统.md | `agents/crons/`, `cli/cron_cmd.py` | ✅ |
| - | part5/37-密钥存储加密系统.md | `security/secret_store.py` | ⚠️ 额外章节 |
| - | part5/38-本地模型管理系统.md | `local_models/` | ⚠️ 额外章节 |
| - | part5/39-日志系统详解.md | `utils/` | ⚠️ 额外章节 |
| - | part5/40-文件操作与安全机制.md | `agents/tools/file_io.py` | ⚠️ 额外章节 |
| - | part5/41-ACP智能体通信协议.md | `app/acp/` | ⚠️ 额外章节 |
| - | part5/42-Shell命令执行系统.md | `agents/tools/shell.py` | ⚠️ 额外章节 |
| - | part5/43-工具模块详解.md | `agents/tools/` | ⚠️ 额外章节 |
| - | part5/44-消息系统详解.md | `app/channels/` | ⚠️ 额外章节 |
| - | part5/45-API路由系统详解.md | `app/routers/` | ⚠️ 额外章节 |
| - | part5/46-CLI命令系统详解.md | `cli/` | ⚠️ 额外章节 |
| - | part5/47-会话与状态管理.md | `app/runner/session.py` | ⚠️ 额外章节 |
| - | part5/48-错误处理与日志记录.md | `exceptions.py` | ⚠️ 额外章节 |
| - | part5/49-Console渠道详解.md | `app/channels/console/` | ⚠️ 额外章节 |
| - | part5/50-文件预览与类型识别.md | `agents/tools/view_media.py` | ⚠️ 额外章节 |
| - | part5/51-跨渠道消息路由.md | `app/channels/` | ⚠️ 额外章节 |
| - | part5/52-Provider系统深度解析.md | `providers/` | ⚠️ 额外章节 |
| - | part5/53-Agent统计系统.md | `agent_stats/` | ⚠️ 额外章节 |
| - | part5/54-模型探测与能力检测.md | `providers/capability_baseline.py` | ⚠️ 额外章节 |
| - | part5/55-健康检查与监控.md | `app/routers/agent_stats.py` | ⚠️ 额外章节 |
| - | part5/56-异常处理与恢复.md | `exceptions.py` | ⚠️ 额外章节 |
| - | part5/57-ToolGuard国际化详解.md | `security/tool_guard/` | ⚠️ 额外章节 |
| - | part5/58-CORS与中间件.md | `app/server.py` | ⚠️ 额外章节 |
| - | part5/59-系统集成与第三方服务.md | `app/` | ⚠️ 额外章节 |
| - | part5/60-故障排查与诊断.md | `cli/doctor_cmd.py` | ⚠️ 额外章节 |
| - | part5/61-部署与运维指南.md | `cli/`, `app/server.py` | ⚠️ 额外章节 |
| - | part5/62-CLI配置与安全.md | `cli/`, `config/` | ⚠️ 额外章节 |
| - | part5/63-审批系统详解.md | `agents/approvals/` | ⚠️ 额外章节 |
| - | part5/64-备份恢复系统详解.md | `app/backup/` | ⚠️ 额外章节 |
| - | part5/65-环境变量系统.md | `envs/`, `config/` | ⚠️ 额外章节 |
| - | part5/66-认证授权系统详解.md | `agents/auth.py` | ⚠️ 额外章节 |
| - | part5/67-搜索工具系统.md | `agents/tools/file_search.py` | ⚠️ 额外章节 |

### 第六部分：架构与最佳实践

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 36 | part6/29-架构设计思维.md | `plugins/architecture.py` | ✅ |
| 37 | part6/30-生命周期管理.md | `agents/hooks/bootstrap.py`, `app/server.py` | ✅ |
| 38 | part6/31-性能优化.md | `providers/rate_limiter.py`, `token_usage/` | ✅ |
| 39 | part6/32-安全加固.md | `security/` | ✅ |
| 40 | part6/33-定时任务与心跳.md | `agents/crons/`, `agents/mission/` | ✅ |
| 41 | part6/34-Workspace隔离机制.md | `app/workspace/` | ✅ |
| - | part6/35-配置热重载机制.md | `config/` | ⚠️ 额外章节 |
| - | part6/36-聊天管理系统.md | `app/routers/agents.py` | ⚠️ 额外章节 |

### 第七部分：运维与贡献

| 章节 | 文件 | 代码模块 | 状态 |
|------|------|----------|------|
| 42 | part7/34-开发环境准备.md | `cli/` | ✅ |
| 43 | part7/35-贡献代码.md | `cli/doctor_cmd.py`, `cli/main.py` | ✅ |
| 44 | part7/36-综合实战.md | 全部模块 | ✅ |

### 附录

| 章节 | 文件 | 内容 | 状态 |
|------|------|------|------|
| A | appendix/A-环境变量速查.md | `config/`, `envs/` | ✅ |
| B | appendix/B-CLI命令参考.md | `cli/` | ✅ |
| C | appendix/C-源码结构速查.md | 全部模块 | ✅ |
| D | appendix/D-Python速查表.md | - | ✅ |
| E | appendix/E-错误代码速查.md | `exceptions.py` | ✅ |

---

## 待补充的章节

无。所有章节均已补充。

---

## 额外章节说明

⚠️ 标记为"额外章节"的文件是超出了官方 41 章节结构的补充内容。这些章节覆盖了更细粒度的主题，建议：

1. 将额外章节整合到主章节中作为子章节
2. 或将其移到"补充章节"目录下
3. 或在后续版本中纳入正式结构

---

## 书籍结构与代码结构对比

### 当前书籍结构（7 部分）
```
part1: 编程入门（11 章）
part2: Python 进阶（6 章）
part3: QwenPaw 入门（5 章）
part4: QwenPaw 开发（11 章）
part5: 系统深入（40+ 章）
part6: 架构与最佳实践（8 章）
part7: 实战与贡献（3 章）
```

### 建议：按代码结构重组（6 部分）
```
part1: 编程基础（11 章）  # 保持不变
part2: Python 进阶（6 章） # 保持不变
part3: QwenPaw 入门（5 章） # 保持不变
part4: 智能体核心（10 章）   # agents/ 相关
part5: 应用与基础设施（10 章） # app/, providers/, security/
part6: 运维与贡献（6 章）     # cli/, config/, plugins/
```

---

*映射表生成时间：2026-05-09*
*状态：代码即权威，书籍必须与代码一一对应*
