# 13 安装和运行 QwenPaw

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 在电脑上成功安装 QwenPaw 2) 完成首次初始化配置 3) 启动 QwenPaw 并访问 Web 界面 4) 了解 QwenPaw 的基本使用流程 |
| **前置知识** | [12-QwenPaw是什么](./12-QwenPaw是什么.md) |
| **预计时长** | 40 分钟（安装 15 分钟 + 配置 25 分钟） |
| **难度等级** | ⭐ |
| **核心关键词** | `pip install` `qwenpaw init` `qwenpaw app` `配置` `模型` |

> **一句话概述**：本章手把手教你安装 QwenPaw，并完成首次配置和运行。

---

## 1. 环境要求

### 1.1 系统要求

| 项目 | 要求 |
|------|------|
| **操作系统** | Windows 10+, macOS 10.14+, Ubuntu 18.04+ |
| **内存** | 推荐 8GB+ |
| **磁盘** | 至少 2GB 可用空间 |
| **Python** | 3.10 - 3.13 |

### 1.2 检查 Python 版本

打开终端（Windows 用 cmd 或 PowerShell），输入：

```bash
python --version
```

或

```bash
python3 --version
```

应该显示 `Python 3.10.x` 或更高版本。

**如果显示找不到 Python**，请先安装 Python：
- 访问 https://www.python.org/downloads/
- 下载并安装最新版的 Python 3

---

## 2. 安装 QwenPaw

### 2.1 方式一：pip 安装（推荐）

这是最简单的方式，只需要一行命令：

```bash
pip install qwenpaw
```

### 2.2 方式二：脚本安装（无需手动安装 Python）

如果你还没有安装 Python，可以用官方安装脚本：

**macOS / Linux：**
```bash
curl -fsSL https://qwenpaw.agentscope.io/install.sh | bash
```

**Windows (PowerShell)：**
```powershell
irm https://qwenpaw.agentscope.io/install.ps1 | iex
```

### 2.3 验证安装

安装完成后，输入：

```bash
qwenpaw --version
```

应该显示版本号，如 `qwenpaw 1.1.2`。

---

## 3. 首次配置

### 3.1 运行初始化

```bash
qwenpaw init --defaults
```

`--defaults` 参数会使用默认配置，适合初学者快速体验。

**如果不带参数运行：**
```bash
qwenpaw init
```

会进入交互式配置模式，依次询问：
- 工作目录位置
- 是否使用默认配置
- LLM 提供商选择
- API 密钥配置

### 3.2 配置 LLM 模型

QwenPaw 需要一个大语言模型来驱动。有两种选择：

#### 方式一：使用云端模型（需要 API 密钥）

| 提供商 | 说明 | 获取密钥 |
|--------|------|----------|
| **Qwen（阿里云）** | 推荐国内用户，便宜稳定 | https://dashscope.console.aliyun.com/ |
| **OpenAI** | 国际用户，GPT-4 | https://platform.openai.com/ |
| **Gemini** | Google 的模型 | https://aistudio.google.com/ |

#### 方式二：使用本地模型（免费，无需密钥）

如果你有显卡，可以使用 Ollama 运行本地模型：
- 安装 Ollama：https://ollama.com/
- 下载模型：`ollama pull qwen2.5`
- 配置本地地址

### 3.3 通过 Web 界面配置

初始化完成后，启动应用：

```bash
qwenpaw app
```

然后打开浏览器访问 **http://127.0.0.1:8088/**

在界面中：
1. 点击右上角「设置」（齿轮图标）
2. 选择「模型」选项卡
3. 选择提供商（如 Qwen/OpenAI）
4. 输入 API 密钥
5. 保存并启用

---

## 4. 启动和使用

### 4.1 启动应用

```bash
qwenpaw app
```

你会看到类似输出：

```
🚀 QwenPaw 正在启动...

✅ 服务已就绪
🌐 请访问 http://127.0.0.1:8088/
```

### 4.2 打开 Web 界面

在浏览器中打开 **http://127.0.0.1:8088/**

你应该能看到 QwenPaw 的 Web 界面。

### 4.3 基本使用流程

#### 4.3.1 创建新对话

