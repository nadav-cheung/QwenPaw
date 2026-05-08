# 附录 A Java 开发者的 Python 快速参考

## A.0 速查表

| 概念 | Java | Python |
|------|------|--------|
| 变量声明 | `String name = "Alice"` | `name = "Alice"` 或 `name: str = "Alice"` |
| 空值 | `null` | `None` |
| 方法定义 | `public ReturnType method()` | `def method() -> ReturnType:` |
| 类定义 | `public class Foo {}` | `class Foo:` |
| 构造函数 | `public Foo() {}` | `def __init__(self):` |
| 异步方法 | `CompletableFuture<T>` | `async def` + `await` |
| 接口 | `interface Foo` | `class Foo(Protocol):` 或 `ABC` |
| 异常捕获 | `try {} catch {}` | `try: except:` |
| 类型注解 | `String` / `List<T>` | `str` / `list[T]` |
| 布尔值 | `true` / `false` | `True` / `False` |
| 集合字面量 | `List.of(1,2)` / `Map.of("a",1)` | `[1, 2]` / `{"a": 1}` |

> **提示**：Python 用缩进代替花括号 `{}` 定义代码块，每次使用 `:` 结尾的行后需要缩进。

---

## A.1 变量与类型

### A.1.1 基本变量声明

Python 变量无需声明类型，类型由赋值决定：

```python
# Python - 动态类型
name = "Alice"           # str
age = 25                 # int
height = 1.75            # float
is_student = True        # bool
data = None              # None (相当于 Java 的 null)
```

```java
// Java - 静态类型
String name = "Alice";
int age = 25;
double height = 1.75;
boolean isStudent = true;
Object data = null;
```

### A.1.2 类型注解（Type Hints）

Python 3.5+ 支持类型注解，虽不强制但便于 IDE 和类型检查：

```python
# Python - 类型注解（可选）
name: str = "Alice"
age: int = 25
scores: list[int] = [90, 85, 88]
person: dict[str, str] = {"name": "Alice", "city": "Beijing"}
```

```java
// Java - 类型必须声明
String name = "Alice";
int age = 25;
List<Integer> scores = List.of(90, 85, 88);
Map<String, String> person = Map.of("name", "Alice", "city", "Beijing");
```

> **重要**：类型注解仅用于静态检查，运行时不生效。`name: str = 123` 完全合法（只是违反类型约定）。

### A.1.3 常用类型对比

| Python 类型 | Java 类型 | 说明 |
|-------------|-----------|------|
| `int` | `int` / `Integer` | 整数 |
| `float` | `double` | 浮点数 |
| `str` | `String` | 字符串 |
| `bool` | `boolean` | 布尔值 |
| `list[T]` | `List<T>` | 列表 |
| `dict[K, V]` | `Map<K, V>` | 字典 |
| `set[T]` | `Set<T>` | 集合 |
| `tuple[T, ...]` | `Record` 或 `Pair` | 元组 |
| `None` | `null` | 空值 |

---

## A.2 数据结构

### A.2.1 列表（List）

```python
# Python 列表
fruits = ["apple", "banana", "orange"]
fruits.append("grape")           # 添加元素
first = fruits[0]               # 访问元素: "apple"
slice = fruits[1:3]             # 切片: ["banana", "orange"]
length = len(fruits)            # 长度: 4
```

```java
// Java 列表
List<String> fruits = new ArrayList<>(List.of("apple", "banana", "orange"));
fruits.add("grape");            // 添加元素
String first = fruits.get(0);    // 访问元素: "apple"
List<String> slice = fruits.subList(1, 3);  // 切片
int length = fruits.size();     // 长度: 4
```

### A.2.2 字典（Dict）

```python
# Python 字典
person = {"name": "Alice", "age": 25}
person["city"] = "Beijing"       # 添加/修改
name = person["name"]            # 访问: "Alice"
keys = person.keys()            # 所有键
values = person.values()        # 所有值
```

