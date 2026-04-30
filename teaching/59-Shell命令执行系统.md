# Shell 命令执行系统

## 概述

`execute_shell_command` 是 QwenPaw 的核心 shell 执行工具，处理跨平台（Windows/macOS/Linux）命令执行、超时控制、进程树终止和 LLM 输出的特殊转义。

本章节详细解析 shell 执行的核心函数、平台差异处理、命令预处理、进程管理、响应格式化，以及完整的执行流程。

---

## 1. 核心函数

源码路径：`src/qwenpaw/agents/tools/shell.py:285`

```python
# src/qwenpaw/agents/tools/shell.py:285
async def execute_shell_command(
    command: str,
    timeout: float = 60.0,
    cwd: Optional[Path] = None,
) -> ToolResponse:
    """执行 shell 命令

    参数：
    - command: 要执行的命令
    - timeout: 超时时间（秒）
    - cwd: 工作目录（默认使用 workspace）

    返回：
    - ToolResponse: 包含 returncode, stdout, stderr
    """
```

### 1.1 平台差异

| 平台 | 实现方式 | 原因 |
|------|----------|------|
| Windows | `cmd /D /S /C` + 线程池 | asyncio subprocess 在 Windows 有 bug |
| Unix | `asyncio.create_subprocess_shell` + `start_new_session` | 原生支持进程组 |

### 1.2 使用示例

```python
# 基本使用
result = await execute_shell_command("ls -la")

# 带超时
result = await execute_shell_command("sleep 30", timeout=10)

# 指定工作目录
result = await execute_shell_command("git status", cwd="/project")

# 处理错误
if result.returncode != 0:
    print(f"命令失败: {result.stderr}")
```

---

## 2. 命令预处理

### 2.1 展开嵌入换行符

源码路径：`src/qwenpaw/agents/tools/shell.py:109`

```python
# src/qwenpaw/agents/tools/shell.py:109
def _collapse_embedded_newlines(cmd: str) -> str:
    """JSON 解码后 \\n 会变成真实换行符，需根据平台处理

    问题：LLM 输出的命令中可能包含真实的换行符，
    这会导致 shell 执行出错。
    """
    if sys.platform == "win32":
        # cmd.exe 遇到换行直接截断，所有换行必须折叠
        return cmd.replace("\r\n", " ").replace("\n", " ")
    return _collapse_newlines_outside_quotes(cmd)  # Unix 保留引号内换行
```

**预处理示例：**

| 原始命令 | Windows 处理后 | Unix 处理后 |
|----------|---------------|-------------|
| `ls\n-la` | `ls -la` | `ls\n-la`（引号外折叠） |
| `echo "line1\nline2"` | `echo line1 line2` | `echo "line1\nline2"`（引号内保留） |

### 2.2 引号内换行保留（Unix）

```python
# src/qwenpaw/agents/tools/shell.py:40
def _collapse_newlines_outside_quotes(cmd: str) -> str:
    """引号外换行折叠为空格，引号内换行保留

    规则：
    - 单引号 ''：完全字面，换行保留
    - 双引号 ""：允许转义符，换行保留
    - 无引号：换行折叠
    """
```

**处理逻辑：**

```
输入: echo "line1\nline2"
处理: 识别在双引号内，保留 \n
输出: echo "line1\nline2"

输入: echo line1\nline2
处理: 不在引号内，折叠 \n
输出: echo line1 line2
```

### 2.3 Windows 转义修复

```python
# src/qwenpaw/agents/tools/shell.py:138
def _sanitize_win_cmd(cmd: str) -> str:
    """修复 LLM 常见的 \\" 双转义问题

    LLM 经常错误地转义引号，产生 \\" 而不是 \"
    """
    if '\\"' in cmd and '"' not in cmd.replace('\\"', ""):
        # 检测是否有孤立的 \\"
        return cmd.replace('\\"', '"')
    return cmd
```

---

## 3. Windows 执行实现

源码路径：`src/qwenpaw/agents/tools/shell.py:161`

### 3.1 线程池执行

