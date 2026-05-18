# 附录 E：术语索引

按拼音排序。标注首次出现的章节号，方便回溯查阅。

---

| 术语 | 英文 | 首次出现 | 一句话解释 |
|---|---|---|---|
| Agent（智能体） | Agent | 第 3 章 | 能感知环境、做出决策、执行行动的自主实体——在 QwenPaw 里就是一个会聊天、会用工具的 AI 助手 |
| AgentConfig（Agent 配置） | AgentConfig | 第 10 章 | 描述一个 Agent 的完整配置对象——模型、工具、技能、安全策略都在里面 |
| Guardian（守卫） | Guardian | 第 7 章 | 工具执行前的安全检查员——决定放行、拦截还是需要用户确认 |
| HTTP（超文本传输协议） | HyperText Transfer Protocol | 第 1 章 | 浏览器和服务器之间的"对话规则"——浏览器按规则提问，服务器按规则回答 |
| FastAPI（Web 框架） | FastAPI | 第 1 章 | 像餐厅前台——客人（HTTP 请求）来了，前台根据菜单（路由）把客人领到对应的服务员（处理函数）面前 |
| Message Queue（消息队列） | Message Queue | 第 5 章 | 生产者往队列里放消息，消费者从队列里取消息——解耦发送方和接收方 |
| Middleware（中间件） | Middleware | 第 1 章 | 请求到达处理函数之前经过的"安检站"——每个安检站可以检查或修改请求 |
| Mixin（混入） | Mixin | 第 3 章 | 像给一道菜加调料——不改变主菜的做法，但增加额外的功能片段 |
| MRO（方法解析顺序） | Method Resolution Order | 第 10 章 | Python 多继承时决定"先找谁的方法"的顺序——像家谱里决定先问爸爸还是先问妈妈 |
| ProcessHandler（处理器） | ProcessHandler | 第 12 章 | Channel 和底层通信之间的桥梁——把平台特有的消息格式翻译成 QwenPaw 的统一格式 |
| Provider（模型供应商） | Provider | 序章 | LLM 服务的供应商——像手机运营商，你换一家不影响手机本身的功能 |
| ReAct（推理与行动） | Reasoning + Acting | 第 5 章 | Agent 的工作方式——先想（Reasoning）再做（Acting），交替进行直到完成任务 |
| Runner（运行器） | Runner | 第 2 章 | 请求的调度员——收到请求后找到对应的 Agent 来处理 |
| Session（会话） | Session | 第 2 章 | 一次连续对话的上下文——像打乒乓球时的那一局，球没落地就一直记着比分 |
| Skill（技能） | Skill | 第 14 章 | 用 Markdown 写的知识文档——注入到系统提示词让 Agent "学会"新能力 |
| Skill Pool（技能池） | Skill Pool | 第 14 章 | 多个 Agent 共享的技能仓库——放进去的技能大家都能用 |
| SSE（服务器推送事件） | Server-Sent Events | 第 1 章 | 服务器主动往浏览器"推送"消息的机制——像快递员不间断地往你门口放包裹 |
| Strategy Pattern（策略模式） | Strategy Pattern | 第 11 章 | 定义一族算法，运行时选择用哪个——像出行时选打车、地铁还是骑车 |
| System Prompt（系统提示词） | System Prompt | 第 4 章 | 给 AI 的"工作手册"——告诉它你是谁、应该怎么回答、有什么规则 |
| Tool Call（工具调用） | Tool Call | 第 7 章 | AI 要求执行某个外部操作（如读文件、搜索网页）的请求 |
| ToolResponse（工具响应） | ToolResponse | 第 7 章 | 工具执行后返回的结果——包含文本、图片或错误信息 |
| Wrapper Chain（装饰器链） | Wrapper Chain | 第 6 章 | 一层套一层的函数包装——每层加一个功能（重试、记录、限流），像俄罗斯套娃 |
| YAML Rules（YAML 规则） | YAML Rules | 第 13 章 | 用 YAML 格式写的安全规则——描述"什么工具在什么条件下需要什么权限" |
| 命令分发 | Command Dispatch | 第 2 章 | 把 `/skill`、`/reset` 等命令路由到对应的处理函数 |
| 工作目录 | Working Directory | 序章 | QwenPaw 的根目录 `~/.qwenpaw/`——就像一栋房子，所有 Agent 的配置、记忆、技能都住在里面 |
| 工作区 | Workspace | 第 4 章 | 单 Agent 的运行时环境（`~/.qwenpaw/workspaces/<id>/`）——就像房子里一个 Agent 的专属房间，包含该 Agent 的身份文件、技能、配置 |
| 工厂模式 | Factory Pattern | 第 3 章 | 不直接 `new` 对象，而是通过工厂函数创建——方便统一管理创建过程 |
| 多态反序列化 | Polymorphic Deserialization | 第 11 章 | JSON 数据反序列化时，根据类型字段选择对应的类来构造——同一份数据变成不同的对象 |
| 限流器 | Rate Limiter | 第 6 章 | 控制请求频率的阀门——防止调用太频繁被 API 服务器拒绝 |
| 适配器模式 | Adapter Pattern | 第 12 章 | 把一个接口转换成另一个接口——像旅行时的电源转换插头 |
| 生产者-消费者模型 | Producer-Consumer Pattern | 第 8 章 | 一个线程生产数据放进队列，另一个线程从队列取数据消费——解耦生产和消费 |
| 类与实例 | Class and Instance | 第 3 章 | 类是蓝图，实例是按蓝图造出来的具体物件——一个类可以造出很多实例 |
| 模板拼装 | Template Assembly | 第 4 章 | 把多个模板片段按规则组合成完整内容——像拼图一样把碎片拼成完整图案 |
| 流适配器 | Stream Adapter | 第 8 章 | 把一种流式数据格式转换成另一种——像不同语言之间的同声传译 |
| 依赖图 | Dependency Graph | 第 9 章 | 模块之间"谁依赖谁"的关系图——像组织架构图，但画的是代码关系 |
| 入口点 | Entry Point | 第 9 章 | 程序开始执行的地方——像大楼的正门，所有访问都从这里开始 |

