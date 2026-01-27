📌 一句话记住
ConfigMap = K8s的配置文件中心，把配置和镜像分开。


# 命令速查链接
https://chat.deepseek.com/share/a858yzq0gkd077c0po

🔧 创建ConfigMap（3种方式，记前2种）
bash
# 1. 从键值对（简单配置）
kubectl create configmap app-config --from-literal=env=prod

# 2. 从文件（推荐，Java配置文件）
kubectl create configmap app-config --from-file=application.yml
🚀 在Deployment中使用（2种方式）
方式1：环境变量（连接信息用）
yaml
env:
- name: DB_URL
  valueFrom:
    configMapKeyRef:
      name: app-config      # ConfigMap名字
      key: db.url           # 里面的key
方式2：文件挂载（配置文件用，最常用）
yaml
# 关键对应关系：
# volumeMounts.name = volumes.name
# volumes.configMap.name = ConfigMap名字

containers:
- volumeMounts:
  - name: config          # 挂载点名
    mountPath: /app/config  # 挂哪里
    
volumes:
- name: config            # 同上
  configMap:
    name: app-config      # ConfigMap名字
🔄 更新机制（面试常问）
文件挂载：改ConfigMap → 自动更新文件（Java应用可能需要重启）

环境变量：改ConfigMap → 必须重启Pod才生效

生产建议：改配置后都重启一下

bash
kubectl rollout restart deployment <应用名>
💡 Java应用最佳实践
yaml
# Spring Boot应用配置
containers:
- name: spring-app
  # 1. 配置文件挂载
  volumeMounts:
  - name: config
    mountPath: /app/config
  
  # 2. 告诉Spring去哪读
  command: ["java", "-jar", "app.jar",
           "--spring.config.location=file:/app/config/application.yml"]
  
volumes:
- name: config
  configMap:
    name: spring-config
⚠️ 注意点
大小限制：1MB，别放大文件

敏感数据：密码、token用Secret，别用ConfigMap

多环境：创建不同ConfigMap（dev-config、prod-config）

🛠️ 常用命令
bash
# 查看
kubectl get cm
kubectl describe cm <名字>

# 编辑
kubectl edit cm <名字>

# 从YAML文件
kubectl apply -f config.yaml
🎯 面试要点
是什么：配置管理中心

怎么用：环境变量（简单值）、文件挂载（配置文件）

更新区别：文件自动更新，环境变量要重启

和Secret区别：ConfigMap存普通配置，Secret存敏感数据

📝 一句话工作记忆
Java项目：application.yml放ConfigMap，挂载到/app/config，Spring从这读。改配置后重启Deployment最保险。

够了，就记这些！ 工作中遇到问题再查具体细节。