1. 点击左侧「新建对话」按钮
2. 输入你的问题或指令
3. 按回车发送
4. 等待 AI 回复

#### 4.3.2 对话示例

```
你：你好，你能做什么？
QwenPaw：你好！我是 QwenPaw，你的个人 AI 助手。我可以：
- 回答问题和对话
- 帮你查找资料
- 协助写作和编程
- 还有很多技能...
```

#### 4.3.3 使用技能

1. 输入 `/skills` 查看可用技能
2. 输入 `/skill <技能名>` 使用特定技能
3. 例如：`/skill websearch` 进行网页搜索

---

## 5. 常用命令

### 5.1 命令行命令

| 命令 | 说明 |
|------|------|
| `qwenpaw app` | 启动 Web 应用 |
| `qwenpaw init` | 初始化配置 |
| `qwenpaw doctor` | 诊断检查 |
| `qwenpaw agents` | 管理智能体 |
| `qwenpaw skills` | 查看技能列表 |
| `qwenpaw --help` | 显示帮助 |

### 5.2 诊断问题

遇到问题时，运行诊断命令：

```bash
qwenpaw doctor
```

这会检查：
- Python 版本
- 依赖是否完整
- 配置文件是否正确
- 网络连接状态

---

## 6. 常见问题

### 6.1 pip 安装失败

**错误**：`pip: command not found`

**解决**：
```bash
# 尝试用 python -m pip
python -m pip install qwenpaw

# 或先升级 pip
python -m pip install --upgrade pip
```

### 6.2 端口被占用

**错误**：`Port 8088 is already in use`

**解决**：
```bash
# 查看占用端口的进程
# Windows:
netstat -ano | findstr :8088

# macOS/Linux:
lsof -i :8088

# 结束进程或使用其他端口
qwenpaw app --port 8089
```

### 6.3 API 密钥无效

**问题**：AI 回复"API 密钥无效"或"认证失败"

**解决**：
1. 检查密钥是否正确复制（不要有多余空格）
2. 确认密钥有足够的额度
3. 尝试重新输入密钥

### 6.4 首次启动很慢

首次启动需要：
- 下载模型（如果用本地模型）
- 初始化数据库
- 编译前端资源

可能需要等待 1-5 分钟，后续启动会快很多。

---

## 7. 配置文件

### 7.1 配置文件位置

QwenPaw 的配置文件通常在：
- **Linux/macOS**: `~/.qwenpaw/`
- **Windows**: `C:\Users\你的用户名\.qwenpaw\`

### 7.2 目录结构

```
~/.qwenpaw/
├── config.yaml          # 主配置文件
├── working/            # 工作目录
│   ├── agents/         # 智能体配置
│   ├── memory/         # 记忆存储
│   └── skills/         # 技能目录
├── working.secret/     # 密钥存储
└── backups/            # 备份
```

### 7.3 手动编辑配置

如果需要高级配置，可以手动编辑 `config.yaml`：

```yaml
app:
  host: "0.0.0.0"
  port: 8088
  title: "我的 QwenPaw"

models:
  default_provider: "qwen"
  providers:
    qwen:
      api_key: "your-api-key"
      model: "qwen-plus"
```

---

## 8. 小结

### 安装步骤

| 步骤 | 命令 |
|------|------|
| 1. 安装 | `pip install qwenpaw` |
| 2. 初始化 | `qwenpaw init --defaults` |
| 3. 配置模型 | 在 Web 界面输入 API 密钥 |
| 4. 启动 | `qwenpaw app` |
| 5. 访问 | 浏览器打开 http://127.0.0.1:8088/ |

### 常见命令

| 命令 | 说明 |
|------|------|
| `qwenpaw app` | 启动 |
| `qwenpaw init` | 初始化 |
| `qwenpaw doctor` | 诊断 |

---

## 延伸阅读

| 资源 | 说明 |
|------|------|
| [QwenPaw 官方文档](https://qwenpaw.agentscope.io/) | 完整文档 |
| [QwenPaw GitHub](https://github.com/agentscope-ai/QwenPaw) | 项目主页 |

---

## 下一章预告

下一章我们将学习 QwenPaw 的基本使用，包括配置、技能、多渠道等。
