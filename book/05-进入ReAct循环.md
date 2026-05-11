# 第 5 章：进入 ReAct 循环

```
Browser -> HTTP -> FastAPI -> Runner -> Agent -> Prompt -> [ReAct] -> LLM -> Tool -> Response
                                                           ^
                                                       you are here
```

前四章我们跟请求走过了 FastAPI、Runner、Agent 创建、提示词拼装。现在 Agent 准备好了——它知道自己是"谁"，有了工具和技能，系统提示词也拼好了。接下来是最激动人心的部分：Agent 开始"思考"。但 Agent 不是直接给你答案——它会先思考，再行动，观察结果，然后再思考。这个循环叫 ReAct。

---

## 问题

Agent 收到消息后做了什么？为什么不是直接回答，而是"思考->行动->观察->再思考"？这个循环什么时候停止？

## 术语其实很简单

> **术语：ReAct（Reasoning + Acting，推理与行动）**
> 想象你要查一个数学题的答案——你先在脑子里推理（"我需要用计算器"），然后行动（打开计算器算一下），观察结果（"答案是 42"），再推理（"这合理吗？"）。ReAct 就是让 AI 模拟这个过程——不是一次性给出答案，而是交替进行推理和行动。

> **术语：消息队列（Message Queue）**
> 想象一个对讲机频道——每个人说完一句话，其他人都能听到。消息队列就是 Agent 内部的"对讲机"——所有的思考、工具调用、工具结果都记录在里面，大模型每次"思考"时能看到完整的历史。

## 探索

### ReAct 循环的全貌

Agent 的核心循环在 agentscope 的 `ReActAgent.reply()` 方法中。简化后：

```python
def reply(self, msg):
    self.memory.add(msg)  # 记住用户的消息

    for _ in range(self.max_iters):  # 最多循环这么多次
        # 1. 思考：调用大模型
        reasoning_msg = await self._reasoning()

        # 2. 如果没有工具调用，说明想好了，直接回复
        if 没有工具调用(reasoning_msg):
            return reasoning_msg  # 退出循环

        # 3. 行动：执行工具
        tool_results = await self._acting(reasoning_msg)

        # 4. 结果自动记录到记忆中（观察步骤）
        # 然后回到第 1 步继续思考

    # 如果循环次数用完了还没回答
    return await self._summarizing()  # 强制生成一个总结
```

一次完整的 ReAct 循环：

```
用户："现在几点了？"
  |
  v
思考：LLM 生成 -> "我需要调用 get_current_time 工具"
  |
  v
行动：执行 get_current_time() -> "2026-05-11 10:30:00"
  |
  v
观察：工具结果自动记入记忆
  |
  v
思考：LLM 看到"现在10:30" -> "现在是2026年5月11日上午10:30。"
  |
  v
没有工具调用，返回文字回复 -> 循环结束
```

这就是"思考->行动->观察->再思考"。不是所有消息都需要循环——如果用户只是说"你好"，LLM 第一轮就生成文字回复，循环立刻结束。

### MRO 如何让 ToolGuardMixin 插入安全检查

上一章提到 Agent 的继承链是 `QwenPawAgent -> ToolGuardMixin -> ReActAgent`。Python 的 MRO 决定了方法调用顺序：

```
调用 self._reasoning()
  -> QwenPawAgent._reasoning()    # 第一层：媒体过滤
       -> super()._reasoning()
            -> ToolGuardMixin._reasoning()  # 第二层：审批/重放逻辑
                 -> super()._reasoning()
                      -> ReActAgent._reasoning()  # 第三层：实际调用 LLM
```

调用 `self._acting()`
  -> ToolGuardMixin._acting()     # 第一层：安全检查
       -> super()._acting()
            -> ReActAgent._acting()  # 第二层：实际执行工具

每一层都调用 `super()` 把控制权传给下一层。这种设计让安全检查"透明"地插入到推理和行动的过程中——`ReActAgent` 完全不知道有 ToolGuardMixin 在拦截它。

### ToolGuardMixin 的安全检查

`ToolGuardMixin._acting()` 是每个工具执行前的安全关卡：

```python
# 伪代码
async def _acting(self, tool_call):
    decision = self._decide_guard_action(tool_call)

    if decision == "auto_denied":
        return 拒绝消息("该操作被安全策略禁止")
    elif decision == "needs_approval":
        记录待审批请求()
        return 等待审批消息()
    else:  # preapproved 或 no_guard
        return await super()._acting(tool_call)  # 正常执行
```

三种结果：
- **auto_denied**：工具在黑名单里，直接拒绝
- **needs_approval**：工具需要用户确认，暂停等待
- **放行**：工具安全，正常执行

### 循环终止条件

ReAct 循环在以下情况停止：

1. **文字回复**：LLM 生成了纯文字（没有工具调用），循环结束
2. **等待审批**：工具被 ToolGuard 拦截需要用户确认，Agent 返回"等待审批"消息
3. **达到最大迭代次数**：`max_iters` 用完了，强制调用 `_summarizing()` 生成总结

## 实验

发送一条需要工具调用的消息，观察 ReAct 循环日志：

```bash
qwenpaw app --log-level debug
```

在浏览器发送："现在几点了？"

预期输出：终端日志中能看到类似 `reasoning`、`acting`、`get_current_time` 的调用记录，说明 Agent 先推理、再行动、再观察。

## 工程权衡

### 为什么用 ReAct 而非纯生成？

纯生成模式下，LLM 只能根据训练数据回答。"现在几点了？"这种问题它无法准确回答——它不知道当前时间。ReAct 让 LLM 能"动手"——调用 `get_current_time` 工具获取实时数据。ReAct 模式让 Agent 从"只会聊天"升级为"能干活"。

### 为什么用 MRO 拦截而非在主循环里加 if？

如果直接在 `ReActAgent` 的循环里写 `if is_dangerous(tool): return deny`，那就把安全逻辑和推理逻辑耦合在一起了。将来改安全策略要改 `ReActAgent` 的代码——但那是 agentscope 的第三方库。Mixin 模式让安全检查独立于推理循环，修改安全策略不需要碰 agentscope 的代码。

## 常见误区

> **误区：ReAct 循环是不是很慢？要调好几次 LLM？**
>
> 如果用户只是说"你好"，LLM 第一轮就生成文字回复，循环只跑一次。只有需要工具调用的消息才会触发多轮循环。而且循环次数有上限（`max_iters`），不会无限循环。大多数日常对话只需要 1-2 轮循环。

## 动手环节

**任务**：观察 ReAct 循环的完整过程。

**步骤**：
1. 用 `qwenpaw app --log-level debug` 启动
2. 在浏览器发送："帮我查看当前时间"（这会触发 `get_current_time` 工具调用）
3. 观察终端日志中的 reasoning 和 acting 调用

**预期输出**：日志中能看到至少一轮 "reasoning -> tool_use -> acting -> result -> reasoning -> text" 的循环。

**自检**：
- [ ] 看到了 LLM 的推理结果中包含工具调用（`get_current_time`）
- [ ] 理解了循环在 Agent 生成纯文字时结束
- [ ] 知道 ToolGuardMixin 在 `_acting` 步骤插入安全检查

---

Agent 的"思考"其实是对 LLM 的调用。下一章我们看看这个调用是怎么发生的——Provider 抽象层、API 调用流程、流式响应、重试机制。
