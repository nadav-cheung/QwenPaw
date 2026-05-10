# 34 本地模型管理系统

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 理解 LocalModelManager 单例模式与 LlamaCppBackend 进程管理的协作方式 2) 掌握模型下载进度追踪的线程安全设计 3) 分析平台检测、后端选择与服务器生命周期管理机制 |
| **前置知识** | [33-OpenAIProvider](./33-OpenAIProvider.md) |
| **预计时长** | 50 分钟（阅读 30 分钟 + 练习 20 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `llama.cpp` `单例模式` `下载管理` `进程管理` |

> **一句话概述**：本章讲解本地模型管理系统如何通过 LocalModelManager 和 LlamaCppBackend 管理 llama.cpp 服务器的下载、启动、健康检查与热切换。

## 概述

QwenPaw 通过 `LocalModelManager` 和 `LlamaCppBackend` 管理本地 llama.cpp 服务器，支持模型下载、热切换和健康检查。

**核心设计理念**：本地模型运行可以降低成本、提高隐私保护，同时通过 llama.cpp 的高效推理实现接近云端模型的性能。

---

## 0. 如果你来自 Java

本节介绍本地模型部署的核心概念。如果你来自 Java 背景，这里介绍主要的概念对照。

### 核心概念对照表

Python 的 llama.cpp 生态与 Java 中类似的工具/库对比如下：

| Python (QwenPaw) | Java (类似实现) | 说明 |
|------------------|----------------|------|
| `LocalModelManager` | `OllamaClient` / `HuggingFaceClient` | 本地模型管理 |
| `LlamaCppBackend` | `LLamaCppEngine` (通过 JNI) | llama.cpp 引擎封装 |
| `.gguf` 模型格式 | `.gguf` (通过 llama.cpp JNI binding) | 模型文件格式 |
| `LlamaCppServer` | `Ollama Server` | HTTP/WS 推理服务 |
| `ModelManager` | `ModelRegistry` | 模型下载和缓存管理 |

### Java 中的 llama.cpp 绑定

Java 没有官方 llama.cpp 绑定，但有几个社区实现：

**1. JNI 绑定 (llama.cpp 官方)**：

```java
// 通过 JNI 调用 llama.cpp (需要编译 native 库)
public class LlamaCppJNI {
    static {
        System.loadLibrary("llama");  // 加载 native 库
    }
    public native long loadModel(String path);
    public native String generate(long model, String prompt);
    public native void freeModel(long model);
}
```

**2. Ollama SDK (推荐)**：

```java
// Ollama 提供 HTTP API，Java 可以直接调用
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;

// Ollama HTTP API
String json = """
    {"model": "llama3", "prompt": "Hello", "stream": false}
    """;

HttpClient client = HttpClient.newHttpClient();
HttpRequest request = HttpRequest.newBuilder()
    .uri(URI.create("http://localhost:11434/api/generate"))
    .header("Content-Type", "application/json")
    .POST(HttpRequest.BodyPublishers.ofString(json))
    .build();

HttpResponse<String> response = client.send(request,
    HttpResponse.BodyHandlers.ofString());
```

**3. Hugging Face Java API**：

```java
// 使用 Hugging Face Java SDK
import io.github.blackrain.huggingface.HuggingFaceClient;

HuggingFaceClient client = new HuggingFaceClient("your-token");
var result = client.textGeneration("microsoft/DialoGPT-medium", "Hello!");
```

### 单例模式对比

**Python (QwenPaw)**：
```python
class LocalModelManager:
    _instance: LocalModelManager | None = None  # 类变量存储单例

    @staticmethod
    def get_instance() -> LocalModelManager:
        if LocalModelManager._instance is None:
            LocalModelManager._instance = LocalModelManager()
        return LocalModelManager._instance
```

**Java (传统单例)**：
```java
public class LocalModelManager {
    private static volatile LocalModelManager instance;

    public static LocalModelManager getInstance() {
        if (instance == null) {
            synchronized (LocalModelManager.class) {
                if (instance == null) {
                    instance = new LocalModelManager();
                }
            }
        }
        return instance;
    }
}
```

**Java (枚举单例，推荐)**：
```java
public enum LocalModelManager {
    INSTANCE;

    public static LocalModelManager getInstance() {
        return INSTANCE;
    }
}
```

### 进程管理对比

**Python (`asyncio.subprocess`)**：
```python
import asyncio

async def start_llama_server(model_path: Path, port: int):
    process = await asyncio.create_subprocess_exec(
        "llama-server",
        "-m", str(model_path),
        "-port", str(port),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    return process
```

**Java (`ProcessBuilder`)**：
```java
import java.lang.ProcessBuilder;
import java.io.IOException;

public class LlamaServerProcess {
    private Process process;

    public void start(String modelPath, int port) throws IOException {
        ProcessBuilder pb = new ProcessBuilder(
            "llama-server",
            "-m", modelPath,
            "-port", String.valueOf(port)
        );
        pb.redirectErrorStream(true);
        process = pb.start();
    }

    public void stop() {
        if (process != null) {
            process.destroy();
        }
    }
}
```