```java
// Java 字典
Map<String, Object> person = new HashMap<>();
person.put("name", "Alice");
person.put("age", 25);
person.put("city", "Beijing");   // 添加/修改
String name = (String) person.get("name");  // 访问: "Alice"
Set<String> keys = person.keySet();   // 所有键
Collection<Object> values = person.values();  // 所有值
```

### A.2.3 集合（Set）

```python
# Python 集合
colors = {"red", "green", "blue"}
colors.add("yellow")            # 添加
is_present = "red" in colors    # 检查成员: True
```

```java
// Java 集合
Set<String> colors = new HashSet<>(Set.of("red", "green", "blue"));
colors.add("yellow");           // 添加
boolean isPresent = colors.contains("red");  // 检查成员: true
```

---

## A.3 函数定义

### A.3.1 基本函数

```python
# Python 函数 - def 关键字，: 结尾，缩进定义代码块
def greet(name: str) -> str:
    return f"Hello, {name}!"

result = greet("Alice")  # "Hello, Alice!"
```

```java
// Java 方法 - public 返回类型 方法名(参数)
public String greet(String name) {
    return "Hello, " + name + "!";
}

// 调用
String result = greet("Alice");  // "Hello, Alice!"
```

### A.3.2 默认参数与可变参数

```python
# Python - 默认参数和 *args, **kwargs
def func(a, b=10, *args, **kwargs):
    print(f"a={a}, b={b}")           # a=1, b=2
    print(f"args={args}")             # args=(3, 4)
    print(f"kwargs={kwargs}")         # kwargs={'key': 'value'}

func(1, 2, 3, 4, key="value")
```

```java
// Java - 可变参数 (varargs)
public void func(int a, int b, int... args) {
    System.out.println("a=" + a + ", b=" + b);  // a=1, b=2
    System.out.println("args=" + Arrays.toString(args));  // args=[3, 4]
}

// 只能通过 Map 模拟 kwargs
Map<String, Object> kwargs = new HashMap<>();
kwargs.put("key", "value");
```

### A.3.3 Lambda 表达式

```python
# Python Lambda - 表达式匿名函数
square = lambda x: x ** 2
numbers = [1, 2, 3, 4]
squared = list(map(lambda x: x ** 2, numbers))  # [1, 4, 9, 16]
```

```java
// Java Lambda - -> 语法
Function<Integer, Integer> square = x -> x * x;
List<Integer> numbers = List.of(1, 2, 3, 4);
List<Integer> squared = numbers.stream()
    .map(x -> x * x)
    .collect(Collectors.toList());  // [1, 4, 9, 16]
```

---

## A.4 类与对象

### A.4.1 类定义与构造函数

```python
# Python 类 - __init__ 是构造函数
class Person:
    def __init__(self, name: str, age: int):
        self.name = name          # self 相当于 Java 的 this
        self.age = age
        self._score = 0           # _ 前缀表示受保护（约定）

    def greet(self) -> str:
        return f"Hi, I'm {self.name}"

    def __str__(self) -> str:     # toString()
        return f"Person({self.name}, {self.age})"

# 使用
person = Person("Alice", 25)
print(person.greet())  # "Hi, I'm Alice"
```

```java
// Java 类 - 构造函数与类名相同
public class Person {
    private String name;
    private int age;
    private int score;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
        this.score = 0;
    }

    public String greet() {
        return "Hi, I'm " + name;
    }

    @Override
    public String toString() {
        return "Person(" + name + ", " + age + ")";
    }
}

// 使用
Person person = new Person("Alice", 25);
System.out.println(person.greet());  // "Hi, I'm Alice"
```

### A.4.2 继承与多态

```python
# Python 继承 - 直接在类名后加 (父类,)
class Student(Person):
    def __init__(self, name: str, age: int, grade: str):
        super().__init__(name, age)  # 调用父类构造函数
        self.grade = grade

    def greet(self) -> str:          # 重写方法
        return f"{super().greet()}, I'm in grade {self.grade}"

# 多态
def introduce(p: Person):
    print(p.greet())

student = Student("Bob", 15, "10th")
introduce(student)  # "Hi, I'm Bob, I'm in grade 10th"
```

