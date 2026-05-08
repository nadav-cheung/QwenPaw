# 附录 E 常见问题解答

## 本章导览

| 项目 | 内容 |
|------|------|
| **学习目标** | 1) 快速定位常见问题 2) 掌握错误排查方法 3) 预防潜在问题 |
| **难度等级** | ⭐ |
| **核心关键词** | `FAQ` `错误码` `调试` `排查` |

> **本章概述**：本附录收集了 QwenPaw 智能体开发实战中最常见的问题及解决方案，帮助开发者快速定位和解决问题。

---

## E.1 环境搭建问题

### E.1.1 pip 安装失败

**问题描述**

执行 `pip install qwenpaw` 时安装失败，提示网络错误或依赖冲突。

**可能原因**

- 网络连接问题（国内访问 PyPI 较慢）
- Python 版本不兼容
- 权限不足
- 系统中存在冲突的依赖版本

**解决方案**

> **推荐方案**：使用国内镜像源加速安装

```bash
# 配置清华镜像源
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 重新安装
pip install qwenpaw
```

> **备选方案**：如果镜像源不可用，尝试阿里云镜像

```bash
pip install qwenpaw -i https://mirrors.aliyun.com/pypi/simple/
```

**预防措施**

- 安装前确认 Python 版本：`python --version`（推荐 3.10-3.13）
- 建议使用虚拟环境隔离项目依赖
- 优先配置国内镜像源

---

### E.1.2 初始化失败

**问题描述**

运行 `qwenpaw init` 或 `python -m qwenpaw init` 时程序无响应或报错。

**可能原因**

- 配置目录权限不足
- 配置文件格式错误
- 缺少必要的依赖包

**解决方案**

> **权限问题处理**

```bash
# Linux/macOS：检查并修复配置目录权限
chmod 755 ~/.qwenpaw

# Windows：以管理员身份运行命令行
```

> **配置文件重置**

```bash
# 备份并删除旧配置，重新初始化
mv ~/.qwenpaw/config.yaml ~/.qwenpaw/config.yaml.bak
qwenpaw init
```

**预防措施**

- 确保运行目录有写入权限
- 定期备份配置文件
- 避免手动修改配置文件格式

---

### E.1.3 依赖版本冲突

**问题描述**

启动时报错 `ImportError` 或 `ModuleNotFoundError`，提示找不到特定模块。

**可能原因**

- 多个项目使用了不同版本的同一依赖
- 系统全局包与虚拟环境包冲突

**解决方案**

> **使用虚拟环境隔离**

```bash
# 创建虚拟环境
python -m venv qwenpaw-env

# 激活虚拟环境
# Linux/macOS:
source qwenpaw-env/bin/activate
# Windows:
qwenpaw-env\Scripts\activate

# 在虚拟环境中安装
pip install qwenpaw
```

**预防措施**

- 每个项目使用独立的虚拟环境
- 使用 `requirements.txt` 锁定依赖版本
- 定期更新依赖以避免过时的安全问题

---

## E.2 配置问题

### E.2.1 配置文件格式错误

**问题描述**

修改 `config.yaml` 后程序无法启动，提示配置文件解析错误。

**可能原因**

- YAML 格式错误（缩进、空格、引号）
- 配置项名称拼写错误
- 配置值类型不正确

**解决方案**

> **验证 YAML 格式**

```bash
# 使用 Python 检查 YAML 语法
python -c "import yaml; yaml.safe_load(open('~/.qwenpaw/config.yaml'))"
```

> **恢复默认配置**

```bash
# 删除错误配置，使用默认配置
rm ~/.qwenpaw/config.yaml
qwenpaw init --force
```

**预防措施**

- 修改配置前先备份
- 使用专业的文本编辑器（VS Code、PyCharm）进行编辑
- 参考官方配置模板

---

### E.2.2 API 密钥配置无效

**问题描述**

配置了 API 密钥后仍然提示认证失败，无法调用模型服务。

**可能原因**

- API 密钥格式错误或包含多余空格
- 密钥已过期或被撤销
- 密钥权限不足
- 环境变量未正确加载

**解决方案**

> **检查密钥配置**

```bash
# 查看当前配置的密钥（脱敏显示）
qwenpaw config show | grep api_key

# 设置密钥（不带引号）
qwenpaw config set api_key sk-your-key-here

# 或通过环境变量设置
export QWENPAW_API_KEY="sk-your-key-here"
```

> **验证密钥有效性**

```bash
# 测试 API 连接
qwenpaw doctor --check-api
```