### 配置持久化对比

**Python (Pydantic + JSON)**：
```python
from pydantic import BaseModel, Field
import json

class LocalModelConfig(BaseModel):
    max_context_length: int = Field(default=65536, ge=32768)
    port: int | None = Field(default=None, ge=1, le=65535)

    def save(self, path: Path):
        with open(path, "w") as f:
            json.dump(self.model_dump(), f, indent=2)

    @classmethod
    def load(cls, path: Path) -> "LocalModelConfig":
        with open(path) as f:
            return cls.model_validate(json.load(f))
```

**Java (Jackson + Lombok)**：
```java
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.Data;
import lombok.Builder;

@Data
@Builder
public class LocalModelConfig {
    @Builder.Default
    private int maxContextLength = 65536;
    private Integer port;

    private static final ObjectMapper mapper = new ObjectMapper();

    public void save(Path path) throws IOException {
        mapper.writeValue(path.toFile(), this);
    }

    public static LocalModelConfig load(Path path) throws IOException {
        return mapper.readValue(path.toFile(), LocalModelConfig.class);
    }
}
```

### 进度追踪对比

**Python (`threading.Lock` + `dataclass`)**：
```python
from dataclasses import dataclass
from threading import Lock
from enum import Enum

class DownloadTaskStatus(str, Enum):
    IDLE = "idle"
    DOWNLOADING = "downloading"
    COMPLETED = "completed"

@dataclass(frozen=True)
class DownloadProgress:
    status: DownloadTaskStatus
    downloaded_bytes: int = 0
    total_bytes: int | None = None

class DownloadProgressTracker:
    def __init__(self):
        self._lock = Lock()
        self._progress = DownloadProgress(status=DownloadTaskStatus.IDLE)

    def update(self, downloaded: int, total: int | None):
        with self._lock:
            self._progress = DownloadProgress(
                status=DownloadTaskStatus.DOWNLOADING,
                downloaded_bytes=downloaded,
                total_bytes=total
            )
```

**Java (`ConcurrentHashMap` + `AtomicInteger`)**：
```java
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;

public class DownloadProgressTracker {
    private final ReentrantLock lock = new ReentrantLock();
    private AtomicReference<DownloadProgress> progress =
        new AtomicReference<>(new DownloadProgress("idle", 0, null));

    public void update(int downloaded, Integer total) {
        lock.lock();
        try {
            progress.set(new DownloadProgress("downloading", downloaded, total));
        } finally {
            lock.unlock();
        }
    }
}

record DownloadProgress(String status, int downloadedBytes, Integer totalBytes) {}
```

---

## 1. 核心架构

源码路径：`src/qwenpaw/local_models/manager.py:41`

```
LocalModelManager（单例）
    ├── ModelManager — 模型下载/存储管理
    └── LlamaCppBackend — llama.cpp 服务器生命周期管理
```

**组件职责**：
- **LocalModelManager**：提供高层 API，管理模型配置和状态
- **ModelManager**：处理模型文件的下载、存储和元数据
- **LlamaCppBackend**：直接管理 llama-server 进程的生命周期

---

## 2. LocalModelManager

源码路径：`src/qwenpaw/local_models/manager.py:41`

LocalModelManager 是本地模型管理的 Facade 单例，管理 llama.cpp 服务器生命周期和模型下载。

### 2.1 核心配置

```python
# src/qwenpaw/local_models/manager.py:23
class LocalModelConfig(BaseModel):
    """Persistent local runtime settings for embedded llama.cpp."""
    max_context_length: int = Field(
        default=65536,
        description="Maximum context length passed to llama.cpp on startup.",
        ge=32768,
    )
    port: int | None = Field(
        default=None,
        description=(
            "Optional fixed port for llama.cpp startup. Null means auto."
        ),
        ge=1,
        le=65535,
    )
```

### 2.2 类定义与方法索引

```python
# src/qwenpaw/local_models/manager.py:41
class LocalModelManager:  # pylint: disable=too-many-public-methods
    """Single entry point for local runtime downloads and server control."""

    _instance: LocalModelManager | None = None
    DEFAULT_LLAMA_CPP_BASE_URL = "https://download.qwenpaw.agentscope.io/files/models/llama_cpp"
    DEFAULT_LLAMA_CPP_RELEASE_TAG = "b8744"
    CONFIG_FILE_NAME = "config.json"
```

