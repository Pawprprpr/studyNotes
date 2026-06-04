# AI Agent 企业级实战知识骨架

> 基于 Java 专家视角构建的系统性学习框架
> 目标：能设计并实现类似于 OpenCode、Cursor 的企业级 AI 编程助手，并覆盖 CI 自动修复等场景

---

## 一、LLM 与推理基础

### 1.1 Transformer 核心概念
- 自注意力机制、多头注意力
- 位置编码（绝对/相对）
- 层归一化、残差连接
- *我的笔记：*

### 1.2 Token 与上下文窗口
- Tokenization（BPE、SentencePiece）
- 上下文长度、截断策略
- Token 消耗计算与优化
- *我的笔记：*

### 1.3 Prompt Engineering
- System / User / Assistant 角色
- 少样本示例（Few-shot）
- 思维链（Chain-of-Thought）、思维树（Tree-of-Thoughts）
- 结构化输出约束（JSON、YAML、正则）
- *我的笔记：*

### 1.4 Function Calling（工具调用规范）
- OpenAI 兼容的工具描述 JSON Schema
- 工具选择与参数填充
- 并行/串行调用策略
- *我的笔记：*

### 1.5 模型格式与量化
- GGUF、GPTQ、AWQ、bitsandbytes
- INT8 / INT4 推理性能与精度权衡
- 量化对代码能力的影响
- *我的笔记：*

### 1.6 推理服务与部署
- vLLM（PagedAttention、连续批处理）
- Ollama、llama.cpp、TGI
- 自托管 vs 云 API 的权衡
- 服务化设计（负载均衡、弹性伸缩）
- *我的笔记：*

### 1.7 AI SDK 与工具调用（✨新增）
- **Vercel AI SDK 核心概念**：
  - `streamText()` - 流式文本生成
  - `generateText()` - 非流式文本生成
  - `tool()` - 工具定义辅助函数
  - `jsonSchema()` - 参数 Schema 转换
- **AI SDK 控制循环 vs 自己控制循环**：
  - 传统 ReAct：每次工具调用都是独立的 LLM 请求
  - AI SDK：一次 `streamText()` 调用里，LLM 可以调用多次工具
  - AI SDK 自动执行工具，把结果塞回给 LLM
- **事件流架构**：
  - `fullStream` - 完整事件流（text-delta、tool-call、tool-result、finish 等）
  - `Stream.tap()` - 事件监听
  - `Stream.takeUntil()` - 条件终止
- **工具修复机制**：`experimental_repairToolCall` - 修复大小写不匹配等
- **与 LangChain 对比**：LangChain 更灵活但需要更多配置，AI SDK 更简洁但定制化程度低
- *我的笔记：*

> **📚 OpenCode 实战笔记**
>
> **AI SDK 在项目中的使用**（`session/llm.ts`）：
> ```typescript
> return streamText({
>   model: wrapLanguageModel({ model: language, middleware }),
>   messages,
>   tools,
>   toolChoice: input.toolChoice,
>   maxOutputTokens,
>   abortSignal: input.abort,
> })
> ```
>
> **事件流处理**（`session/processor.ts`）：
> ```typescript
> const stream = llm.stream(streamInput)
> yield* stream.pipe(
>   Stream.tap((event) => handleEvent(event)),
>   Stream.runDrain,
> )
> ```
>
> **关键事件类型**：
> - `start` - 开始
> - `text-start/delta/end` - 文本输出
> - `reasoning-start/delta/end` - 思考过程
> - `tool-input-start/delta/end` - 工具输入
> - `tool-call` - 工具调用
> - `tool-result` - 工具结果
> - `tool-error` - 工具错误
> - `finish` - 完成
>
> **关键代码位置**：
> - `session/llm.ts:261` - `streamText()` 调用
> - `session/processor.ts:513` - 流式处理
> - `session/processor.ts:129` - `handleEvent()` 事件处理