---

## 英文索引（Alphabetical Index）

按英文首字母排序，方便英文关键词反向查找。

| 英文 | 中文 | 章节 |
|------|------|------|
| Adapter Pattern | 适配器模式 | 第 12 章 |
| Agent | 智能体 | 第 3 章 |
| AgentConfig | Agent 配置 | 第 10 章 |
| Class and Instance | 类与实例 | 第 3 章 |
| Command Dispatch | 命令分发 | 第 2 章 |
| Dependency Graph | 依赖图 | 第 9 章 |
| Entry Point | 入口点 | 第 9 章 |
| Factory Pattern | 工厂模式 | 第 3 章 |
| FastAPI | Web 框架 | 第 1 章 |
| Guardian | 守卫 | 第 7 章 |
| HTTP | 超文本传输协议 | 第 1 章 |
| Message Queue | 消息队列 | 第 5 章 |
| Middleware | 中间件 | 第 1 章 |
| Mixin | 混入 | 第 3 章 |
| MRO | 方法解析顺序 | 第 10 章 |
| Polymorphic Deserialization | 多态反序列化 | 第 11 章 |
| ProcessHandler | 处理器 | 第 12 章 |
| Producer-Consumer Pattern | 生产者-消费者模型 | 第 8 章 |
| Provider | 模型供应商 | 序章 |
| Rate Limiter | 限流器 | 第 6 章 |
| ReAct | 推理与行动 | 第 5 章 |
| Runner | 运行器 | 第 2 章 |
| SSE | 服务器推送事件 | 第 1 章 |
| Session | 会话 | 第 2 章 |
| Skill | 技能 | 第 14 章 |
| Skill Pool | 技能池 | 第 14 章 |
| Strategy Pattern | 策略模式 | 第 11 章 |
| Stream Adapter | 流适配器 | 第 8 章 |
| System Prompt | 系统提示词 | 第 4 章 |
| Template Assembly | 模板拼装 | 第 4 章 |
| Tool Call | 工具调用 | 第 7 章 |
| ToolResponse | 工具响应 | 第 7 章 |
| Working Directory | 工作目录 | 序章 |
| Workspace | 工作区 | 第 4 章 |
| Wrapper Chain | 装饰器链 | 第 6 章 |
| YAML Rules | YAML 规则 | 第 13 章 |