```python
# src/qwenpaw/agents/tools/shell.py:337
if sys.platform == "win32":
    returncode, stdout_str, stderr_str = await asyncio.to_thread(
        _execute_subprocess_sync,
        cmd,
        str(working_dir),
        timeout,
        env,
    )
```

**为什么用线程池？**

```
asyncio.create_subprocess_shell 在 Windows 上的问题：
- 管道创建失败
- 进程有时无法终止
- 字符编码问题

解决方案：使用同步 subprocess + 线程池
```

### 3.2 临时文件重定向

```python
# src/qwenpaw/agents/tools/shell.py:212
stdout_fd, stdout_path = tempfile.mkstemp(prefix="qwenpaw_out_")
stderr_fd, stderr_path = tempfile.mkstemp(prefix="qwenpaw_err_")

# stdout/stderr 重定向到临时文件而非管道
# 避免 Chrome 等进程继承管道句柄导致 communicate() 阻塞
```

**阻塞原因：**

```
问题：Chrome 等进程可能继承 subprocess 的 stdout 管道
如果 Chrome 不关闭管道，communicate() 会一直等待

解决方案：
1. 重定向到临时文件
2. 读取临时文件获取输出
3. 避免管道继承问题
```

### 3.3 进程树终止

```python
# src/qwenpaw/agents/tools/shell.py:23
def _kill_process_tree_win32(pid: int) -> None:
    """使用 taskkill /F /T 杀完整进程树

    /F: 强制终止
    /T: 终止进程树（所有子进程）
    /PID: 指定进程 ID
    """
    subprocess.call(
        ["taskkill", "/F", "/T", "/PID", str(pid)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
```

---

## 4. Unix 执行实现

源码路径：`src/qwenpaw/agents/tools/shell.py:347`

### 4.1 subprocess 创建

```python
# src/qwenpaw/agents/tools/shell.py:347
proc = await asyncio.create_subprocess_shell(
    cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    cwd=str(working_dir),
    env=env,
    start_new_session=True,  # 创建新进程组
)
stdout, stderr = await asyncio.wait_for(
    proc.communicate(),
    timeout=timeout,
)
```

**`start_new_session=True` 的作用：**

```
父进程
    ↓ fork
子进程（继承父进程组）
    ↓ setsid() 创建新会话和新进程组
新会话 + 新进程组
    ↓
可以单独杀整个进程组，不影响父进程
```

### 4.2 超时处理

```python
# src/qwenpaw/agents/tools/shell.py:368
except asyncio.TimeoutError:
    # 1. 杀进程组（含所有子进程）
    pgid = os.getpgid(proc.pid)
    os.killpg(pgid, signal.SIGTERM)

    # 2. 2秒 grace period 后 SIGKILL
    try:
        await asyncio.sleep(2)
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass  # 进程已退出

    # 3. 排出剩余输出
    stdout, stderr = await proc.communicate()
```

**优雅终止流程：**

```
超时
    ↓
SIGTERM (请求终止，进程可捕获)
    ↓ (等待 2 秒)
SIGKILL (强制杀死，进程不可捕获)
    ↓
读取剩余输出
```

---

## 5. 工作目录与环境变量

```python
# src/qwenpaw/agents/tools/shell.py:325
# 优先使用传入的 cwd
if cwd is not None:
    working_dir = cwd
else:
    working_dir = get_current_workspace_dir() or WORKING_DIR

# 确保 venv Python 在 PATH
env = os.environ.copy()
python_bin_dir = str(Path(sys.executable).parent)
env["PATH"] = python_bin_dir + os.pathsep + env.get("PATH", "")
```

**PATH 优先级：**

```
确保 QwenPaw 使用的 Python 在 PATH 最前面
env["PATH"] = "/path/to/qwenpaw/venv/bin:/usr/bin:/bin"

这样 `python` 会使用 venv 中的 Python
而不是系统的 Python
```

---

## 6. 响应格式化

```python
# src/qwenpaw/agents/tools/shell.py:412
if returncode == 0:
    # 成功：输出 + stderr 警告
    response_text = stdout_str or "Command executed successfully (no output)."
    if stderr_str:
        response_text += f"\n[stderr]\n{stderr_str}"
else:
    # 失败：详细错误信息
    response_parts = [f"Command failed with exit code {returncode}."]
    if stdout_str:
        response_parts.append(f"\n[stdout]\n{stdout_str}")
    if stderr_str:
        response_parts.append(f"\n[stderr]\n{stderr_str}")
    response_text = "".join(response_parts)
```

