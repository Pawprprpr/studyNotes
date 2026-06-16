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
> **调用链路**：
> ```
> 用户发消息 → prompt() → runLoop() → while true 循环
>                                         ↓
>                              handle.process() → llm.stream() → AI SDK
> ```
>
> **关键关系**：
> - 每次用户发消息 → 调用一次 `prompt()` → 创建新的 `runLoop()`
> - `while true` 控制"一次消息里需要处理多少轮工具调用"
> - 每次 `handle.process()` = 一次完整 LLM 请求
>
> **handle.process() 返回三种可能**（`processor.ts:545-550`）：
> - `"continue"` = LLM 调用结束了，但还没"说完"，继续下一轮 while true
> - `"stop"` = LLM 说完了，退出 while true
> - `"compact"` = 上下文太长了，需要压缩后继续
>
> **runLoop 判断逻辑**（`prompt.ts:1574-1603`）：
> ```typescript
> const result = yield* handle.process({...})
>
> // 1. structured 输出 → break
> if (structured !== undefined) return "break"
>
> // 2. finished 且没错误 → break
> const finished = handle.message.finish && !["tool-calls", "unknown"].includes(handle.message.finish)
> if (finished && !handle.message.error) return "break"
>
> // 3. result === "stop" → break
> if (result === "stop") return "break"
>
> // 4. result === "compact" → compact 然后 continue
> if (result === "compact") {
>   yield* compaction.create({...})
>   return "continue"
> }
>
> // 5. 其他 → continue
> return "continue"
> ```
>
> **重要**：`finish = "tool-calls"` 不算 finished，会继续循环
>
> **AI SDK 自动处理工具调用**：
> - `llm.stream()` 内部收到 `tool-call` 事件
> - AI SDK 自动执行工具，把结果塞回去
> - 等 `streamText()` 返回时，所有 tool-call 已经执行完毕
> - 一个 `while true` 循环里，可能有多次 tool-call，但只有一次 `llm.stream()`
>
> **关键代码位置**：
> - `session/prompt.ts:1356` - `prompt()` 方法入口
> - `session/prompt.ts:1388` - `runLoop()` 循环
> - `session/prompt.ts:1561` - 调用 `handle.process()`
> - `session/prompt.ts:1593` - 判断 result 决定 break/continue
> - `session/processor.ts:545-550` - handle.process 返回值逻辑
> - `session/llm.ts:261` - `streamText()` 调用

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

### 2.5 Provider / Model（LLM 接入层）（✨新增）

> **📚 OpenCode 实战笔记**
>
> **整体定位**：Provider 是 Agent 和 LLM 之间的桥梁。Agent 说"我要用 claude-sonnet-4"，Provider 负责：找到模型 → 创建 SDK 客户端 → 返回 AI SDK 能用的 LanguageModelV3 对象。
>
> **Java 类比**：DataSource 接口，背后可以是 MySQL/PostgreSQL/Oracle。
>
> **三层类型体系**：
> ```
> ProviderID (品牌标识) → Info (Provider 全量配置) → Model (一个具体模型)
> ```
>
> | 类型 | 含义 | Java 类比 |
> |------|------|-----------|
> | `ProviderID` | Effect Schema Brand 品牌字符串（anthropic、openai...） | 枚举 |
> | `Info` | Provider 全量信息：名称、Key、env、模型列表 | DataSource 配置 Bean |
> | `Model` | 模型元数据：能力、费用、上下文、变体 | Connection 配置 |
>
> **ProviderID 和 ModelID 用 Brand Type**（`provider/schema.ts`）：
> - 编译时类型安全，运行时就是字符串
> - 不能把 ProviderID 传给需要 ModelID 的函数
> - Java 类比：类似自定义类型 `ProviderID extends String`，但 Java 做不到编译时强类型
>
> **初始化 6 步流程**（`provider/provider.ts:1014-1339`）：
> ```
> 1. ModelsDev.get()         → 加载模型数据库（所有已知 Provider+Model 元数据）
> 2. config 合并             → opencode.json 中的用户自定义 Provider
> 3. env 检测                → 环境变量中的 API Key（ANTHROPIC_API_KEY 等）
> 4. auth 读取               → 存储中的 OAuth/API Key
> 5. custom() 后处理          → 每个 Provider 的定制化逻辑
> 6. filter                  → 过滤 disabled/alpha/deprecated
> ```
>
> **优先级链**：database → config → env → auth → custom → filter，后者覆盖前者。
> **Java 类比**：Spring PropertySource 优先级链。
>
> **custom() 函数——Provider 后处理器**（`provider/provider.ts:175-820`）：
>
> 每个 Provider 可定义特殊行为，返回：
> ```typescript
> {
>   autoload: boolean,           // 无 Key 时是否还显示
>   getModel?: CustomModelLoader, // 自定义模型创建逻辑
>   vars?: CustomVarsLoader,     // URL 变量替换（${GOOGLE_VERTEX_PROJECT}）
>   options?: Record<string, any>, // 传给 SDK 的额外选项
>   discoverModels?: CustomDiscoverModels  // 动态发现模型
> }
> ```
>
> 典型例子：
> - **anthropic**：添加 `anthropic-beta` 请求头（扩展思考、工具流式）
> - **openai**：用 `sdk.responses()` 而非 `sdk.languageModel()`（OpenAI Responses API）
> - **amazon-bedrock**：根据 region 自动加前缀（`us.claude-sonnet-4`），处理 AWS 凭证链
> - **gitlab**：运行时动态发现工作流模型（`discoverModels`）
> - **azure**：根据配置选择 `sdk.responses()` 或 `sdk.chat()`
>
> **Java 类比**：BeanPostProcessor，每个供应商有自己的后处理器。
>
> **getLanguage() 核心调用路径**（`provider/provider.ts:1503-1544`）：
> ```
> Agent 要用模型 → Provider.getLanguage(model)
>   → resolveSDK(model) 创建 SDK 客户端
>     → BUNDLED_PROVIDERS[api.npm] 内置？或 Npm.add() 动态安装？
>   → modelLoaders[providerID] 存在？用自定义 getModel()
>     → 否则用 sdk.languageModel(model.api.id)
>   → 缓存到 Map<string, LanguageModelV3>
> ```
>
> **resolveSDK 关键逻辑**（`provider/provider.ts:1344-1479`）：
> 1. 合并 options（baseURL、apiKey、headers）
> 2. URL 中的 `${VAR}` 变量替换（varsLoaders + 环境变量）
> 3. Hash 缓存 key（同 providerID + npm + options 复用 SDK 实例）
> 4. 包装自定义 fetch：超时控制、SSE 超时检测（`wrapSSE`）
> 5. 优先 BUNDLED_PROVIDERS（编译时打包的 20+ SDK），否则动态 `npm install + import`
>
> **BUNDLED_PROVIDERS**（`provider/provider.ts:129-153`）：
> ```typescript
> BUNDLED_PROVIDERS = {
>   "@ai-sdk/anthropic": createAnthropic,
>   "@ai-sdk/openai": createOpenAI,
>   "@ai-sdk/amazon-bedrock": createAmazonBedrock,
>   // ... 20+ 个
> }
> ```
> 如果模型的 `api.npm` 不在此表中，resolveSDK 会动态 `npm install` + `import`。
>
> **ProviderTransform——消息适配层**（`provider/transform.ts`）：
>
> 处理不同 LLM 的"怪癖"（Dialect 模式）：
>
> | 函数 | 作用 |
> |------|------|
> | `normalizeMessages()` | Anthropic 不接受空 content；Claude toolCallId 只能含字母数字下划线；Mistral toolId 限9字符且 tool 后不能紧跟 user |
> | `applyCaching()` | 对 system 和最后2条消息加缓存标记（Anthropic/OpenRouter/Bedrock 各有不同字段名） |
> | `unsupportedParts()` | 模型不支持图片/PDF 时，把附件转成文本提示 |
> | `variants()` | 推理模型的思考级别配置（high/max/low），每个 Provider 参数格式不同 |
> | `temperature()` | 不同模型默认温度（qwen: 0.55, gemini: 1.0, claude: undefined） |
> | `options()` | 每个 Provider 特殊请求选项（openai: store=false, openrouter: usage.include=true） |
> | `schema()` | Gemini 不接受 integer 枚举，转成 string |
> | `providerOptions()` | 把选项映射到正确的 SDK 命名空间（azure 需同时设 openai 和 azure） |
>
> **Java 类比**：DatabaseDialect，不同数据库的 SQL 方言翻译层。
>
> **ProviderAuth——认证流程**（`provider/auth.ts`）：
> - **API Key**：直接存 key，由 custom() 或 env 填入
> - **OAuth**：`authorize()` → 浏览器授权 → `callback()` 拿到 access_token/refresh_token
> - OAuth 通过 Plugin 的 `auth` 钩子扩展（如 GitLab 的 OAuth 流程）
>
> **关键代码位置**：
> - `provider/schema.ts:6` - ProviderID Brand Type 定义
> - `provider/schema.ts:29` - ModelID Brand Type 定义
> - `provider/provider.ts:129-153` - BUNDLED_PROVIDERS 映射表
> - `provider/provider.ts:175-820` - custom() Provider 后处理器
> - `provider/provider.ts:822-891` - Model 类型定义
> - `provider/provider.ts:893-906` - Info 类型定义
> - `provider/provider.ts:1014-1339` - 初始化 6 步流程
> - `provider/provider.ts:1344-1479` - resolveSDK
> - `provider/provider.ts:1503-1544` - getLanguage
> - `provider/provider.ts:1614-1643` - defaultModel
> - `provider/transform.ts:278` - message 消息适配
> - `provider/transform.ts:364` - variants 思考级别
> - `provider/transform.ts:746` - options Provider 选项
> - `provider/transform.ts:907` - providerOptions 命名空间映射
> - `provider/auth.ts:165` - authorize
> - `provider/auth.ts:192` - callback

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