**预防措施**

- 不要在配置文件中直接粘贴带有引号的密钥值
- 优先使用环境变量方式配置敏感信息
- 定期检查密钥有效期

---

### E.2.3 渠道配置丢失

**问题描述**

配置的渠道（channel）信息丢失，程序无法连接外部服务。

**可能原因**

- 配置文件被覆盖
- 渠道配置格式不完整
- 渠道服务地址变更

**解决方案**

> **查看当前渠道配置**

```bash
qwenpaw config show channels
```

> **重新配置渠道**

```bash
# 添加渠道
qwenpaw channel add mychannel --type http --endpoint http://localhost:8080

# 查看可用渠道
qwenpaw channel list
```

**预防措施**

- 修改配置后验证保存成功
- 重要配置变更前备份
- 使用版本控制管理配置文件

---

## E.3 渠道问题

### E.3.1 渠道连接超时

**问题描述**

连接外部渠道服务时提示超时，无法建立通信。

**可能原因**

- 网络连接不稳定
- 渠道服务地址错误
- 渠道服务未启动
- 防火墙阻止连接
- 请求超时设置过短

**解决方案**

> **检查网络连通性**

```bash
# 测试渠道服务是否可达
curl -v http://localhost:8080/health
telnet localhost 8080
```

> **调整超时配置**

```yaml
# 在 config.yaml 中调整超时设置
channels:
  mychannel:
    timeout: 30  # 增加到 30 秒
    retry: 3      # 增加重试次数
```

**预防措施**

- 确保渠道服务正常运行
- 使用健康检查机制监控渠道状态
- 配置合理的超时和重试策略

---

### E.3.2 渠道认证失败

**问题描述**

连接渠道时提示认证失败，无法通过身份验证。

**可能原因**

- 认证令牌过期
- 令牌格式错误
- 渠道服务认证策略变更

**解决方案**

> **重新获取认证令牌**

```bash
# 查看渠道认证状态
qwenpaw channel status mychannel

# 重新认证
qwenpaw channel auth mychannel --refresh
```

> **检查认证配置**

```yaml
# 确保认证配置正确
channels:
  mychannel:
    auth:
      type: bearer
      token: your-valid-token
```

**预防措施**

- 定期更新认证令牌
- 配置令牌自动刷新机制
- 记录认证配置变更历史

---

## E.4 模型问题

### E.4.1 模型调用失败

**问题描述**

调用模型时返回错误，无法获取模型响应。

**可能原因**

- 模型服务不可用
- 模型名称配置错误
- 请求参数超出模型限制
- API 配额耗尽

**解决方案**

> **检查模型配置**

```bash
# 列出可用模型
qwenpaw model list

# 测试模型调用
qwenpaw model test --name qwen-turbo
```

> **调整请求参数**

```yaml
# 在 config.yaml 中配置模型参数
models:
  default:
    name: qwen-turbo
    max_tokens: 2048
    temperature: 0.7
```

> **检查 API 配额**

```bash
# 查看 API 使用情况
qwenpaw doctor --check-quota
```

**预防措施**

- 配置多个模型作为备选
- 设置合理的请求超时
- 监控 API 配额使用情况

---

### E.4.2 模型响应缓慢

**问题描述**

模型响应时间过长，影响用户体验。

**可能原因**

- 网络延迟
- 模型负载过高
- 请求内容过长
- 模型服务资源不足

**解决方案**

> **优化请求内容**

```bash
# 精简输入内容
qwenpaw model call --prompt "简洁的问题" --max-tokens 500
```

> **使用流式输出**

```python
# 启用流式响应减少等待感
response = agent.run("问题", stream=True)
for chunk in response:
    print(chunk, end="", flush=True)
```

**预防措施**

- 合理限制输入长度
- 使用流式输出改善体验
- 选择适当的模型规格

---

### E.4.3 模型输出格式错误

**问题描述**

模型输出无法解析，JSON 解析失败或格式不符合预期。

**可能原因**

- 提示词不够清晰
- 模型生成内容被截断
- 输出格式要求与模型能力不匹配

**解决方案**

> **优化提示词设计**

```yaml
# 在 config.yaml 中配置输出格式
models:
  default:
    name: qwen-max
    response_format:
      type: json_object
      schema:
        status: string
        result: string
```

> **添加输出解析保护**

```python
import json

def parse_model_output(output):
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        # 提取 JSON 部分
        import re
        match = re.search(r'\{.*\}', output, re.DOTALL)
        if match:
            return json.loads(match.group())
        raise ValueError("无法解析模型输出")
```