**响应格式：**

```
成功时：
<stdout 内容>
[stderr]
<stderr 内容（如果有）>

失败时：
Command failed with exit code <code>.
[stdout]
<stdout 内容>
[stderr]
<stderr 内容>
```

---

## 7. 智能解码

```python
# src/qwenpaw/agents/tools/shell.py:447
def smart_decode(data: bytes) -> str:
    """智能解码字节为字符串

    策略：
    1. 先尝试 UTF-8
    2. 失败则使用系统首选编码
    3. 使用 errors='replace' 避免解码失败
    """
    try:
        decoded_str = data.decode("utf-8")
    except UnicodeDecodeError:
        encoding = locale.getpreferredencoding(False) or "utf-8"
        decoded_str = data.decode(encoding, errors="replace")
    return decoded_str.strip("\n")
```

---

## 8. 执行流程图

```
┌─────────────────────────────────────────────────────────────┐
│ execute_shell_command(command, timeout, cwd)                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ _collapse_embedded_newlines() — 预处理换行符                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │         sys.platform == "win32"       │
         └──────────────────────────────────────┘
               │                        │
               ▼                        ▼
┌───────────────────────┐   ┌───────────────────────────────┐
│ _execute_subprocess_   │   │ asyncio.create_subprocess_   │
│ sync() 线程池执行      │   │ shell() + communicate()     │
└───────────────────────┘   └───────────────────────────────┘
               │                        │
               └────────────┬───────────┘
                            ▼
         ┌──────────────────────────────────────┐
         │         超时检查                        │
         │  超时 → 杀进程树 (SIGTERM → SIGKILL)  │
         └──────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ smart_decode() + 格式化 → ToolResponse                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. 设计模式

### 9.1 平台适配

```python
# 平台特定实现
if sys.platform == "win32":
    # Windows: 线程池 + subprocess.call
    result = await asyncio.to_thread(_execute_sync, cmd)
else:
    # Unix: asyncio.create_subprocess_shell
    proc = await asyncio.create_subprocess_shell(cmd)
    result = await proc.communicate()
```

### 9.2 进程组管理

```python
# Unix: 创建新会话和进程组
proc = await asyncio.create_subprocess_shell(
    cmd,
    start_new_session=True,  # 关键：创建新进程组
)

# 超时时杀整个进程组
os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
```

### 9.3 资源清理

```python
# 确保资源释放
try:
    stdout, stderr = await asyncio.wait_for(
        proc.communicate(),
        timeout=timeout,
    )
finally:
    # 清理临时文件
    for path in [stdout_path, stderr_path]:
        if os.path.exists(path):
            os.unlink(path)
```

---

## 10. 应用场景

### 10.1 代码构建

**场景：** 执行构建命令并获取输出。

```python
result = await execute_shell_command(
    "npm run build",
    timeout=300,  # 5分钟构建
    cwd="/project"
)

if result.returncode == 0:
    print("构建成功")
else:
    print(f"构建失败: {result.stderr}")
```

### 10.2 Git 操作

**场景：** 在 workspace 中执行 Git 命令。

```python
# 检查 Git 状态
status = await execute_shell_command("git status")
print(status.response_text)

# 执行 Git 操作
result = await execute_shell_command(
    "git commit -m 'Update'",
    cwd=workspace_dir
)
```

### 10.3 自动化脚本

**场景：** 执行复杂的多步骤脚本。

```python
script = """
cd /project
npm install
npm run build
npm test
"""

result = await execute_shell_command(script, timeout=600)
```

---

## 11. 常见问题

### Q1: 命令执行超时？

**原因：** 命令执行时间超过 timeout。

**解决：**

```python
# 1. 增加超时时间
result = await execute_shell_command(cmd, timeout=300)