## 十一、核心知识点提炼（✨新增）

### 11.1 AI Agent 的 ReAct 模式实现

**架构特点**：
- 采用 Vercel AI SDK 实现 ReAct 循环
- 传统 ReAct：每次工具调用都是独立 LLM 请求
- AI SDK 实现：一次 `streamText()` 调用里，LLM 可以决定调用多个工具
- AI SDK 自动执行工具并把结果塞回给 LLM，继续对话，直到 LLM 说"好了"

**关键代码**：`session/llm.ts:261` - `streamText()` 调用

---

### 11.2 事件驱动架构

**事件流处理**：
- LLM 返回的是事件流（Event Stream）
- 包含 `text-delta`、`tool-call`、`tool-result`、`reasoning-delta` 等事件
- OpenCode 通过 `handleEvent()` 处理每个事件，只做 UI 状态更新
- 实际工具执行是 AI SDK 在 `streamText()` 内部完成的

**关键代码**：
- `session/processor.ts:513` - 流式处理
- `session/processor.ts:129` - `handleEvent()` 事件处理

---

### 11.3 工具注册与扩展机制

**三层架构**：
1. **工具定义层**（`tool/read.ts` 等）：定义工具的 description、parameters、execute 方法
2. **工具注册层**（`tool/registry.ts`）：统一注册管理，支持动态发现和插件加载
3. **工具包装层**（`session/prompt.ts`）：在 execute 外层包装插件扩展点（before/after）

**扩展点设计**：
```typescript
execute(args, options) {
  yield* plugin.trigger("tool.execute.before", ...)
  const result = yield* item.execute(args, ctx)  // 原工具的 execute
  yield* plugin.trigger("tool.execute.after", ...)
  return output
}
```

**工具注册时机**：
- 工具提前在 `registry.ts` 注册好
- 每次 while 循环，`resolveTools()` 从注册表获取工具
- 转成 AI SDK 格式，传给 LLM
- LLM 决定调用哪个工具，AI SDK 执行对应的 execute 函数