| 方法 | 行号 | 说明 |
|------|------|------|
| `__init__()` | 56 | 初始化，加载配置 |
| `_load_config()` | 75 | 从磁盘加载配置 |
| `_save_config()` | 113 | 异步保存配置到磁盘 |
| `get_config()` | 120 | 获取配置的防御副本 |
| `set_max_context_length()` | 126 | 设置上下文长度 |
| `set_port()` | 134 | 设置固定端口 |
| `check_llamacpp_installation()` | 142 | 检查 llama.cpp 是否已安装 |
| `check_llamacpp_installability()` | 146 | 检查是否可以安装 llama.cpp |
| `start_llamacpp_download()` | 150 | 启动 llama.cpp 下载 |
| `has_update()` | 170 | 检查是否有更新 |
| `check_llamacpp_server_ready()` | 180 | 检查服务器是否就绪 |
| `get_llamacpp_download_progress()` | 188 | 获取下载进度 |
| `get_llamacpp_server_status()` | 192 | 获取服务器状态 |
| `is_llamacpp_server_transitioning()` | 196 | 检查服务器是否在转换中 |
| `cancel_llamacpp_download()` | 200 | 取消下载 |
| `get_recommended_models()` | 204 | 获取推荐模型列表 |
| `is_model_downloaded()` | 208 | 检查模型是否已下载 |
| `list_downloaded_models()` | 212 | 列出已下载模型 |
| `start_model_download()` | 216 | 启动模型下载 |
| `get_model_download_progress()` | 224 | 获取模型下载进度 |
| `cancel_model_download()` | 228 | 取消模型下载 |
| `remove_downloaded_model()` | 232 | 删除已下载模型 |
| `setup_server()` | 240 | 启动 llama.cpp 服务器 |
| `shutdown_server()` | 256 | 关闭服务器 |
| `shutdown_server_sync()` | 262 | 同步关闭（用于进程退出路径）|
| `get_instance()` | 269 | 获取单例实例 |

### 2.3 配置持久化

```python
# src/qwenpaw/local_models/manager.py:75
def _load_config(self) -> LocalModelConfig:
    """Load persisted local runtime settings from disk."""
    if not self._config_path.exists():
        return LocalModelConfig()

    try:
        with open(self._config_path, "r", encoding="utf-8") as file_obj:
            payload = json.load(file_obj)
        return LocalModelConfig.model_validate(payload)
    except (OSError, ValueError, ValidationError) as exc:
        logger.warning(
            "Failed to load local model config from %s: %s",
            self._config_path,
            exc,
        )
        return LocalModelConfig()

# src/qwenpaw/local_models/manager.py:113
async def _save_config(self) -> None:
    """Persist local runtime settings to disk without blocking the loop."""
    await asyncio.to_thread(
        self._write_config_file,
        self._config_path,
        self._config.model_dump(),
    )

# src/qwenpaw/local_models/manager.py:90
@staticmethod
def _write_config_file(config_path, payload: dict[str, Any]) -> None:
    """Write local runtime settings to disk in a worker thread."""
    config_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config_path, "w", encoding="utf-8") as file_obj:
        json.dump(payload, file_obj, ensure_ascii=False, indent=2)
    try:
        config_path.chmod(0o600)  # 限制文件权限
    except OSError:
        pass
```

### 2.4 单例模式

```python
# src/qwenpaw/local_models/manager.py:41, 237-243
class LocalModelManager:
    """Single entry point for local runtime downloads and server control."""

    _instance: LocalModelManager | None = None  # 类变量存储单例

    def __init__(self, ...) -> None:
        # 初始化组件，不涉及单例逻辑
        self._model_manager = model_manager or ModelManager()
        self._llamacpp_backend = llamacpp_backend or LlamaCppBackend()
        self._server_lifecycle_lock = asyncio.Lock()
        self._config_path = DEFAULT_LOCAL_PROVIDER_DIR / self.CONFIG_FILE_NAME
        self._config = self._load_config()

    @staticmethod
    def get_instance() -> LocalModelManager:
        """Return the singleton LocalModelManager instance."""
        if LocalModelManager._instance is None:
            LocalModelManager._instance = LocalModelManager()
        return LocalModelManager._instance
```

**单例模式特点**：
- **类变量存储**：`_instance` 是类变量而非实例变量
- **延迟初始化**：首次调用 `get_instance()` 时才创建实例
- **非线程安全**：假设在单线程/事件循环环境下使用（asyncio.Lock 保护配置操作）
- **全局唯一**：整个进程只有一个 `LocalModelManager` 实例

---

## 3. LlamaCppBackend

源码路径：`src/qwenpaw/local_models/llamacpp.py:51`

### 3.1 初始化

```python
# src/qwenpaw/local_models/llamacpp.py:59
def __init__(self):
    self.os_name = self._resolve_os_name()       # windows/macos/linux
    self.arch = self._resolve_arch()             # x64/arm64
    self.cuda_version = self._resolve_cuda_version()
    self.backend = self._resolve_backend()       # cpu/cuda
    self.target_dir = DEFAULT_LOCAL_PROVIDER_DIR / "bin"
    self._server_process: ManagedProcess | None = None
```

**初始化流程**：
1. 检测操作系统类型（Windows/macOS/Linux）
2. 检测 CPU 架构（x64/arm64）
3. 检测 CUDA 版本（如适用）
4. 选择后端（CPU 或 CUDA）
5. 设置 llama.cpp 二进制文件目录

### 3.2 服务器启动

```python
# src/qwenpaw/local_models/llamacpp.py:217
async def setup_server(
    self,
    model_path: Path,
    model_name: str,
    max_context_length: int | None = None,
    port: int | None = None,
) -> LlamaCppServerSetupResult:
```