---

## 二、Agent 架构与核心模式

### 2.1 核心运行模式
- ReAct（推理-行动循环）
- Plan-Execute（先规划再执行）
- Self-Reflection（反思与自我修正）
- 终止条件判定（目标达成、超时、熔断）
- *我的笔记：*

> **📚 OpenCode 实战笔记**
> 
> 这个项目的 ReAct 实现特点：
> - **AI SDK 控制循环**：不是自己控制循环，而是把循环交给 Vercel AI SDK
> - **单次调用多次工具**：LLM 在一次 `streamText()` 调用里可以调用多次工具
> - **事件驱动架构**：LLM 输出 → 事件流 → `handleEvent()` 处理
> 
> 核心流程：
> ```
> prompt.ts:createUserMessage() → 创建用户消息
>     ↓
> runLoop() → while 循环处理
>     ↓
> resolveTools() → 准备工具列表给 LLM
>     ↓
> llm.stream() → 调用 AI SDK 的 streamText
>     ↓
> LLM 输出 tool_call
>     ↓
> AI SDK 自动执行工具，把结果塞回去
>     ↓
> LLM 继续输出，直到 finish
> ```
> 
> **关键代码位置**：
> - `session/prompt.ts:1356` - `prompt()` 方法入口
> - `session/prompt.ts:1388` - `runLoop()` 循环
> - `session/prompt.ts:441` - `resolveTools()` 准备工具
> - `session/processor.ts:501` - `handle.process()` 发起 LLM 调用
> - `session/processor.ts:129` - `handleEvent()` 处理事件

### 2.2 记忆管理
- 短期记忆（对话历史滑动窗口、Token 压缩）
- 长期记忆（向量存储、经验总结）
- 工作记忆（当前任务状态、中间结果）
- 记忆更新与遗忘策略
- *我的笔记：*

### 2.3 状态管理与任务调度
- 有限状态机设计（FSM）
- 任务取消、暂停、恢复
- 多任务并发与排队
- *我的笔记：*

> **📚 OpenCode 实战笔记**
> 
> 工具调用状态机：
> ```
> pending → running → completed
>                   ↘ error
> ```
> 
> 关键事件：`tool-input-start` → `tool-call` → `tool-result` / `tool-error`
> 
> **关键代码位置**：
> - `session/processor.ts:196` - `tool-call` 事件处理
> - `session/processor.ts:240` - `tool-result` 事件处理
> - `session/processor.ts:262` - `tool-error` 事件处理

### 2.4 多 Agent 协作（进阶）
- 主从模式、委派与汇总
- Agent 间通信协议
- *我的笔记：*

---

## 三、上下文工程与代码智能

### 3.1 代码解析与 AST
- tree-sitter 多语言增量解析
- JavaParser、TypeScript Compiler API
- 自定义查询（Query DSL）
- *我的笔记：*

### 3.2 代码分块与嵌入
- 分块策略（按函数、类、文件）
- 语义相似的合并与上下文窗口适配
- CodeBERT、StarCoder、UniXcoder 等嵌入模型
- sentence-transformers 调用
- *我的笔记：*

### 3.3 向量数据库与检索增强（RAG）
- Chroma / FAISS / Qdrant / Milvus
- 近似最近邻（ANN）索引
- 混合检索（向量 + BM25）
- 重排序（Re-rank）
- *我的笔记：*

### 3.4 LSP 集成
- LSP 协议核心（诊断、跳转定义、引用、符号）
- 客户端实现（pygls、lsp-types）
- 实时诊断与增量更新
- *我的笔记：*

### 3.5 增量索引与文件监听
- watchdog / inotify
- 索引更新策略（全量、增量、懒加载）
- *我的笔记：*

---

## 四、工具层与 CLI 联动

### 4.1 工具抽象与注册
- 统一 Tool 接口（名称、描述、参数 Schema、执行函数）
- 工具注册表与动态发现
- *我的笔记：*