**完整工具调用链路**：
```
用户发消息
    ↓
prompt() → createUserMessage()
    ↓
runLoop() → while true 循环开始
    ↓
第1次循环：
    resolveTools() ← 获取所有工具
        ↓
    registry.tools() ← 查注册表
        ↓
    返回 Tool.Def 列表
        ↓
    转成 AI SDK 格式（tools[name] = tool({ execute: ... })）
        ↓
    handle.process({ tools }) ← 发给 LLM
        ↓
    LLM 返回 tool_call: bash
        ↓
    AI SDK 调用 tools["bash"].execute(args, options)
        ↓
    session/prompt.ts:450 的 execute 函数
        ↓
    item.execute(args, ctx) ← bash.ts 的 execute
        ↓
    bash.ts 调用 ctx.ask() 请求权限
        ↓
    permission.ask() → 发布 Event.Asked → 前端弹窗
        ↓
    用户允许 → Deferred.succeed() → ctx.ask() 返回
        ↓
    bash.ts 继续执行 → 返回结果给 AI SDK
        ↓
    AI SDK 把结果塞给 LLM → LLM 继续输出
        ↓
    最终返回给用户
```

**关键代码**：
- `tool/tool.ts` - Tool 接口定义
- `tool/registry.ts` - 工具注册中心
- `tool/bash.ts` - Bash 工具实现（命令白名单、权限请求、子进程执行）
- `session/prompt.ts:450` - execute 包装函数
- `session/prompt.ts:426-438` - ctx.ask 的创建

---

### 11.4 BashTool 实现详解

**核心流程**（`tool/bash.ts:483-528`）：
```typescript
async execute(params, ctx) {
  // 1. 解析路径
  const cwd = params.workdir ? await resolvePath(...) : Instance.directory
  
  // 2. 用 tree-sitter 解析命令成 AST
  const root = await parse(params.command, ps)
  
  // 3. collect 函数分析 AST，收集外部目录和命令模式
  const scan = await collect(root, cwd, ps, shell)
  
  // 4. ctx.ask() 请求权限（阻塞等待用户确认）
  await ask(ctx, scan)
  
  // 5. run() 执行命令
  return run({ shell, command, cwd, env, timeout }, ctx)
}
```

**命令白名单**（`tool/bash.ts:32-53`）：
```typescript
const FILES = new Set([
  ...CWD,  // cd, push-location, set-location
  "rm", "cp", "mv", "mkdir", "touch", "chmod", "chown", "cat",
  "get-content", "set-content", "copy-item", "move-item", ...
])
// 只有在白名单里的命令才会被当作文件操作处理
```

**权限请求**（`tool/bash.ts:271-292`）：
- `scan.dirs`：需要 external_directory 权限的目录
- `scan.patterns`：需要 bash 权限的命令模式

**tree-sitter 解析**：
- 把命令字符串解析成 AST（抽象语法树）
- `descendantsOfType("command")` 找出所有命令节点
- `collect()` 遍历 AST，收集需要权限的资源

**ctx.ask() 机制**：
- `ctx.ask()` 是在 `session/prompt.ts:426` 创建的
- 底层调用 `permission.ask()`
- `permission.ask()` 创建 Deferred + 发布 Event.Asked 事件
- 前端弹窗，用户点击后调用 `permission.reply()`
- `Deferred.succeed()` 唤醒等待者

**ctx.metadata() 机制**：
- 更新工具的 UI 状态（进度、输出）
- 非阻塞，随时可以调用

**关键代码**：
- `tool/bash.ts:32-53` - 命令白名单
- `tool/bash.ts:229-258` - collect 函数
- `tool/bash.ts:271-292` - ask 函数
- `tool/bash.ts:321-422` - run 函数（子进程执行）
- `permission/index.ts:168` - permission.ask 实现

---

### 11.5 while true 循环控制

**循环控制逻辑**：
- `while true` 控制"一次用户消息里需要处理多少轮工具调用"
- 每次用户发消息都会创建新的 `prompt()` → `runLoop()`
- 一次 `handle.process()` = 一次完整 LLM 请求
- 返回值：`continue`（没说停）、`stop`（说停）、`compact`（上下文太长）

**关键代码**：
- `session/prompt.ts:1388` - `runLoop()` 循环
- `session/prompt.ts:1593` - 判断 result 决定 break/continue
- `session/processor.ts:545-550` - handle.process 返回值

---

### 11.6 权限与安全

**多层防御**：
1. **命令白名单**：只允许特定命令（rm、cp、mv、cat 等）
2. **路径过滤**：检查文件是否在允许目录
3. **动态权限请求**：执行前调用 `ctx.ask()` 询问用户
4. **Agent 级别配置**：不同 Agent 有不同权限（build 全权限、plan 禁用 edit 等）

**Deferred 机制（等待用户回复）**：
- `permission.ask()` 创建 Deferred（类似 Java CompletableFuture）
- 发布 Event.Asked 事件给前端
- `Deferred.await()` 阻塞等待
- 前端弹窗，用户点击后调用 `permission.reply()`
- `Deferred.succeed()` 或 `Deferred.fail()` 唤醒等待者

**关键代码**：
- `tool/bash.ts:32-55` - 命令白名单
- `permission/index.ts:168` - permission.ask 实现
- `permission/index.ts:205` - permission.reply 实现
- `agent/agent.ts` - Agent 权限配置

### 11.6.1 完整调用链架构图（✨新增）

**一句话概括**：
> 用户发消息 → prompt() → runLoop() → while true { resolveTools() → handle.process() → llm.stream() → AI SDK 执行工具 }