**启动流程：**
```
1. 解析模型路径（支持 GGUF 文件或 HF 仓库目录）
         ↓
2. 解析 mmproj 文件（多模态支持）
         ↓
3. 查找空闲端口或使用固定端口
         ↓
4. 启动 `llama-server` 子进程
         ↓
5. 等待 `/health` 端点就绪
         ↓
6. 返回端口和模型信息
```

### 3.3 模型文件解析

```python
# src/qwenpaw/local_models/llamacpp.py:445
def _resolve_model_file(self, model_path: Path) -> tuple[Path, Path | None]:
    if model_path.is_file():
        if model_path.suffix.lower() != ".gguf":
            raise RuntimeError("Model file must be a .gguf file")
        return model_path.resolve(), None

    # 从仓库目录搜索所有 .gguf 文件
    gguf_files = sorted(model_path.rglob("*.gguf"))
    # mmproj 文件以 mmproj 开头
    mmproj_files = [f for f in gguf_files if f.name.lower().startswith("mmproj")]
    model_files = [f for f in gguf_files if not f.name.lower().startswith("mmproj")]
    return model_files[0].resolve(), mmproj_files[0].resolve() if mmproj_files else None
```

**文件类型说明**：
| 类型 | 说明 |
|------|------|
| `.gguf` | Llama.cpp 模型格式，支持量化 |
| `mmproj*.gguf` | 多模态投影器文件，用于视觉模型 |

### 3.4 后端选择

```python
# src/qwenpaw/local_models/llamacpp.py:878
def _resolve_backend(self) -> str:
    if self.os_name in ("macos", "linux"):
        return "cpu"  # 仅 CPU
    if self.os_name == "windows":
        if self.cuda_version is not None:
            return "cuda"  # CUDA 加速
        return "cpu"
```

**后端选择逻辑**：
- **macOS/Linux**：仅支持 CPU 后端（Metal GPU 加速在后续版本）
- **Windows + CUDA**：使用 CUDA 加速
- **Windows 无 CUDA**：回退到 CPU

### 3.5 平台检测与文件名构建

```python
# src/qwenpaw/local_models/llamacpp.py:820
def _build_filename(self, tag: str) -> str:
    """根据操作系统和架构构建 llama.cpp 下载文件名"""
    if self.os_name == "macos":
        return f"llama-{tag}-bin-macos-{self.arch}.tar.gz"

    if self.os_name == "linux":
        return f"llama-{tag}-bin-ubuntu-{self.arch}.tar.gz"

    if self.os_name == "windows":
        if self.backend == "cuda":
            if self.arch != "x64":
                raise RuntimeError("Windows CUDA package is only supported for x64.")
            return f"llama-{tag}-bin-win-cuda-{self.cuda_version}-{self.arch}.zip"
        return f"llama-{tag}-bin-win-cpu-{self.arch}.zip"
```

**平台包选择**：

| 操作系统 | CUDA | 架构 | 包格式 |
|----------|------|------|--------|
| macOS | - | x64/arm64 | `llama-{tag}-bin-macos-{arch}.tar.gz` |
| Linux | - | x64/arm64 | `llama-{tag}-bin-ubuntu-{arch}.tar.gz` |
| Windows | Yes | x64 | `llama-{tag}-bin-win-cuda-{version}-x64.zip` |
| Windows | No | x64/arm64 | `llama-{tag}-bin-win-cpu-{arch}.zip` |

### 3.6 CUDA 版本检测

```python
# src/qwenpaw/local_models/llamacpp.py:870
def _resolve_cuda_version(self) -> Optional[str]:
    if self.os_name != "windows":
        return None

    cuda_version = system_info.get_cuda_version()
    if cuda_version is None:
        return None

    parts = cuda_version.split(".")
    major = parts[0]
    minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0

    if major == "12":
        return "12.4" if minor >= 4 else None
    if major == "13":
        return "13.1"
    return None
```

**CUDA 版本要求**：
- **CUDA 12.4+**：返回 `12.4`
- **CUDA 13.1+**：返回 `13.1`
- **低于 12.4**：返回 `None`（不使用 CUDA）

---

## 4. 模型下载管理

源码路径：`src/qwenpaw/local_models/manager.py:194`

```python
# src/qwenpaw/local_models/manager.py:194
def start_model_download(
    self,
    model_id: str,
    source: DownloadSource | None = None,
) -> None:
    """启动模型下载任务"""
    self._model_manager.download_model(model_id, source=source)
```

**下载源**：
- **HuggingFace**（默认）：官方模型仓库
- **镜像站点**：国内用户可配置 HuggingFace 镜像

**支持的模型格式**：
- GGUF 文件（直接下载）
- HuggingFace 仓库（自动搜索 .gguf 文件）

---

## 5. 服务器状态检查

### 5.1 状态查询