**预防措施**

- 使用结构化输出配置
- 添加输出验证逻辑
- 提供输出解析的容错处理

---

## E.5 技能问题

### E.5.1 技能加载失败

**问题描述**

启动时报错提示技能无法加载，技能不可用。

**可能原因**

- 技能依赖缺失
- 技能代码语法错误
- 技能配置文件格式错误

**解决方案**

> **检查技能状态**

```bash
# 列出所有技能及其状态
qwenpaw skill list --verbose

# 查看技能加载详情
qwenpaw skill debug my-skill
```

> **重新安装技能**

```bash
# 卸载后重新安装
qwenpaw skill uninstall my-skill
qwenpaw skill install my-skill
```

**预防措施**

- 安装技能前检查依赖
- 使用技能市场安装稳定版本
- 定期更新技能以获得修复

---

### E.5.2 技能调用超时

**问题描述**

调用技能时无响应或超时，无法完成技能执行。

**可能原因**

- 技能执行时间过长
- 技能陷入死循环
- 网络问题（远程技能）
- 超时配置过短

**解决方案**

> **调整技能超时配置**

```yaml
# 在 config.yaml 中配置技能超时
skills:
  my-skill:
    timeout: 60  # 增加到 60 秒
    retry: 2
```

> **中断长时间运行的技能**

```bash
# 查看正在运行的技能
qwenpaw skill status

# 中断技能执行
qwenpaw skill interrupt my-skill
```

**预防措施**

- 为复杂技能设置合理的超时时间
- 使用技能沙箱机制防止资源耗尽
- 实现技能执行进度报告

---

## E.6 插件问题

### E.6.1 插件安装失败

**问题描述**

使用 `qwenpaw plugin install` 安装插件失败。

**可能原因**

- 插件来源不受信任
- 插件与当前版本不兼容
- 网络下载失败

**解决方案**

> **安装官方插件**

```bash
# 从官方插件市场安装
qwenpaw plugin install --market official plugin-name

# 验证插件签名
qwenpaw plugin verify plugin-name
```

> **手动安装**

```bash
# 下载插件包
pip install ./plugin-name-1.0.0.whl

# 或从源码安装
cd plugin-name && pip install .
```

**预防措施**

- 仅安装来自可信来源的插件
- 检查插件与 QwenPaw 版本的兼容性
- 安装前阅读插件权限要求

---

### E.6.2 插件冲突

**问题描述**

安装多个插件后出现功能冲突或异常行为。

**可能原因**

- 插件修改了相同的系统组件
- 插件依赖了不同版本的同一库
- 插件之间的接口不兼容

**解决方案**

> **诊断插件冲突**

```bash
# 列出已安装插件
qwenpaw plugin list

# 检查插件依赖
qwenpaw plugin deps plugin-a
qwenpaw plugin deps plugin-b
```

> **禁用冲突插件**

```bash
# 临时禁用插件
qwenpaw plugin disable plugin-name

# 逐一排查：禁用所有插件后，逐个启用
qwenpaw plugin disable --all
qwenpaw plugin enable plugin-1
# 测试...
```

**预防措施**

- 安装插件前检查依赖兼容性
- 避免安装功能重复的插件
- 记录插件组合以便问题排查

---

## E.7 常见错误码

| 错误码 | 名称 | 说明 | 处理方法 |
|--------|------|------|----------|
| `E1001` | INSTALL_FAILED | pip 安装失败 | 检查网络，使用国内镜像源 |
| `E1002` | INIT_FAILED | 初始化失败 | 检查权限，重置配置 |
| `E1003` | DEPENDENCY_CONFLICT | 依赖版本冲突 | 使用虚拟环境隔离 |
| `E2001` | CONFIG_PARSE_ERROR | 配置文件解析错误 | 验证 YAML 格式，恢复默认配置 |
| `E2002` | INVALID_API_KEY | API 密钥无效 | 重新配置有效密钥 |
| `E2003` | CONFIG_NOT_FOUND | 配置文件不存在 | 执行 init 重新生成 |
| `E3001` | CHANNEL_CONNECT_TIMEOUT | 渠道连接超时 | 检查服务状态，调整超时设置 |
| `E3002` | CHANNEL_AUTH_FAILED | 渠道认证失败 | 刷新认证令牌 |
| `E3003` | CHANNEL_NOT_FOUND | 渠道不存在 | 检查渠道配置 |
| `E4001` | MODEL_UNAVAILABLE | 模型服务不可用 | 检查模型服务状态 |
| `E4002` | MODEL_QUOTA_EXCEEDED | API 配额超限 | 等待配额重置或升级套餐 |
| `E4003` | MODEL_RESPONSE_INVALID | 模型响应格式错误 | 检查提示词，优化输出解析 |
| `E5001` | SKILL_LOAD_FAILED | 技能加载失败 | 检查依赖，重新安装技能 |
| `E5002` | SKILL_EXEC_TIMEOUT | 技能执行超时 | 增加超时时间，中断技能 |
| `E5003` | SKILL_NOT_FOUND | 技能不存在 | 确认技能名称，安装技能 |
| `E6001` | PLUGIN_INSTALL_FAILED | 插件安装失败 | 检查插件来源和兼容性 |
| `E6002` | PLUGIN_CONFLICT | 插件冲突 | 禁用冲突插件，逐一排查 |
| `E6003` | PLUGIN_UNVERIFIED | 插件签名验证失败 | 仅使用官方插件或手动验证 |