**完整架构图**：
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              用户发起对话                                     │
│                          "帮我读取 D:/study/README.md"                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  session/prompt.ts:1356  prompt()                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. createUserMessage() → 创建用户消息                                │    │
│  │  2. session.appendMessage() → 保存到数据库                            │    │
│  │  3. runLoop() → 启动 while true 循环                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  session/prompt.ts:1388  runLoop()  ← while true                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │   ┌────────────────────────────────────────────────────────────┐   │    │
│  │   │  第 N 次循环                                                 │   │    │
│  │   │                                                            │   │    │
│  │   │   resolveTools()  ──────────────────────────────────┐     │   │    │
│  │   │        │                                        │     │   │    │
│  │   │        ▼                                        │     │   │    │
│  │   │   registry.tools()                              │     │   │    │
│  │   │        │                                        │     │   │    │
│  │   │        ▼                                        │     │   │    │
│  │   │   Tool.Def 列表  ───────────────────────────────│     │   │    │
│  │   │                                                │     │   │    │
│  │   │                                                ▼     │   │    │
│  │   │   handle.process({ tools, messages })           │     │   │    │
│  │   │        │                                        │     │   │    │
│  │   │        │  tools 参数格式：                       │     │   │    │
│  │   │        │  { name: tool({ execute: async() {} }) }│     │   │    │
│  │   │        ▼                                        │     │   │    │
│  │   │   llm.stream(streamInput)                       │     │   │    │
│  │   │        │                                        │     │   │    │
│  │   │        │  AI SDK 内部执行 ReAct 循环             │     │   │    │
│  │   │        │  ┌───────────────────────────────┐    │     │   │    │
│  │   │        │  │ LLM 说："我要调用 bash"        │    │     │   │    │
│  │   │        │  │ AI SDK 执行 bash.execute()    │    │     │   │    │
│  │   │        │  │ 执行结果塞回给 LLM            │    │     │   │    │
│  │   │        │  └───────────────────────────────┘    │     │   │    │
│  │   │        │                                        │     │   │    │
│  │   │        ▼                                        │     │   │    │
│  │   │   返回: "continue" | "stop" | "compact"        │     │   │    │
│  │   │                                            ▲     │   │    │
│  │   │   ┌────────────────────────────────────────┘     │   │    │
│  │   │   │  evaluate result:                            │   │    │
│  │   │   │  if "continue" → 继续 while true            │   │    │
│  │   │   │  if "stop" → break 退出循环                  │   │    │
│  │   │   │  if "compact" → 压缩上下文后 continue        │   │    │
│  │   │   └─────────────────────────────────────────────┘   │    │
│  │   └────────────────────────────────────────────────────────────┘   │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼ (工具执行时)
┌─────────────────────────────────────────────────────────────────────────────┐
│  tool/bash.ts:483  execute()                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. parse(command) → tree-sitter 解析成 AST                         │    │
│  │  2. collect(root) → 遍历 AST，收集要访问的目录和命令                  │    │
│  │  3. ask(ctx, scan) → 请求权限                                       │    │
│  │  4. run() → 执行命令                                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**权限请求详细流程**：
```
tool/bash.ts:271  ask()
    │
    ▼
session/prompt.ts:426  ctx.ask = permission.ask()
    │
    ▼
permission/index.ts:168  Permission.ask()
    │
    ├─ evaluate() 遍历 patterns，匹配规则
    │    │
    │    ├─ rule.action === "deny" → 直接返回 DeniedError
    │    ├─ rule.action === "allow" → 继续下一个 pattern
    │    └─ rule.action === "ask" → 标记 needsAsk = true
    │
    ├─ 所有都是 allow？ → 直接返回（不弹窗）
    │
    └─ 有 ask？ → 创建 Deferred + 发布 Event.Asked + 阻塞等待
         │
         ▼
    Bus.publish(Event.Asked, info)  ──→ 前端弹窗
         │
    Deferred.await(deferred)  ◄────────────────────┘
         │
         ▼ (用户点击后)
permission.reply()
    │
    ├─ "reject" → Deferred.fail(RejectedError)
    └─ "once"/"always" → Deferred.succeed() + 可选加入 approved
```

**Agent 权限配置关系**（`agent.ts:94-111`）：
```
build Agent 默认规则：
┌─────────────────────────────────────────────────────────────────────┐
│  { "*": "allow" }                    // 大部分权限默认 allow           │
│                                                                      │
│  external_directory: {                // 访问项目外目录                │
│    "*": "ask",                       //   默认询问                    │
│    "~/.opencode/*": "allow",         //   白名单 allow                │
│  },                                                                       │
│                                                                      │
│  read: {                               // 读取文件                    │
│    "*": "allow",                      //   默认 allow                 │
│    "*.env": "ask",                    //   .env 要询问                │
│  },                                                                       │
└─────────────────────────────────────────────────────────────────────┘

evaluate() 匹配规则：
- findLast() 从后往前找最后一个匹配的规则（后面的覆盖前面的）
- 默认 action 是 "ask"
```

### 11.6.2 Bus 与 Deferred 机制（✨新增）

**Bus（事件总线）**：
- 发布-订阅模式，用于后端和前端通信
- `Bus.publish(Event.Asked, info)` → 前端订阅后弹窗
- `Bus.subscribe(Permission.Event.Asked, callback)` → 前端监听事件
- `GlobalBus.emit()` → 跨实例广播（用于 TUI 或前端跨标签页）

**Deferred（延迟结果）**：
- 类似 Java 的 `CompletableFuture`，用于 Effect 框架
- `Deferred.make()` → 创建
- `Deferred.await(deferred)` → 阻塞等待
- `Deferred.succeed(deferred, value)` → 成功唤醒
- `Deferred.fail(deferred, error)` → 失败唤醒

**完整串起来**：
```
用户执行 cat D:/study/README.md
    │
    ▼
BashTool.execute()
    │
    ▼
ctx.ask({ permission: "external_directory", patterns: ["D:/study/*"] })
    │
    ▼
permission.ask()
    │
    ├─ evaluate() → 匹配到 "ask"
    │
    ├─ Deferred.make() → 创建 deferred
    │
    ├─ pending.set(id, { deferred }) → 存入 Map
    │
    ├─ Bus.publish(Event.Asked, info) → 发布事件
    │      │
    │      ▼
    │   前端收到事件 → 弹窗
    │      │
    │   用户点击"Allow Once"
    │      │
    │   Permission.reply({ reply: "once" })
    │      │
    ├─ Deferred.await(deferred) ← 阻塞等待...
    │      │
    │      ◄──────────────────────
    │      │ (用户点击后唤醒)
    │
    └─ 继续执行命令
```

**关键代码**：
- `bus/index.ts:83-98` - Bus.publish 实现
- `bus/index.ts:149-156` - Bus.subscribeCallback 实现
- `permission/index.ts:194` - Deferred.make 创建
- `permission/index.ts:198` - Deferred.await 阻塞
- `permission/index.ts:236` - Deferred.succeed 唤醒
- `permission/index.ts:218` - Deferred.fail 唤醒（拒绝）

### 11.6.3 流式输出与前端交互（✨新增）

**问题**：后端的事件怎么传到前端 UI 的？