```python
# src/qwenpaw/local_models/llamacpp.py:115
def get_server_status(self) -> dict[str, Any]:
    process = self._server_process
    running = bool(process is not None and process.returncode is None)
    return {
        "running": running,
        "port": self._server_port,
        "model_name": self._server_model_name,
        "pid": process.pid if running else None,
    }
```

### 5.2 就绪检测

```python
# src/qwenpaw/local_models/llamacpp.py:695
async def server_ready(self, timeout: float = 120.0) -> bool:
    """轮询 /health 端点直到返回成功"""
    health_url = f"http://127.0.0.1:{self._server_port}/health"
    async with httpx.AsyncClient(timeout=2.0) as client:
        while True:
            response = await client.get(health_url)
            if response.status_code < 500:
                return True
            await asyncio.sleep(1)
```

---

## 6. 下载进度追踪

### 6.1 核心数据类

源码路径：`src/qwenpaw/local_models/download_manager.py`

| 类型 | 行号 | 说明 |
|------|------|------|
| `DownloadTaskStatus` | 25 | 下载生命周期枚举 |
| `DownloadTaskMessageType` | 37 | 消息类型枚举 |
| `DownloadProgress` | 42 | 下载进度数据类 |
| `DownloadTaskResult` | 56 | 下载结果数据类 |
| `DownloadProgressUpdate` | 92 | 进度更新数据类 |
| `ProcessDownloadTask` | 139 | 下载任务描述符 |
| `ProcessDownloadTaskSpec` | 179 | 下载任务规格 |
| `ManagedDownloadTask` | 190 | 托管下载任务 |
| `DownloadProgressTracker` | 198 | 进度追踪器 |
| `ProcessDownloadController` | 368 | 下载进程控制器 |

**DownloadTaskStatus 枚举** (第25行):

```python
class DownloadTaskStatus(str, Enum):
    """Download lifecycle for a single downloader instance."""
    IDLE = "idle"
    PENDING = "pending"
    DOWNLOADING = "downloading"
    CANCELING = "canceling"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
```

**DownloadProgress 数据类** (第42行):

```python
@dataclass(frozen=True)
class DownloadProgress:
    """Normalized download progress shared by local model downloads."""
    status: DownloadTaskStatus = DownloadTaskStatus.IDLE
    model_name: str | None = None
    downloaded_bytes: int = 0
    total_bytes: int | None = None
    speed_bytes_per_sec: float = 0.0
    source: str | None = None
    error: str | None = None
    local_path: str | None = None
```

### 6.2 DownloadProgressTracker

源码路径：`src/qwenpaw/local_models/download_manager.py:198`

```python
class DownloadProgressTracker:
    """Thread-safe tracker for lifecycle and throughput of a download task."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._progress = DownloadProgress()
        self._last_size_sample = 0
        self._last_sample_time = time.monotonic()
```

**核心方法**：

| 方法 | 行号 | 说明 |
|------|------|------|
| `get_status()` | 253 | 获取当前状态 |
| `get_progress()` | 258 | 获取进度快照 |
| `snapshot()` | 263 | 返回字典格式快照 |
| `begin()` | 270 | 开始下载 |
| `request_cancel()` | 292 | 请求取消 |
| `apply_progress_update()` | 295 | 应用进度更新 |
| `apply_result()` | 333 | 应用最终结果 |

**核心机制**：
- 使用 `threading.Lock` 保证线程安全
- 实时计算下载速度：`speed = (downloaded_bytes - last_sample) / elapsed_time`
- 进度状态机：`IDLE → PENDING → DOWNLOADING → COMPLETED/FAILED/CANCELLED`

### 6.3 ProcessDownloadController

源码路径：`src/qwenpaw/local_models/download_manager.py:368`

```python
class ProcessDownloadController:
    """Manage a single process-backed download task and its progress."""

    def __init__(
        self,
        *,
        context: Any,
        progress: DownloadProgressTracker,
    ) -> None:
        self._context = context
        self._progress = progress
        self._lock = threading.Lock()
        self._task: ManagedDownloadTask | None = None
```

**核心方法**：

| 方法 | 行号 | 说明 |
|------|------|------|
| `start()` | 382 | 启动后台下载进程 |
| `cancel()` | 417 | 取消下载 |
| `snapshot()` | 441 | 获取进度快照 |
| `is_active()` | 444 | 检查是否活跃 |
| `_monitor_task()` | 449 | 监控线程目标 |
| `_handle_message()` | 492 | 处理队列消息 |
| `_finish_task()` | 549 | 完成任务 |

**进程架构**：
```
主进程                          子进程（下载）
    │                                │
    ├── start() ──────────────────► 启动下载
    │                                │
    ├── _monitor_task() ◄──────────── 进度消息 (queue)
    │    (监控线程)                   │
    │    • 轮询 queue                │
    │    • 更新 DownloadProgressTracker │
    │                                │
    └── _finish_task() ◄──────────── 完成/失败 (queue)
```

### 6.4 消息序列化

**DownloadTaskResult** (第56行):