---

## E.8 调试技巧

### E.8.1 启用调试模式

> **命令行启用调试**

```bash
# 启用调试输出
qwenpaw --debug run

# 查看详细日志
qwenpaw --verbose doctor
```

> **配置文件启用调试**

```yaml
# 在 config.yaml 中启用调试
debug:
  enabled: true
  level: debug
  log_file: ~/.qwenpaw/logs/debug.log
```

---

### E.8.2 查看日志文件

> **日志文件位置**

| 操作系统 | 日志路径 |
|---------|---------|
| Linux/macOS | `~/.qwenpaw/logs/` |
| Windows | `%USERPROFILE%\.qwenpaw\logs\` |

> **查看最近日志**

```bash
# 查看最后 100 行日志
tail -n 100 ~/.qwenpaw/logs/qwenpaw.log

# 实时跟踪日志
tail -f ~/.qwenpaw/logs/qwenpaw.log
```

---

### E.8.3 使用诊断命令

> **完整诊断**

```bash
# 运行完整系统诊断
qwenpaw doctor
```

> **单项检查**

```bash
# 检查环境
qwenpaw doctor --check-env

# 检查配置
qwenpaw doctor --check-config

# 检查模型连接
qwenpaw doctor --check-model

# 检查渠道连接
qwenpaw doctor --check-channel
```

---

### E.8.4 网络调试

> **测试网络连通性**

```bash
# 测试 API 端点
curl -v https://api.qwenpaw.com/health

# 测试模型服务
qwenpaw model test --name qwen-turbo --verbose
```

> **查看网络请求**

```bash
# 启用 HTTP 请求日志
qwenpaw --debug --log-requests run
```

---

### E.8.5 常见问题快速排查流程

> **环境问题排查**

```
1. 检查 Python 版本
   python --version

2. 检查 QwenPaw 安装
   pip show qwenpaw

3. 检查配置文件
   qwenpaw config show

4. 运行诊断
   qwenpaw doctor
```

> **运行时问题排查**

```
1. 启用调试模式
   qwenpaw --debug run

2. 查看错误日志
   tail -f ~/.qwenpaw/logs/qwenpaw.log

3. 检查系统资源
   top/htop  # Linux/macOS
   taskmgr   # Windows

4. 重启服务
   qwenpaw restart
```

---

## E.9 进阶支持

### E.9.1 获取更多帮助

| 渠道 | 地址 |
|------|------|
| 官方文档 | https://qwenpaw.com/docs |
| GitHub Issues | https://github.com/qwenpaw/qwenpaw/issues |
| 社区论坛 | https://github.com/qwenpaw/qwenpaw/discussions |
| 官方邮箱 | support@qwenpaw.com |

### E.9.2 提交问题反馈

> **提交 Issue 前准备**

- [ ] 确认已阅读本文档相关章节
- [ ] 启用调试模式，复现问题
- [ ] 收集日志文件
- [ ] 记录环境信息：`qwenpaw doctor --export env.json`

> **Issue 模板**

```markdown
## 问题描述
[清晰描述遇到的问题]

## 环境信息
- QwenPaw 版本：[版本号]
- Python 版本：[版本号]
- 操作系统：[系统信息]

## 复现步骤
1. [步骤1]
2. [步骤2]
3. [步骤3]

## 错误日志
```
[粘贴相关错误日志]
```

## 尝试过的解决方案
[列出已尝试的解决方法]
```

---

> **提示**：本 FAQ 会持续更新。如有未被收录的问题，欢迎提交 Issue 或 Pull Request 完善文档。