```java
// Java 继承 - extends 关键字
public class Student extends Person {
    private String grade;

    public Student(String name, int age, String grade) {
        super(name, age);  // 调用父类构造函数
        this.grade = grade;
    }

    @Override
    public String greet() {  // 重写方法
        return super.greet() + ", I'm in grade " + grade;
    }
}

// 多态
public void introduce(Person p) {
    System.out.println(p.greet());
}

Student student = new Student("Bob", 15, "10th");
introduce(student);  // "Hi, I'm Bob, I'm in grade 10th"
```

### A.4.3 dataclass（QwenPaw 常用）

dataclass 自动生成 `__init__`、`__repr__`、`__eq__` 等方法，大幅简化数据类：

```python
# Python dataclass - 自动生成常用方法
from dataclasses import dataclass

@dataclass
class Message:
    role: str
    content: str
    metadata: dict = None  # 默认值

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

# 自动生成：__init__, __repr__, __eq__, __hash__
msg = Message(role="user", content="Hello")
print(msg)  # Message(role='user', content='Hello', metadata={})
```

```java
// Java 传统方式 - 需要手动编写
public class Message {
    private String role;
    private String content;
    private Map<String, Object> metadata;

    public Message(String role, String content) {
        this(role, content, new HashMap<>());
    }

    public Message(String role, String content, Map<String, Object> metadata) {
        this.role = role;
        this.content = content;
        this.metadata = metadata;
    }

    // getters, setters, toString, equals, hashCode...
}
```

> **QwenPaw 提示**：QwenPaw 智能体开发中大量使用 dataclass 作为消息、状态、工具参数的数据载体。

---

## A.5 异步编程

### A.5.1 async/await 基本用法

```python
# Python 异步 - async def 定义协程，await 等待结果
import asyncio

async def fetch_data(url: str) -> dict:
    # 模拟异步 IO 操作
    await asyncio.sleep(1)  # 相当于 Java 的 CompletableFuture.delayed
    return {"url": url, "data": "result"}

async def main():
    # 并发执行多个协程
    results = await asyncio.gather(
        fetch_data("https://api.example.com/1"),
        fetch_data("https://api.example.com/2"),
    )
    print(results)

# 运行
asyncio.run(main())
```

```java
// Java 异步 - CompletableFuture
import java.net.http.HttpClient;
import java.time.Duration;

public CompletableFuture<JsonNode> fetchData(String url) {
    return HttpClient.newHttpClient()
        .sendAsync(HttpRequest.newBuilder(URI.create(url)).build(),
            HttpResponse.BodyHandlers.ofString())
        .thenApply(response -> parseJson(response.body()))
        .exceptionally(ex -> {
            System.err.println("Error: " + ex.getMessage());
            return JsonNode.nullNode();
        });
}

public void main() {
    CompletableFuture.allOf(
        fetchData("https://api.example.com/1"),
        fetchData("https://api.example.com/2")
    ).thenAccept(v -> System.out.println("All done"));
}
```

### A.5.2 对比总结

| 特性 | Python | Java |
|------|--------|------|
| 异步定义 | `async def` | `CompletableFuture<T>` |
| 等待异步结果 | `await` | `.thenApply()` / `.join()` |
| 并发执行 | `asyncio.gather()` | `CompletableFuture.allOf()` |
| 延迟 | `asyncio.sleep()` | `CompletableFuture.delayed()` |
| 异常处理 | `try/except` | `.exceptionally()` |

> **提示**：Python 的 async/await 是协程模型，代码以同步风格编写但异步执行；Java 的 CompletableFuture 是回调模型。

---

## A.6 Protocol 接口定义

### A.6.1 结构化子类型（Protocol）

Python 的 `Protocol` 类似 Java 的接口，用于定义结构化子类型：