**架构图**：
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              后端 OpenCode                                   │
│                                                                             │
│  AI SDK fullStream 事件 ──► handleEvent() ──► Bus.publish() ──► SSE /event  │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  事件类型：text-delta、tool-input-start、tool-input-delta、tool-call、│    │
│  │          tool-result、finish 等                                       │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼ (SSE: text/event-stream)
┌─────────────────────────────────────────────────────────────────────────────┐
│                              前端 (你当前用的 GUI)                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  global-sdk.tsx:139-154                                              │    │
│  │  const events = await eventSdk.global.event({...})                  │    │
│  │  for await (const event of events.stream) {                         │    │
│  │    emitter.emit(event.directory, event.payload)  // 发射给 UI        │    │
│  │  }                                                                   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  event-reducer.ts 根据事件类型更新 UI 状态：                                  │
│  ├── permission.asked ──► 显示权限弹窗                                      │
│  ├── message.part.updated ──► 显示 AI 回复内容                              │
│  └── tool-result ──► 显示工具执行结果                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**AI SDK fullStream 事件类型**：

| 事件类型 | 什么时候触发 | 携带什么数据 |
|---------|------------|-------------|
| `start` | 开始生成 | 无 |
| `text-delta` | 输出文本增量 | `text: "你"` |
| `reasoning-start/delta/end` | AI 思考过程 | `id`, `text` |
| `tool-input-start` | 工具参数开始 | `id`, `toolName` |
| `tool-input-delta` | 工具参数增量 | `id`, `delta: "cat D:/s"` |
| `tool-input-end` | 工具参数结束 | `id` |
| `tool-call` | 触发工具调用 | `toolCallId`, `toolName`, `input` |
| `tool-result` | 工具执行完成 | `toolCallId`, `output` |
| `tool-error` | 工具执行失败 | `toolCallId`, `error` |
| `finish` | 全部完成 | 无 |

**示例：用户说 "帮我读取 D:/study/README.md"**

```json
{"type": "start"}
{"type": "text-delta", "text": "好的"}
{"type": "text-delta", "text": "，我来帮你读取这个文件"}
{"type": "tool-input-start", "id": "tool_001", "toolName": "read"}
{"type": "tool-input-delta", "id": "tool_001", "delta": "{"}
{"type": "tool-input-delta", "id": "tool_001", "delta": '"filePath":'}
{"type": "tool-input-delta", "id": "tool_001", "delta": " "}
{"type": "tool-input-delta", "id": "tool_001", "delta": '"D:/study/README.md"'}
{"type": "tool-input-delta", "id": "tool_001", "delta": "}"}
{"type": "tool-input-end", "id": "tool_001"}
{"type": "tool-call", "toolCallId": "tool_001", "toolName": "read", "input": {"filePath": "D:/study/README.md"}}
{"type": "tool-result", "toolCallId": "tool_001", "output": {"output": "<path>D:/study/README.md</path>\n<type>file</type>\n<content>\n1: # 学习笔记\n2: ...\n</content>", "title": "README.md"}}
{"type": "text-delta", "text": "\n文件已读取成功"}
{"type": "finish"}
```

**tool-input-delta 的意义**：
- LLM 一个字一个字生成，工具参数也是慢慢拼接的
- `tool-input-delta` 把拼接过程实时告诉前端，用户可以看到 AI 正在输入什么命令

**项目结构**：
```
packages/
├── opencode/          # 后端 Agent（你学的主要内容）
│   ├── session/
│   │   ├── processor.ts    # handleEvent 处理事件
│   │   └── llm.ts          # AI SDK streamText()
│   ├── bus/               # 事件总线
│   ├── permission/        # 权限系统
│   └── server/routes/
│       └── event.ts       # SSE /event 端点
│
├── app/               # Web 前端（packages/app 是 web 版本）
│   └── src/
│       ├── context/
│       │   ├── global-sdk.tsx     # 连接 /event，接收事件
│       │   └── global-sync/
│       │       └── event-reducer.ts  # 根据事件更新 UI
│       └── pages/
│
└── desktop/           # Desktop 前端（Tauri/Electron）
    └── src-tauri/     # Rust 后端
```

**关键代码**：
- `session/processor.ts:129` - handleEvent 处理每个事件
- `session/processor.ts:171-184` - tool-input-start 处理
- `session/processor.ts:186-191` - tool-input-delta 处理
- `session/processor.ts:240-259` - tool-result 处理
- `server/routes/event.ts:92` - Bus.subscribeAll() 发布 SSE
- `global-sdk.tsx:139-154` - 前端连接 SSE 接收事件

### 11.6.4 MessageV2 数据结构（✨新增）

**用户消息 User**：
```typescript
MessageV2.User {
  id, sessionID,
  role: "user",
  time: { created },
  tools: { "bash": true, "edit": false },  // 用户强制工具开关（一般不用）
  format: { type: "text" | "json_schema" },
  summary: { title, body, diffs },  // 压缩后的摘要
  agent: "build",
  model: { providerID, modelID },
  system: "...",  // 系统提示词
  variant: "..."
}
```

**助手消息 Assistant**：
```typescript
MessageV2.Assistant {
  id, sessionID,
  role: "assistant",
  parentID: lastUser.id,  // 关联用户消息
  time: { created, completed },
  mode: "build",
  agent: "build",
  finish: "stop" | "tool-calls" | "error",
  tokens: { input, output, reasoning, cache },
  parts: [  // 消息片段
    TextPart,           // 普通文本
    ReasoningPart,      // AI 思考
    ToolPart,           // 工具调用
    ToolDeltaPart,      // 工具参数流式
    StepStartPart,      // 步骤开始
    StepFinishPart,     // 步骤完成
    CompactionPart,     // 压缩标记
    SnapshotPart,       // 文件快照
    RetryPart,          // 重试记录
  ]
}
```

**Part 类型汇总**：

| Part 类型 | 作用 | 关键字段 |
|-----------|------|---------|
| `TextPart` | 普通文本回复 | `text` |
| `ReasoningPart` | AI 思考过程 | `text` |
| `ToolPart` | 工具调用 | `tool`, `callID`, `state` |
| `ToolDeltaPart` | 工具参数流式（GUI用） | 同 ToolPart，type 不同 |
| `StepStartPart` | 循环步骤开始 | `snapshot` |
| `StepFinishPart` | 循环步骤完成 | `reason`, `cost`, `tokens` |
| `CompactionPart` | 压缩标记 | `auto`, `overflow` |
| `SnapshotPart` | 文件快照 | `snapshot` |
| `RetryPart` | 重试记录 | `attempt`, `error` |