> **📚 OpenCode 实战笔记**
>
> **Tool 接口设计**（`tool/tool.ts`）：
> ```typescript
> export interface Def<Parameters, M> {
>   description: string      // 工具描述，给 LLM 看
>   parameters: Parameters   // 参数校验器（Zod schema）
>   execute(args, ctx): Promise<{
>     title: string
>     metadata: M
>     output: string
>     attachments?: FilePart[]
>   }>
> }
> ```
>
> **工具注册中心**（`tool/registry.ts`）：
> - 内置工具注册：BashTool、ReadTool、EditTool 等 17 个
> - 动态目录发现：扫描 `{tool,tools}/*.{js,ts}`
> - 插件工具加载：从 `p.tool ?? {}` 获取
> - 工具过滤：根据模型/Agent 启用不同工具
>
> **工具执行流程**（`session/prompt.ts`）：
> ```
> registry.tools() → 获取所有工具定义
>     ↓
> AI SDK 的 tool() 包装
>     ↓
> execute() 实际调用 item.execute(args, ctx)
>     ↓
> 插件扩展点：tool.execute.before / tool.execute.after
> ```
>
> **扩展点设计**：
> - `tool.definition` 事件：修改工具的 description/parameters
> - `globalExtensionRegistry.transformToolDef()`：修改工具的 execute 方法
>
> **关键代码位置**：
> - `tool/tool.ts` - Tool 接口定义
> - `tool/registry.ts` - 工具注册中心
> - `tool/read.ts` - 简单工具实现示例
> - `tool/bash.ts` - 复杂工具实现（权限检查、命令解析）
> - `session/prompt.ts:441` - `resolveTools()` 工具转换
> - `session/prompt.ts:450` - execute 函数注册

### 4.2 命令行安全封装
- 异步子进程管理（asyncio subprocess）
- 超时、输出截断、环境隔离
- 资源限制（cgroups、rlimit、Docker 容器）
- 沙箱执行与权限控制
- *我的笔记：*

### 4.3 文件与代码修改
- 差异应用（unidiff、git diff/patch）
- 原子写入与备份
- 行级精确定位编辑（Replace、Insert、Delete）
- *我的笔记：*

### 4.4 构建系统集成
- Maven / Gradle / npm / Cargo 命令封装
- 依赖树解析
- 编译错误与测试报告解析
- *我的笔记：*

### 4.5 Git 操作
- GitPython / 直接调用 Git CLI
- 创建分支、提交、推送、rebase
- 冲突检测与处理
- *我的笔记：*

---

## 五、安全与企业可靠性

### 5.1 深度防御体系
- 输入校验 → 命令过滤 → 沙箱执行 → 行为审计 → 熔断机制
- *我的笔记：*

> **📚 OpenCode 实战笔记**
>
> **权限系统设计**（`permission/index.ts`）：
> - 三种 Action：`allow`（允许）、`deny`（拒绝）、`ask`（询问用户）
> - 规则匹配：`Wildcard.match()` 通配符匹配，`findLast` 找最后一个匹配规则
>
> **权限检查流程**：
> ```
> ctx.ask({ permission: "read", patterns: [filepath] })
>     ↓
> evaluate() 遍历规则
>     ↓
> deny? → 拒绝 | allow? → 通过 | ask? → 弹窗询问
>     ↓
> 等待用户确认/拒绝
> ```
>
> **Agent 权限配置**（`agent/agent.ts`）：
> - 三层叠加：defaults → Agent配置 → 用户配置
> - 内置 Agent 权限：`build`（全权限）、`plan`（禁用edit）、`explore`（只读+网络）
>
> **命令白名单**（`tool/bash.ts`）：
> - 只允许特定命令（rm, cp, mv, mkdir, cat 等）
> - 文件操作白名单：`CWD` + 特定路径
>
> **关键代码位置**：
> - `permission/index.ts` - 权限系统核心
> - `permission/evaluate.ts` - 规则评估算法
> - `agent/agent.ts` - Agent 权限配置
> - `tool/bash.ts:32-55` - 命令白名单