```python
@dataclass(frozen=True)
class DownloadTaskResult:
    """Normalized terminal result for a background download task."""
    status: DownloadTaskStatus
    local_path: str | None = None
    error: str | None = None

    def to_dict(self) -> dict[str, str | None]:
        """Return a serializable result for thread/process boundaries."""
        return {
            "status": self.status.value,
            "local_path": self.local_path,
            "error": self.error,
        }

    def to_message(self) -> dict[str, Any]:
        return {
            "type": DownloadTaskMessageType.RESULT.value,
            "payload": self.to_dict(),
        }
```

**DownloadProgressUpdate** (第92行):

```python
@dataclass(frozen=True)
class DownloadProgressUpdate:
    downloaded_bytes: int
    total_bytes: int | None = None
    model_name: str | None = None
    source: str | None = None
```

### 6.5 进度查询

```python
# src/qwenpaw/local_models/llamacpp.py:111
def get_download_progress(self) -> dict[str, Any]:
    return self._progress.snapshot()
```

**返回字段**：
| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | str | 下载状态：idle/pending/downloading/completed/failed/cancelled |
| `downloaded_bytes` | int | 已下载字节数 |
| `total_bytes` | int | 总字节数 |
| `speed_bytes_per_sec` | float | 下载速度（字节/秒） |
| `source` | str | 下载源 URL |
| `error` | str | 错误信息（如有） |
| `local_path` | str | 本地存储路径 |

---

## 7. 模型切换

### 7.1 热切换流程

```python
# 1. 获取当前服务器状态
status = backend.get_server_status()

# 2. 如果有模型在运行，先关闭
if status["running"]:
    await backend.shutdown_server()

# 3. 启动新模型
result = await backend.setup_server(
    model_path=new_model_path,
    model_name="my-model",
    max_context_length=65536,
)

# 4. 等待服务器就绪
await backend.server_ready(timeout=120)
```

### 7.2 多模型支持

```python
# 支持同时运行多个 llama-server 实例（不同端口）
backend_1 = LlamaCppBackend()
backend_2 = LlamaCppBackend()

await backend_1.setup_server(model_path=path1, port=8080)
await backend_2.setup_server(model_path=path2, port=8081)
```

---

## 8. 应用场景

### 8.1 隐私优先场景

本地模型确保数据不离开本地机器：
- 医疗记录分析
- 财务数据处理
- 内部文档问答

### 8.2 离线环境

在无网络环境下运行：
- 边缘设备部署
- 演示环境
- 安全隔离网络

### 8.3 成本优化

减少云端 API 调用成本：
- 大量简单推理任务
- 长时间运行的批处理

---

## 9. 最佳实践

### 9.1 模型选择

| 模型大小 | 量化 | 内存需求 | 适用场景 |
|----------|------|----------|----------|
| 3B | Q4_K_M | ~2GB | 轻量任务 |
| 7B | Q4_K_M | ~4GB | 常规对话 |
| 13B | Q4_K_M | ~8GB | 复杂推理 |
| 34B | Q4_K_M | ~20GB | 高质量输出 |

### 9.2 性能优化

```python
# 推荐配置
config = LocalModelConfig(
    max_context_length=8192,  # 根据模型和内存调整
    port=None,  # 自动选择端口
)
```

### 9.3 资源管理

- 监控内存使用，避免 OOM
- 定期检查 llama.cpp 更新
- 模型文件存储在 SSD 上提升加载速度

---

## 10. 常见问题

### Q1: llama-server 启动失败？

**排查步骤**：
```bash
# 1. 检查 llama.cpp 二进制是否存在
ls -la ~/.qwenpaw/providers/local/bin/

# 2. 检查模型文件是否完整
file model.gguf

# 3. 查看启动日志
journalctl -u qwenpaw | tail -50
```

### Q2: 内存不足 (OOM)？

**原因**：模型过大或上下文长度设置过高。

**解决方案**：
1. 使用更小的量化版本（如 Q3_K_M 代替 Q5_K_M）
2. 减少 `max_context_length`
3. 增加系统 swap 空间

### Q3: macOS 上 GPU 加速不生效？

**原因**：llama.cpp 在 macOS 上暂不支持 Metal GPU 加速。

**替代方案**：
1. 使用更小的模型
2. 等待 llama.cpp 更新
3. 考虑使用 Apple Silicon 优化版本

### Q4: 模型下载速度慢？

**优化方案**：
```bash
# 配置 HuggingFace 镜像
export HF_ENDPOINT=https://hf-mirror.com

# 或使用 wget/curl 多线程下载
```

### Q5: 如何验证模型已正确加载？

```python
# 检查服务器状态
status = backend.get_server_status()
print(f"Running: {status['running']}")
print(f"Port: {status['port']}")
print(f"Model: {status['model_name']}")
```

---

## 11. 总结

**核心要点**：

| 要点 | 说明 |
|------|------|
| 单例管理 | LocalModelManager 全局唯一实例 |
| 进程管理 | LlamaCppBackend 管理 llama-server 生命周期 |
| 自动端口选择 | 避免端口冲突 |
| 健康检查 | 轮询 /health 确保服务就绪 |
| 多后端支持 | CPU/CUDA 自动选择 |