---

### 11.6.5 resolveTools 精讲（✨新增）

**作用**：把 OpenCode 工具转换成 AI SDK 认识的格式

**调用位置**：`session/prompt.ts:1511`

**代码流程**：
```typescript
const resolveTools = Effect.fn("SessionPrompt.resolveTools")(function* (input) {
  const tools: Record<string, AITool> = {}

  // 1. 创建 context 函数（工具执行时的上下文）
  const context = (args, options): Tool.Context => ({
    sessionID: input.session.id,
    callID: options.toolCallId,
    agent: input.agent.name,
    messages: input.messages,
    ask: (req) => permission.ask(...),  // 权限请求
    metadata: (val) => ...               // 更新 UI
  })

  // 2. 处理内置工具
  for (const item of yield* registry.tools(model, agent)) {
    const schema = ProviderTransform.schema(model, z.toJSONSchema(item.parameters))
    tools[item.id] = tool({
      id: item.id,
      description: item.description,
      inputSchema: jsonSchema(schema),
      execute(args, options) {
        const ctx = context(args, options)
        yield* plugin.trigger("tool.execute.before")
        const result = yield* item.execute(args, ctx)  // 调用原工具
        yield* plugin.trigger("tool.execute.after")
        return output
      }
    })
  }

  // 3. 处理 MCP 工具（外部工具）
  for (const [key, item] of Object.entries(yield* mcp.tools())) {
    // 类似上面，但增加 ctx.ask()
  }

  return tools
})
```

**关键点**：
- `tools` 参数只是历史遗留，实际没用到
- Agent 参数传给 `tool.init({ agent })`，工具可以根据 agent 调整行为
- 插件可以通过 `tool.definition` hook 修改工具定义

**执行时机**：
```
用户发消息
    │
    ▼
resolveTools() → 获取 { bash: tool, read: tool, ... }
    │
    ▼
handle.process({ tools }) → 传给 AI SDK
```

---

### 11.6.6 ToolRegistry.tools（✨新增）

**作用**：获取所有已注册的工具