```python
# Python Protocol - 定义接口
from typing import Protocol

class Drawable(Protocol):
    def draw(self) -> None: ...

    def get_area(self) -> float: ...

class Circle:
    def __init__(self, radius: float):
        self.radius = radius

    def draw(self) -> None:
        print(f"Drawing circle with radius {self.radius}")

    def get_area(self) -> float:
        return 3.14 * self.radius ** 2

def render(d: Drawable) -> None:  # 只要求实现了 draw 和 get_area
    d.draw()
    print(f"Area: {d.get_area()}")

circle = Circle(5)
render(circle)  # 正常工作，Circle 隐式实现了 Drawable
```

```java
// Java 接口
public interface Drawable {
    void draw();
    double getArea();
}

public class Circle implements Drawable {
    private double radius;

    public Circle(double radius) {
        this.radius = radius;
    }

    @Override
    public void draw() {
        System.out.println("Drawing circle with radius " + radius);
    }

    @Override
    public double getArea() {
        return 3.14 * radius * radius;
    }
}

public void render(Drawable d) {  // Circle 实现了 Drawable
    d.draw();
    System.out.println("Area: " + d.getArea());
}
```

> **QwenPaw 提示**：QwenPaw 的技能系统（Skill System）使用 Protocol 定义工具接口，`Tool` Protocol 规定了 `execute()` 等方法的签名。

---

## A.7 装饰器

### A.7.1 方法装饰器

Python 装饰器是修改函数/方法行为的函数，类似 Java 的注解但更强大：

```python
# Python 装饰器
def log_calls(func):
    def wrapper(*args, **kwargs):
        print(f"Calling {func.__name__}")
        result = func(*args, **kwargs)
        print(f"{func.__name__} returned {result}")
        return result
    return wrapper

@log_calls
def add(a: int, b: int) -> int:
    return a + b

add(1, 2)
# 输出:
# Calling add
# add returned 3
```

```java
// Java 注解 + AOP（Spring 等框架）
@Aspect
@Component
public class LoggingAspect {
    @Around("execution(* com.example.add(..))")
    public Object logCalls(ProceedingJoinPoint pjp) throws Throwable {
        System.out.println("Calling " + pjp.getSignature().getName());
        Object result = pjp.proceed();
        System.out.println(pjp.getSignature().getName() + " returned " + result);
        return result;
    }
}
```

### A.7.2 @property 装饰器

```python
# Python @property - 将方法转为属性
class Person:
    def __init__(self, name: str):
        self._name = name

    @property
    def name(self) -> str:
        return self._name

    @name.setter
    def name(self, value: str):
        if not value:
            raise ValueError("Name cannot be empty")
        self._name = value

person = Person("Alice")
print(person.name)   # "Alice" - 像访问属性一样
person.name = "Bob"  # 调用 setter
```

```java
// Java getter/setter
public class Person {
    private String name;

    public Person(String name) {
        this.name = name;
    }

    public String getName() {
        return name;
    }

    public void setName(String value) {
        if (value == null || value.isEmpty()) {
            throw new IllegalArgumentException("Name cannot be empty");
        }
        this.name = value;
    }
}

Person person = new Person("Alice");
System.out.println(person.getName());  // 需要调用方法
person.setName("Bob");
```

---

## A.8 异常处理

### A.8.1 基本语法

```python
# Python - try/except 结构
try:
    result = 10 / 0
except ZeroDivisionError as e:
    print(f"Cannot divide by zero: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
else:
    print("Success!")       # 无异常时执行
finally:
    print("Cleanup")       # 始终执行
```

```java
// Java - try/catch 结构
try {
    int result = 10 / 0;
} catch (ArithmeticException e) {
    System.out.println("Cannot divide by zero: " + e.getMessage());
} catch (Exception e) {
    System.out.println("Unexpected error: " + e.getMessage());
} finally {
    System.out.println("Cleanup");  // 始终执行
}
```

### A.8.2 自定义异常