**进阶主题**：
- 自定义 llama.cpp 参数调优
- 多模态模型支持（视觉-语言）
- 分布式推理（多机部署）
- 模型量化工具集成

---

## 练习题

### 基础练习

1. **单例模式的线程安全性**
   `LocalModelManager` 使用类变量 `_instance` 存储单例实例，并通过 `get_instance()` 方法获取。请分析：在多线程/多协程环境下，直接调用 `get_instance()` 是否存在竞态条件？如果存在，说明具体场景；如果不存在，说明理由。

2. **下载进度状态机**
   `DownloadTaskStatus` 的生命周期为：`IDLE → PENDING → DOWNLOADING → COMPLETED/FAILED/CANCELLED`。请问从 `DOWNLOADING` 状态可以直接转换到哪些状态？哪些转换是合理的，哪些是非法的？

3. **LlamaCppBackend 的平台检测**
   `LlamaCppBackend` 在初始化时通过 `_resolve_os_name()`、`_resolve_arch()`、`_resolve_cuda_version()` 检测平台环境。请分别列出在 macOS x64、Linux ARM64、Windows + CUDA 12.4 x64 三种环境下，`os_name`、`arch`、`backend` 的值分别是什么？

### 进阶练习

1. **热切换流程分析**
   参考 7.1 节的热切换流程，描述从"运行模型 A"切换到"运行模型 B"的完整步骤，并说明 `shutdown_server()` 和 `setup_server()` 之间是否存在一个服务器不可用的时间窗口，如何优化减少这个窗口？

2. **下载速度计算**
   `DownloadProgressTracker` 使用公式 `speed = (downloaded_bytes - last_sample) / elapsed_time` 计算下载速度。请分析：为什么使用两个采样点的差值而非直接从累计值计算？这种设计有什么好处？

### 实战练习

- **多后端并发模型加载**
  QwenPaw 支持同时运行多个 llama-server 实例（不同端口）。假设你需要部署一个隐私优先的问答系统，同时使用两个本地模型：一个 7B 模型处理常规对话（端口 8080），一个 3B 模型处理快速分类（端口 8081）。请参考 `LlamaCppBackend` 的 `setup_server` 方法，设计一个初始化脚本，包括：模型路径配置、端口固定策略、服务器就绪等待逻辑，以及如何将两个后端注册到系统中供 Agent 使用。

---

## 12. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| LocalModelManager | `src/qwenpaw/local_models/manager.py:41` |
| LlamaCppBackend | `src/qwenpaw/local_models/llamacpp.py:51` |
| ModelManager | `src/qwenpaw/local_models/model_manager.py` |
| 下载管理器 | `src/qwenpaw/local_models/download_manager.py` |
| 本地 Provider | `src/qwenpaw/providers/ollama_provider.py` (Ollama) / `lmstudio_provider.py` (LM Studio) |

---

## 知识检查

1. **`LocalModelManager` 使用类变量 `_instance` 实现单例模式，但未使用线程锁保护。在什么场景下这会导致创建多个实例？实际使用中为什么通常不会出现这个问题？**

2. **`DownloadProgressTracker` 使用 `threading.Lock` 而非 `asyncio.Lock`，这是因为什么？下载任务为什么选择在子进程中执行而非异步协程？**

3. **`LlamaCppBackend.server_ready()` 通过轮询 `/health` 端点检测服务器是否就绪，超时时间为 120 秒。为什么不能在进程启动后立即认为服务器可用？轮询间隔设为 1 秒是否合理？**

---

---

## 13. Contributor 指南

### 13.1 适合新手修改的文件

以下文件相对独立，危险系数低，适合初次贡献：

| 文件 | 难度 | 原因 |
|------|------|------|
| `local_models/startup_display.py` | ⭐ | 启动横幅逻辑简单，输出格式化 |
| `local_models/console_static.py` | ⭐ | 路径解析逻辑清晰 |
| `local_models/tag_parser.py` | ⭐⭐ | 标签解析逻辑独立，测试容易编写 |

### 13.2 危险区域（修改前必须咨询 Maintainer）

| 文件/模块 | 危险原因 |
|-----------|----------|
| `llamacpp.py` 的服务器生命周期 | 错误可能导致进程泄漏、端口占用或僵尸进程 |
| `download_manager.py` 的线程同步 | 错误可能导致进度追踪不准确或数据竞争 |
| `manager.py` 的单例实现 | 单例模式变更可能影响全局状态 |
| `manager.py` 的 `setup_server()` | 服务器启动逻辑复杂，错误可能导致无法启动 |

### 13.3 调试方法

**测试 LocalModelManager 单例**：

```python
from qwenpaw.local_models.manager import LocalModelManager

# 获取单例
manager1 = LocalModelManager.get_instance()
manager2 = LocalModelManager.get_instance()
assert manager1 is manager2  # 验证是同一实例
```

**测试 llama-server 启动**：