### 5.2 敏感信息检测与脱敏
- 正则匹配 + NER（Microsoft Presidio）
- 自动替换为占位符
- 上下文进入 LLM 前的清洗管道
- *我的笔记：*

### 5.3 权限分级与风险管控
- 修改范围/影响面风险评估
- 自动/半自动/人工审批分级
- 修改量熔断（最大文件数、行数、重试次数）
- *我的笔记：*

### 5.4 审计与可观测性
- 结构化行为日志（不可篡改）
- OpenTelemetry 分布式追踪
- Prometheus 指标监控
- Grafana 面板
- *我的笔记：*

### 5.5 提示注入防御
- 输入角色边界加固
- 用户数据与系统提示隔离
- 动态检测恶意指令
- *我的笔记：*

---

## 六、流式输出与实时交互（✨新增）

### 6.1 流式输出架构
- **Server-Sent Events (SSE)**：
  - 单向 Server → Client 推送
  - `text/event-stream` Content-Type
  - 自动重连机制
- **WebSocket vs SSE 对比**：
  - SSE：简单、单向、HTTP 兼容
  - WebSocket：双向、低延迟、更复杂
- **EventSource API**：
  - 浏览器原生支持
  - 自动重连、状态管理
- *我的笔记：*

### 6.2 流式事件设计模式
- **事件类型设计**：
  - `text-delta` - 文本增量
  - `tool-input-start/delta` - 工具输入流式
  - `tool-call` - 工具调用触发
  - `tool-result` - 工具执行结果
  - `reasoning-start/delta/end` - 思考过程
  - `finish` - 完成信号
- **事件序列设计**：
  - 保证事件顺序
  - 处理重复事件
  - 断点续传策略
- *我的笔记：*

### 6.3 前端流式渲染
- **React 流式组件**：
  - `useChat` / `useCompletion` Hooks
  - 流式状态管理
  - 自动滚动与分页
- **SSE 客户端实现**：
  - `fetch` + `ReadableStream`
  - `EventSource` API
  - 错误处理与重连
- **性能优化**：
  - 虚拟列表（大量消息）
  - 防抖与节流
  - 增量渲染
- *我的笔记：*

> **📚 OpenCode 实战笔记**
>
> **OpenCode 的流式输出实现**：
> - 后端：AI SDK 的 `streamText()` 返回 `fullStream`
> - 前端：`EventSource` 或 WebSocket 接收事件
> - 工具输入流式：`tool-input-start/delta/end` 事件
>
> **关键代码位置**：
> - `session/processor.ts:171` - `tool-input-start` 处理
> - `session/processor.ts:186` - `tool-input-delta` 处理
> - `session/processor.ts:193` - `tool-input-end` 处理
>
> **与 Cursor/GitHub Copilot 对比**：
> - 都是基于 SSE 的流式输出
> - 区别在于事件类型设计和前端渲染策略

---

## 七、CI/CD 集成与 MR 自动化

### 7.1 事件驱动与 Webhook
- GitLab CI / GitHub Actions Webhook 解析
- 从 artifacts 获取构建日志
- 失败事件路由
- *我的笔记：*

### 7.2 修复流水线
- 日志清洗 → 根因分析 → 修复方案生成 → 确认 → 应用修改 → 验证 → 创建 MR
- 自动化程度分级（全自动/半自动）
- *我的笔记：*

### 7.3 MR 生命周期管理
- 通过 API 创建 MR、更新描述、添加评论
- 指派 Reviewer、打标签（如 `autofix`）
- Conventional Commits 与 JIRA 编号提取
- rebase 冲突自动处理策略
- *我的笔记：*