**工具来源**：
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        工具来源                                              │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │  1. 内置工具      │  bash, read, edit, glob, grep, task, todo, ...       │
│  │  (hardcoded)     │  registry.ts:139-156                                  │
│  └──────────────────┘                                                       │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │  2. 自定义工具    │  {cwd}/tool/*.{js,ts} 目录下                           │
│  │  (fromPlugin)    │  registry.ts:113-126                                  │
│  └──────────────────┘                                                       │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │  3. 插件工具      │  plugin.list() → p.tool                              │
│  │  (from plugin)   │  registry.ts:128-133                                  │
│  └──────────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

**tools() 方法流程**：
```typescript
const tools = Effect.fn("ToolRegistry.tools")(function* (model, agent) {
  // 1. 获取所有工具
  const allTools = yield* all(s.custom)

  // 2. 根据 model 过滤
  const filtered = allTools.filter((tool) => {
    if (tool.id === "codesearch" || tool.id === "websearch") {
      return model.providerID === ProviderID.opencode || Flag.OPENCODE_ENABLE_EXA
    }
    // edit/write 和 apply_patch 互斥
    if (tool.id === "apply_patch") return usePatch
    if (tool.id === "edit" || tool.id === "write") return !usePatch
    return true
  })

  // 3. 初始化每个工具
  return yield* Effect.forEach(filtered, (tool) => {
    const next = yield* tool.init({ agent })  // 关键：传入 agent
    yield* plugin.trigger("tool.definition", { toolID: tool.id, agent }, output)
    return globalExtensionRegistry.transformToolDef(toolDef)
  })
})
```

**Agent 和 Tool 的关系**：
- Agent 不直接包含工具列表
- Agent 只包含**权限规则**（决定哪些操作需要询问/拒绝）
- 工具统一从 registry 获取，agent 参数只是传入用来做**过滤/扩展**

**关键代码**：
- `tool/registry.ts:139-156` - 内置工具列表
- `tool/registry.ts:191-238` - tools() 方法实现
- `tool/registry.ts:441-479` - resolveTools 中调用

---

### 11.7 上下文压缩（Compaction）（✨整合）

**问题**：对话历史越来越长，token 超过 LLM 限制怎么办？

**解决方案**：两种策略结合
1. **compaction.create**：生成 summary，把多条消息合成一条
2. **compaction.prune**：剪枝旧的 tool 输出，释放空间

---

#### 11.7.1 compaction.create（生成摘要）

**触发条件**：
- `isOverflow()` = 当前 token >= (限制 - 预留空间)
- 每次用户发消息后检查
- 在 `prompt.ts:1466`：`yield* compaction.isOverflow({ tokens: lastFinished.tokens, model })`

**压缩流程**（`compaction.ts:141-283`）：
```
1. 找到用户消息（userMessage）作为锚点
2. 创建空的 assistant 消息（msg，summary: true）
3. yield* session.updateMessage(msg)  // 先保存到数据库（空的）
4. 把 msg 传给 processor（同一引用）
5. 调用 LLM 生成 summary（tools: {}，不带工具）
6. LLM 生成的内容直接写入 msg（handleEvent 实时更新）
7. process 结束后 yield* session.updateMessage(msg)  // 保存有内容的消息
8. 返回 continue，继续正常对话
```

**Summary 模板**：
```markdown
## Goal
[用户想完成什么目标]

## Instructions
[重要指令]

## Discoveries
[发现了什么]

## Accomplished
[完成了什么]

## Relevant files
[相关文件列表]
```

---

#### 11.7.2 compaction.prune（剪枝旧输出）

**作用**：释放上下文空间，删除旧的 tool 输出但保留最近的关键结果

**代码逻辑**（`compaction.ts:93-139`）：
```typescript
const prune = Effect.fn("SessionCompaction.prune")(function* (input) {
  // 从最新消息往前遍历
  for (msgIndex from msgs.length-1 to 0) {
    turns++  // 遇到 user 消息就计数
    if (turns < 2) continue  // 保留最近 2 轮对话的所有 tool 输出
    
    for (partIndex from msg.parts.length-1 to 0) {
      if (part.type === "tool" && part.state.status === "completed") {
        if (PRUNE_PROTECTED_TOOLS.includes(part.tool)) continue  // 某些工具不删除
        if (part.state.time.compacted) break  // 已经压缩过的就停止
        
        total += estimate  // 累加 token
        if (total > PRUNE_PROTECT) {
          toPrune.push(part)  // 需要删除的
        }
      }
    }
  }
  
  // 标记为已压缩
  for (const part of toPrune) {
    part.state.time.compacted = Date.now()  // 标记时间戳
    yield* session.updatePart(part)
  }
})
```

**关键常量**：
- `PRUNE_PROTECT`: 保留最近多少 token 的 tool 输出
- `PRUNE_PROTECTED_TOOLS`: 不压缩的工具（如 search、grep）
- `PRUNE_MINIMUM`: 超过多少才压缩

**调用位置**：`prompt.ts:1614`（后台异步执行）
```typescript
yield* compaction.prune({ sessionID }).pipe(Effect.ignore, Effect.forkIn(scope))
```

---

#### 11.7.3 isOverflow() 实现

```typescript
const count = tokens.total  // 当前 token 数
const reserved = 20000  // 预留空间
const usable = context - reserved  // 可用空间
return count >= usable  // 超限就触发
```

**关键代码**：
- `session/overflow.ts` - isOverflow 判断
- `session/compaction.ts:93` - prune 函数
- `session/compaction.ts:141` - processCompaction 函数
- `session/compaction.ts:189-217` - Summary 模板
- `session/compaction.ts:349` - compaction.create
- `prompt.ts:1466` - 触发检查
- `prompt.ts:1614` - prune 调用

**面试怎么说**：
> "我研究过 OpenCode 的上下文压缩机制。当对话历史超过 token 限制时，系统会自动触发压缩：找到用户消息作为锚点，创建一个空的 summary 消息，然后调用 LLM 生成压缩摘要。同时通过 prune 剪枝旧的 tool 输出，只保留最近 2 轮对话和关键工具的结果。"

---

### 11.8 Plugin 系统（✨新增）

**是什么**：扩展点机制，允许在特定时机插入自定义逻辑，不改源码

**本质**：事件总线模式（不是 AOP）
- AOP：切入点在注解/配置，框架自动拦截
- Plugin：切入点硬编码在业务代码里，手动 trigger 触发
- 一个切入点可以挂多个插件

**核心概念**：

| 概念 | 说明 | Java 类比 |
|------|------|-----------|
| Plugin | 返回 hooks 对象的函数 | 切面类 |
| Hooks | `{ "扩展点名": fn }` 对象 | 切面方法 |
| hooks 数组 | 存所有 Plugin 返回的 hooks | 切面列表 |
| trigger | 遍历 hooks 数组，找对应 key 执行 | 代理调用 |

**常用扩展点**：

| 扩展点 | 时机 | input | output |
|--------|------|-------|--------|
| `tool.execute.before` | 工具执行前 | `{ tool, sessionID, callID, args }` | `{ args }` |
| `tool.execute.after` | 工具执行后 | `{ tool, sessionID, callID, args }` | `{ output, title, metadata }` |
| `tool.definition` | 工具定义时 | `{ toolID, agent }` | `{ description, parameters }` |
| `experimental.chat.messages.transform` | 消息转换时 | `{}` | `{ messages }` |
| `event` | Bus 事件 | `{ event }` | - |

**完整链路**：

```
1. 插件定义：Plugin 函数返回 hooks 对象
   ┌──────────────┐    返回     ┌─────────────────────────────────┐
   │  Plugin1     │ ────────→  │ { "tool.execute.before": fn1 }  │ ──→ hooks[0]
   │  (计时插件)   │            └─────────────────────────────────┘
   └──────────────┘

   ┌──────────────┐    返回     ┌──────────────────────────────────────┐
   │  Plugin2     │ ────────→  │ { "tool.execute.before": fn2,        │ ──→ hooks[1]
   │  (日志插件)   │            │   "tool.execute.after": fn3 }        │
   └──────────────┘            └──────────────────────────────────────┘

2. 插件注册：INTERNAL_PLUGINS 数组（plugin/index.ts:71-91）
   const INTERNAL_PLUGINS = [Plugin1, Plugin2, HelloPlugin, ...]

3. 插件初始化：启动时遍历，调用 plugin(input)，返回 hooks 存入数组（plugin/index.ts:170-182）
   for (const plugin of INTERNAL_PLUGINS) {
     hooks.push(await plugin(input))
   }

4. 触发扩展点：业务代码手动调用（prompt.ts:454, 469）
   plugin.trigger("tool.execute.before", input, output)
     ↓
   遍历 hooks 数组：
     hooks[0]["tool.execute.before"] → fn1 ✅ 执行
     hooks[1]["tool.execute.before"] → fn2 ✅ 执行
     hooks[2]["tool.execute.before"] → undefined ❌ 跳过
     ↓
   返回 output（可能被插件修改）
```

**实际插件示例**（HelloPlugin）：
```typescript
// custom-hw/plugin/hello-plugin-cac.ts
import type { Plugin } from "@opencode-ai/plugin"

export const HelloPlugin: Plugin = async ({ client }) => {
  const log = (message: string, data?: any) => {
    client.app.log({
      body: { service: "hello-plugin", level: "info", message, ...data },
    })
  }

  return {
    "tool.execute.before": async (input, output) => {
      log(`[Hello] 工具即将执行: ${input.tool}`)
    },
    "tool.execute.after": async (input, output) => {
      log(`[Hello] 工具执行完成: ${input.tool}`)
    },
  }
}
```

**注册方式**：
1. import: `import { HelloPlugin } from "../custom-hw/plugin/hello-plugin-cac"`
2. 加入 INTERNAL_PLUGINS 数组: `[..., HelloPlugin]`

**关键代码**：
- `plugin/index.ts:71-91` - INTERNAL_PLUGINS 插件列表
- `plugin/index.ts:170-182` - 插件初始化（调用 plugin(input)）
- `plugin/index.ts:280-293` - trigger 实现（遍历 hooks 执行）
- `session/prompt.ts:454` - tool.execute.before 触发
- `session/prompt.ts:469` - tool.execute.after 触发
- `tool/registry.ts:222` - tool.definition 触发
- `session/prompt.ts:1550` - messages.transform 触发
- `custom-hw/plugin/hello-plugin-cac.ts` - 自己写的插件示例

---

### 11.8.1 Provider 模块精讲（✨新增）

**一句话概括**：
> Provider 模块就是 Agent 和 LLM 之间的"数据源选择器"，负责：从哪找模型、怎么连模型、怎么适配模型。

**三层核心逻辑**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    1. 从哪找模型（初始化 6 步）                               │
│                                                                             │
│   ModelsDev 数据库 → config 合并 → env 检测 → auth 读取                    │
│       → custom() 后处理 → filter 过滤                                       │
│                                                                             │
│   优先级：database → config → env → auth → custom → filter                 │
│   类比：Spring PropertySource 优先级链                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    2. 怎么连模型（resolveSDK）                                │
│                                                                             │
│   合并 options → URL ${VAR} 替换 → Hash 缓存 key                           │
│       → 包装自定义 fetch（超时、SSE 检测）                                   │
│       → BUNDLED_PROVIDERS 内置优先？或动态 npm install + import             │
│                                                                             │
│   getLanguage() 调用链：                                                     │
│   Model → resolveSDK → SDK 客户端                                           │
│       → modelLoaders[providerID] 自定义 getModel？                          │
│       → 否则 sdk.languageModel(model.api.id)                                │
│       → 缓存到 Map<string, LanguageModelV3>                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    3. 怎么适配模型（ProviderTransform）                       │
│                                                                             │
│   normalizeMessages()  → 消息格式适配（空content、toolCallId等）            │
│   applyCaching()       → 缓存标记（Anthropic/OpenRouter/Bedrock 各不同）    │
│   unsupportedParts()   → 不支持的附件类型转文本                             │
│   variants()           → 思考级别（每个 Provider 参数格式不同）              │
│   temperature()        → 不同模型默认温度                                   │
│   options()            → Provider 特殊选项                                  │
│   schema()             → Gemini 不接受 integer 枚举                         │
│   providerOptions()    → 选项映射到正确的 SDK 命名空间                      │
│                                                                             │
│   类比：DatabaseDialect，不同数据库的 SQL 方言翻译层                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

**custom() 后处理器典型例子**：

| Provider | 定制行为 | 类比 |
|----------|---------|------|
| anthropic | 添加 `anthropic-beta` 请求头 | MySQL 的 charset 配置 |
| openai | 用 `sdk.responses()` 而非 `sdk.languageModel()` | PostgreSQL 的 SSL 模式选择 |
| amazon-bedrock | 根据 region 自动加前缀，AWS 凭证链 | Oracle 的 TNS 配置 |
| gitlab | 运行时动态发现工作流模型 | 动态数据源路由 |
| azure | 根据配置选 responses 或 chat API | SQL Server 的连接方式选择 |

**面试怎么说**：
> "我深入研究了 OpenCode 的 Provider 模块。它用 6 步初始化链加载模型数据库，优先级是 database → config → env → auth → custom → filter。每个 Provider 有自己的后处理器（custom 函数），类似 BeanPostProcessor。连接模型时用 resolveSDK 创建 SDK 客户端，内置 20+ SDK 优先，动态 npm install 兜底。最有趣的是 ProviderTransform，它是个消息适配层，类似数据库的 Dialect，处理不同 LLM 的'怪癖'——比如 Anthropic 不接受空 content、Claude 的 toolCallId 只能含字母数字、Mistral 的 toolId 限 9 个字符。"

**关键代码**：
- `provider/provider.ts:1014-1339` - 初始化 6 步
- `provider/provider.ts:175-820` - custom() 后处理器
- `provider/provider.ts:1344-1479` - resolveSDK
- `provider/provider.ts:1503-1544` - getLanguage
- `provider/transform.ts` - 全部消息适配逻辑
- `provider/schema.ts` - Brand Type 定义

---

### 11.9 面试一句话概括

```
我深入理解了 AI Agent 的核心实现：
- 用 AI SDK 实现 ReAct 循环（一次请求多次工具调用）
- 事件驱动的架构（handleEvent 处理流式事件）
- 可扩展的工具系统（定义→注册→包装）
- 深度防御的安全机制（白名单+权限请求+Agent配置）
```

---

### 11.9 面试加分项

| 知识点 | 加分原因 |
|--------|----------|
| AI SDK 控制循环 vs 自己控制循环 | 理解现代 Agent 架构 |
| 事件流处理（text-delta、tool-call、tool-result） | 理解流式输出原理 |
| 插件扩展点设计（before/after） | 理解可扩展架构 |
| 多层防御安全（白名单+权限请求+Agent配置） | 理解企业级安全设计 |
| Effect 框架（依赖注入、服务层） | 理解函数式编程在 AI 的应用 |
| 上下文压缩机制（Compaction） | 理解长对话管理和 Token 限制 |
| isOverflow 判断（预留空间、可用空间） | 理解资源管理和性能优化 |

---

## 十二、Java 专家学习对照表（原有）

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
| 插件扩展点 | AOP 切面 / Filter 链 | 拦截增强 | 插件注册而非硬编码 |
| 工具包装层 | 装饰器模式 | 层层包装 | 不改原工具，增加功能 |
| Provider 初始化 | PropertySource 优先级链 | 多源合并 | 6步链式加载，后者覆盖前者 |
| custom() 后处理 | BeanPostProcessor | 初始化后定制 | 每个 Provider 有自己的定制逻辑 |
| resolveSDK | DataSource.getConnection() | 客户端创建 | Hash 缓存 + 动态 npm install |
| ProviderTransform | DatabaseDialect | 方言适配 | 不同 LLM 的消息格式翻译 |
| ProviderID/ModelID Brand Type | 自定义强类型字符串 | 编译时类型安全 | Effect Schema Brand 实现 |

*我的补充与理解：*

---

## 十三、常用工具与资源速查

- 模型：CodeQwen、DeepSeek-Coder、Starcoder2
- 推理：Ollama、vLLM、llama.cpp
- 向量库：Chroma、FAISS、Qdrant
- 嵌入模型：BGE、CodeBERT、text-embedding-3-small
- LSP：pygls、bash-language-server、typescript-language-server
- 安全：Presidio、Bandit
- 框架参考：Open Interpreter、Aider、Continue、LangChain（源码阅读清单）
- *我的收藏：*