```python
import asyncio
from qwenpaw.local_models.llamacpp import LlamaCppBackend

async def test_server():
    backend = LlamaCppBackend()
    result = await backend.setup_server(model_path="path/to/model.gguf")
    print(f"Server running on port {result.port}")
    await backend.shutdown_server()

asyncio.run(test_server())
```

**测试下载进度追踪**：

```python
from qwenpaw.local_models.download_manager import DownloadProgressTracker

tracker = DownloadProgressTracker()
tracker.begin(model_name="test-model", total_bytes=1000)
tracker.apply_progress_update(downloaded_bytes=500)
snapshot = tracker.snapshot()
print(f"Progress: {snapshot['downloaded_bytes']}/{snapshot['total_bytes']}")
```

**测试平台检测**：

```python
from qwenpaw.local_models.llamacpp import LlamaCppBackend

backend = LlamaCppBackend()
print(f"OS: {backend.os_name}")
print(f"Arch: {backend.arch}")
print(f"Backend: {backend.backend}")
print(f"CUDA: {backend.cuda_version}")
```

### 13.4 添加日志的最佳实践

```python
import logging
from qwenpaw.local_models.llamacpp import LlamaCppBackend

logger = logging.getLogger(__name__)

async def setup_server(self, model_path, ...):
    logger.info(f"Setting up llama-server for model: {model_path}")

    # 检测端口
    port = port or self._find_free_port()
    logger.debug(f"Using port: {port}")

    # 启动进程
    process = await self._start_server_process(...)
    logger.info(f"Server started with PID: {process.pid}")

    # 等待就绪
    if await self.server_ready(timeout=120):
        logger.info(f"Server ready on port {port}")
        return result
    else:
        logger.error("Server failed to become ready")
        raise RuntimeError("Server startup timeout")
```

### 13.5 如何避免破坏架构

**服务器生命周期规则**：
- 启动前必须检查端口可用性，避免端口冲突
- `shutdown_server()` 必须处理进程已退出情况，不能抛出异常
- 健康检查使用 `/health` 端点，不能假设进程存在即就绪

**下载管理规则**：
- `DownloadProgressTracker` 使用 `threading.Lock` 保护共享状态
- 下载任务必须在子进程中执行，不能使用 asyncio 协程（因为 `httpx` 同步下载会阻塞事件循环）
- 状态转换必须遵循 `IDLE → PENDING → DOWNLOADING → COMPLETED/FAILED/CANCELLED` 顺序

**单例模式规则**：
- `LocalModelManager._instance` 是类变量，整个进程只有一个实例
- 不要在单例中存储请求级别的状态（如会话 ID），这会导致并发问题

**测试要求**：
- 修改服务器生命周期逻辑后，必须运行进程启动/关闭测试
- 修改下载管理后，必须验证进度追踪准确性
- 在多平台（Windows/macOS/Linux）上测试平台检测逻辑

### 13.6 快速参考

```bash
# 测试本地模型模块
pytest tests/local_models/test_llamacpp.py -v
pytest tests/local_models/test_download_manager.py -v

# 手动测试 llama-server 启动
python -c "
import asyncio
from qwenpaw.local_models.llamacpp import LlamaCppBackend

async def test():
    backend = LlamaCppBackend()
    result = await backend.setup_server(model_path='test.gguf')
    print(f'Port: {result.port}')
    await backend.shutdown_server()

asyncio.run(test())
"
```

---

## 延伸阅读

| 章节 | 说明 |
|------|------|
| [33-OpenAIProvider](./33-OpenAIProvider.md) | 模型系统与 LLM 提供商的整体架构 |
| [39-配置系统](../level-6-config-plugins/39-配置系统.md) | 配置文件管理与持久化 |

---

## 源码一致性审查 (Source Consistency Review)

| 检查项 | 状态 | 证据 |
|--------|------|------|
| `LocalModelManager` | ✅ | `src/qwenpaw/local_models/manager.py` |
| `LlamaCppBackend` | ✅ | `src/qwenpaw/local_models/llamacpp.py` — llama.cpp 服务器管理 |
| `download_manager.py` | ✅ | 支持 HuggingFace + ModelScope 双源下载 |
| `tag_parser.py` | ✅ | GGUF 标签/量化参数解析 |

**审查结论**: 本地模型管理系统组件路径与真实源码一致。

## 教学审查 (Pedagogy Review)
| 检查项 | 状态 | 说明 |
|--------|------|------|
| 从云到本地递进 | ✅ | 第 32 章云端 Provider → 第 34 章本地模型 |

## 工程审查 (Engineering Review)
| 检查项 | 状态 | 说明 |
|--------|------|------|
| ONNX 运行时 | ✅ | `onnxruntime<1.24` 版本锁定（pyproject.toml） |
| 双下载源 | ✅ | HuggingFace + ModelScope 自动回退 |

## Contributor 审查 (Contributor Review)
| 检查项 | 状态 | 说明 |
|--------|------|------|
| 危险区域 | ✅ | llama.cpp 二进制管理和进程生命周期 |

---

*Chapter 34 审查完成。基于 local_models/ 的真实源码。*