### 7.4 构建验证与回归
- 隔离分支编译 + 单元测试
- 代码风格检查（lint）
- 受影响模块的测试回归
- 性能对比（可选）
- *我的笔记：*

---

## 八、前端与交互层（可选）

### 8.1 IDE 插件架构
- VS Code Extension API
- Webview、内联建议、装饰器
- *我的笔记：*

### 8.2 Web 控制台
- React + Monaco Editor / CodeMirror
- Diff 可视化（双栏对比、行内高亮）
- 流式输出显示（SSE / WebSocket）
- *我的笔记：*

---

## 九、基础设施与工程化

### 9.1 容器化与编排
- Docker、Docker Compose
- Kubernetes（生产环境）
- 多服务编排（推理服务 + Agent + 数据库）
- *我的笔记：*

### 9.2 网络与负载均衡
- Nginx / Traefik 反向代理
- SSE 长连接超时与缓冲设置
- 会话保持
- *我的笔记：*

### 9.3 配置与密钥管理
- 环境变量分层
- Vault / K8s Secrets
- 配置热更新
- *我的笔记：*

### 9.4 日志、监控与告警
- 结构化日志（JSON）
- ELK / Loki + Grafana
- 告警规则（连续失败、熔断触发）
- *我的笔记：*

---

## 十、学习路线与项目里程碑

### 10.1 里程碑 1：最小闭环 Agent
- 实现异步 Shell 工具安全调用
- 跑通 ReAct 循环
- *我的笔记：*

### 10.2 里程碑 2：CI 失败根因分析
- 解析真实 Java 项目构建日志
- 输出结构化根因报告
- *我的笔记：*

### 10.3 里程碑 3：自动修复与 MR
- 生成修复补丁 → 应用 → 编译验证
- 创建合规 MR
- *我的笔记：*

### 10.4 里程碑 4：安全加固与生产化
- 敏感信息脱敏、权限分级、审计日志
- 多场景测试与性能优化
- *我的笔记：*

---

## 十一、Java 专家学习对照表

| AI Agent 概念 | Java 中可类比的技术/模式 | 相似点 | 关键差异 |
|--------------|------------------------|--------|----------|
| ReAct 循环 | 工作流引擎状态机 (Camunda) | 步骤流转 | LLM 决策不确定，需结构化输出 |
| 工具调用 (Tool) | SPI 接口 + 策略模式 | 动态绑定 | 工具需自然语言描述 |
| 记忆管理 | Redis + 数据库持久层 | 数据存取 | 语义检索、Token 压缩 |
| 上下文引擎 (RAG) | 搜索引擎 + 数据管道 | 数据预处理 | 嵌入模型精度、切片策略 |
| 安全护栏 | Spring Security 过滤器链 | 拦截与审批 | 输入/输出两端防御，提示注入 |
| 熔断器 | Hystrix / Resilience4j | 失败保护 | 模型输出不可信导致的逻辑熔断 |
| AI SDK (streamText) | WebClient + 响应式流 (WebFlux) | 异步流式处理 | LLM 输出非结构化，需事件解析 |
| 事件流 (Event Stream) | Server-Sent Events / Reactive Streams | 异步事件推送 | 需要状态机管理事件序列 |
| 工具注册中心 | Spring Bean 容器 | 统一管理、依赖注入 | 工具需要自然语言描述供 LLM 理解 |

*我的补充与理解：*

---

## 十二、常用工具与资源速查

- 模型：CodeQwen、DeepSeek-Coder、Starcoder2
- 推理：Ollama、vLLM、llama.cpp
- 向量库：Chroma、FAISS、Qdrant
- 嵌入模型：BGE、CodeBERT、text-embedding-3-small
- LSP：pygls、bash-language-server、typescript-language-server
- 安全：Presidio、Bandit
- 框架参考：Open Interpreter、Aider、Continue、LangChain（源码阅读清单）
- *我的收藏：*