# 2. 使用后台执行
# 在命令后加 & 放到后台
result = await execute_shell_command("long-running-cmd &", timeout=10)
```

### Q2: Windows 中文路径乱码？

**原因：** 系统编码不是 UTF-8。

**解决：**

```python
# 设置控制台编码
result = await execute_shell_command("chcp 65001 && dir")
```

### Q3: 进程无法终止？

**原因：** 子进程创建了更多子进程，杀不尽。

**解决：**

```python
# 确保 start_new_session=True
# 这样可以杀整个进程组
proc = await asyncio.create_subprocess_shell(
    cmd,
    start_new_session=True,
)
```

### Q4: stderr 包含有用信息？

**原因：** 很多程序将重要信息输出到 stderr。

**注意：**

```python
# stderr 不一定表示错误
# 某些命令（如 git）将警告输出到 stderr

result = await execute_shell_command("git status")
# 即使 returncode == 0，stderr 也可能有警告信息
```

---

## 12. 最佳实践

### 12.1 超时设置

```python
# 推荐：合理的超时设置
TIMEOUT_SHORT = 10   # 简单命令
TIMEOUT_MEDIUM = 60  # 一般操作
TIMEOUT_LONG = 300   # 构建、测试

# 根据命令类型选择超时
if "build" in command:
    timeout = TIMEOUT_LONG
elif "git" in command:
    timeout = TIMEOUT_MEDIUM
else:
    timeout = TIMEOUT_SHORT
```

### 12.2 工作目录隔离

```python
# 推荐：明确指定工作目录
result = await execute_shell_command(
    "npm test",
    cwd="/project",  # 明确指定
)

# 避免：依赖隐式工作目录
# result = await execute_shell_command("npm test")  # 不推荐
```

### 12.3 错误处理

```python
# 推荐：完整的错误处理
result = await execute_shell_command("npm run build", timeout=300)
if result.returncode != 0:
    logger.error(f"构建失败 (exit {result.returncode})")
    logger.error(f"stdout: {result.stdout}")
    logger.error(f"stderr: {result.stderr}")
    raise BuildError(result.stderr)
```

### 12.4 敏感信息

```python
# 推荐：避免在命令中硬编码敏感信息
# 使用环境变量
result = await execute_shell_command(
    f"API_KEY={api_key} python script.py"
)  # 不推荐

# 更好的方式：通过 env 参数传递
# （如果支持）
```

---

## 13. 总结

### 核心要点

| 要点 | 说明 |
|------|------|
| **跨平台** | Windows (线程池) + Unix (asyncio.subprocess) |
| **预处理** | 换行符折叠、Windows 转义修复 |
| **进程管理** | 进程组 `start_new_session`、SIGTERM → SIGKILL |
| **超时控制** | `asyncio.wait_for` + 优雅终止 |
| **智能解码** | UTF-8 优先，系统编码 fallback |
| **响应格式** | 成功/失败格式不同，stderr 单独标识 |
| **工作目录** | 优先使用 workspace_dir |
| **PATH 优先** | 确保 venv Python 在前面 |

### 平台差异总结

| 功能 | Windows | Unix |
|------|---------|------|
| 执行方式 | `subprocess` + 线程池 | `asyncio.subprocess_shell` |
| 进程终止 | `taskkill /F /T` | `killpg` |
| 管道处理 | 临时文件重定向 | 直接 PIPE |
| 换行处理 | 全部折叠 | 保留引号内 |

### 相关章节

- [53-文件操作与安全机制](./53-文件操作与安全机制.md) — Shell 中文件操作的访问控制
- [55-CLI命令系统详解](./55-CLI命令系统详解.md) — Shell 命令的 CLI 调用

---

## 关键文件索引

| 组件 | 文件路径 | 核心职责 |
|------|----------|----------|
| Shell 执行工具 | `src/qwenpaw/agents/tools/shell.py:285` | 主入口 |
| Windows 进程终止 | `src/qwenpaw/agents/tools/shell.py:23` | Windows 进程树终止 |
| 换行符处理 | `src/qwenpaw/agents/tools/shell.py:109` | 跨平台换行符处理 |
| 智能解码 | `src/qwenpaw/agents/tools/shell.py:447` | 编码处理 |
