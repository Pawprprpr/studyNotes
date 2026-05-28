RAG（检索增强生成）
├── 什么是RAG
│   └── 用户问题 → Embedding → 向量检索 → 召回文档 → 拼接Prompt → LLM生成
│
├── 文档入库流程
│   ├── 上传文件 (_save_files_in_thread)
│   ├── 加载文档 (KnowledgeFile.file2docs → Loader)
│   ├── 文本切分 (docs2texts → RecursiveCharacterTextSplitter)
│   ├── 向量化 (embed_documents)
│   └── 存入向量库 (add_embeddings → FAISS)
│
├── 向量数据库
│   ├── Embedding原理
│   │   └── 文本 → 向量（Transformer模型，1536维）
│   ├── 相似度计算
│   │   └── 余弦相似度 = A·B / (||A|| × ||B||)
│   └── FAISS索引类型
│       ├── Flat（暴力搜索，精确）
│       ├── IVF（聚类后搜索）
│       └── HNSW（图索引，高速）
│
├── LangChain核心概念
│   ├── Chain (prompt | llm)
│   ├── Callback（流式输出）
│   └── Agent（ReAct循环）
│       └── Think → Act → Observe → Loop → Finish
│
└── FastAPI基础
    ├── 路由 @app.get/post
    ├── 参数接收 Body/Query/Path
    ├── Pydantic Model（数据校验）
    ├── 依赖注入 Depends()
    ├── 异步 async/await
    └── 流式响应 EventSourceResponse(SSE)


    RAG进阶
├── ReRanker（重排序，二次筛选）
├── 混合检索（向量+关键词BM25）
└── LLM基础理论（Transformer/Attention）