```python
# Python 自定义异常
class ValidationError(Exception):
    def __init__(self, field: str, message: str):
        self.field = field
        self.message = message
        super().__init__(f"{field}: {message}")

raise ValidationError("email", "Invalid format")
```

```java
// Java 自定义异常
public class ValidationError extends Exception {
    private String field;
    private String message;

    public ValidationError(String field, String message) {
        super(field + ": " + message);
        this.field = field;
        this.message = message;
    }
}

throw new ValidationError("email", "Invalid format");
```

---

## A.9 QwenPaw 常用模式

### A.9.1 异步工具执行（QwenPaw 技能系统核心）

```python
# QwenPaw 异步工具模式
import asyncio
from dataclasses import dataclass
from typing import Protocol

class Tool(Protocol):
    async def execute(self, **kwargs) -> dict: ...

@dataclass
class Calculator:
    async def execute(self, expression: str) -> dict:
        try:
            result = eval(expression)  # 简化示例，实际应使用安全求值
            return {"success": True, "result": result}
        except Exception as e:
            return {"success": False, "error": str(e)}

async def run_tool(tool: Tool, params: dict) -> dict:
    return await tool.execute(**params)

async def main():
    calc = Calculator()
    result = await run_tool(calc, {"expression": "2 + 3"})
    print(result)  # {'success': True, 'result': 5}

asyncio.run(main())
```

### A.9.2 消息传递模式

```python
# QwenPaw 消息模式
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class Message:
    role: str                          # "user", "assistant", "system"
    content: str
    metadata: dict = field(default_factory=dict)

class Conversation:
    def __init__(self):
        self.messages: list[Message] = []

    def add(self, role: str, content: str, **kwargs):
        msg = Message(role=role, content=content, metadata=kwargs)
        self.messages.append(msg)
        return msg

    def get_history(self) -> list[Message]:
        return self.messages.copy()

conv = Conversation()
conv.add("user", "Hello!")
conv.add("assistant", "Hi, how can I help?")
for msg in conv.get_history():
    print(f"{msg.role}: {msg.content}")
```

---

## A.10 快速开发参考

### A.10.1 环境准备

```bash
# 创建虚拟环境（类似 Java 的 Maven/Gradle wrapper）
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 安装依赖（类似 pom.xml 或 build.gradle）
pip install qwenpaw openai python-dotenv

# 运行（类似 java -jar）
python main.py
```

### A.10.2 常用标准库导入

```python
# 文件操作
from pathlib import Path
Path("output.txt").write_text("content")

# JSON 处理
import json
data = json.loads('{"key": "value"}')

# 日期时间
from datetime import datetime
now = datetime.now()

# 类型提示
from typing import Optional, Union, Callable, TypeVar
T = TypeVar('T')
```

### A.10.3 调试技巧

```python
# 打印调试（类似 Java 的 System.out.println）
print(f"Debug: {variable}")

# 断言（类似 Java 的 assert）
assert result == expected, f"Expected {expected}, got {result}"

# 详细错误信息
import traceback
try:
    risky_operation()
except Exception:
    traceback.print_exc()
```

---

## 附录对照索引

| Python 特性 | Java 对应 | 参考章节 |
|-------------|-----------|----------|
| `def func():` | `ReturnType method()` | A.3 |
| `self` | `this` | A.4 |
| `__init__` | 构造函数 | A.4.1 |
| `async/await` | `CompletableFuture` | A.5 |
| `Protocol` | `interface` | A.6 |
| `@property` | `getter/setter` | A.7.2 |
| `dataclass` | POJO / Record | A.4.3 |
| `try/except` | `try/catch` | A.8 |
| `*args, **kwargs` | `varargs`, `Map` | A.3.2 |
| `None` | `null` | A.1.1 |

---

> **持续学习**：本快速参考覆盖 Java 开发者入门 Python 所需的核心概念。QwenPaw 智能体开发中的高级特性（如异步流处理、上下文管理、元编程）请参考正文各章节。
