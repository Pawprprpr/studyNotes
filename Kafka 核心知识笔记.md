# 📝 Kafka 核心知识笔记

## 一、Kafka 基础概念

### 1.1 什么是 Kafka？
- **事件流平台**：集发布订阅、持久化存储、流处理于一身
- **分布式系统**：由 Broker 服务器和客户端组成
- **高可靠性**：容错、可扩展、安全

### 1.2 核心术语
| 术语 | 说明 | 类比 |
|------|------|------|
| Event（事件） | 业务发生的事实记录 | 数据库中的一行记录 |
| Topic（主题） | 事件分类的逻辑概念 | 数据库表 |
| Partition（分区） | Topic 的物理分片 | 表分区 |
| Producer（生产者） | 发布事件的客户端 | 数据写入方 |
| Consumer（消费者） | 订阅事件的客户端 | 数据读取方 |
| Consumer Group（消费者组） | 一组协同工作的消费者 | 负载均衡组 |

## 二、生产者详解

### 2.1 消息确认机制（acks）

```java
// 三种确认模式
Properties props = new Properties();

// 模式1: acks=0 - 最大吞吐量
props.put("acks", "0");  // 发送即忘，可能丢失

// 模式2: acks=1 - 平衡模式（默认）
props.put("acks", "1");  // Leader确认，可能丢失

// 模式3: acks=all - 最高可靠性
props.put("acks", "all"); // 所有ISR副本确认，不丢失

这里指的是等待broker的应答

### 2.2  幂等性
**保证不会重复发消息的关键**



#### 解决的问题：

**网络重试导致的消息重复**

**生产者重启后的重复发送**

#### 工作原理：

每个生产者有唯一 PID

每条消息有序列号

Broker 拒绝重复序列号的消息


## 二、消费者详解

###  1.1 负载均衡的范围
负载均衡发生在同一个消费组内的不同消费者实例之间！

1.1 并发配置到底是什么？

```java
@Configuration
public class ConsumerConcurrencyDetail {
    
    /**
     * 并发配置 = 一个@KafkaListener方法启动多少个消费者实例
     */
    
    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object> 
            kafkaListenerContainerFactory() {
        
        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        
        // 关键配置：设置并发消费者数量
        factory.setConcurrency(3);
        
        return factory;
    }
}

@Service
public class ConcurrencyExample {
    
    /**
     * 假设：Topic有6个分区，设置concurrency=3
     * 
     * 实际效果：
     * Spring会为这个@KafkaListener方法启动3个消费者线程
     * 每个线程都是一个独立的Kafka消费者
     * Kafka会自动把6个分区分配给3个消费者
     */
    
    @KafkaListener(topics = "order-events", groupId = "order-processor")
    public void processOrder(String message) {
        // 这个方法会被3个消费者线程并发调用！
        System.out.println("处理订单: " + message + ", 线程: " + Thread.currentThread().getName());
    }
    
    /**
     * 分区分配结果：
     * 消费者线程1 → 分区0, 分区1
     * 消费者线程2 → 分区2, 分区3  
     * 消费者线程3 → 分区4, 分区5
     * 
     * 每个线程处理2个分区，实现并行消费
     */
}
```
1.2 重平衡
发生在实例重启啊 扩容的场景
一般不需要处理，等待业务执行完成就可以


###  2.1 大型互联网kafka如何实现消息同步的
```java
/**
 * 使用 MirrorMaker 2.0 进行集群间数据同步
 */
@Component
public class MirrorMakerSolution {
    
    /**
     * 将 IAM 集群的权限消息复制到 CICD 集群
     */
    public void iamToCicdSync() {
        // IAM 集群 → MirrorMaker → CICD 集群
        // 配置示例：
        
        // mirror-maker.properties:
        // clusters = iam-cluster, cicd-cluster
        // iam-cluster.bootstrap.servers = kafka-iam-1:9092,kafka-iam-2:9092
        // cicd-cluster.bootstrap.servers = kafka-cicd-1:9092,kafka-cicd-2:9092
        
        // 复制规则：
        // replicas = iam-cluster->cicd-cluster
        // iam-cluster->cicd-cluster.topics = auth-sync, user-events
    }
    
    /**
     * 运维部署 MirrorMaker
     */
    public void deployMirrorMaker() {
        // 命令行部署：
        // bin/connect-mirror-maker.sh mirror-maker.properties
        
        // 或者使用 Kubernetes：
        // kubectl apply -f mirror-maker-deployment.yaml
    }
}

@Service
@Slf4j
public class DualWriteProducer {
    
    @Autowired
    @Qualifier("iamKafkaTemplate")
    private KafkaTemplate<String, Object> iamKafkaTemplate;
    
    @Autowired
    @Qualifier("cicdKafkaTemplate")  
    private KafkaTemplate<String, Object> cicdKafkaTemplate;
    
    /**
     * IAM 服务同时写入两个集群
     */
    @Transactional
    public void syncUserPermission(UserPermission permission) {
        // 1. 业务逻辑处理
        permissionService.updatePermission(permission);
        
        // 2. 双写消息到两个集群
        CompletableFuture<SendResult<String, Object>> iamFuture = 
            iamKafkaTemplate.send("auth-sync", permission.getUserId(), permission);
            
        CompletableFuture<SendResult<String, Object>> cicdFuture = 
            cicdKafkaTemplate.send("auth-sync", permission.getUserId(), permission);
        
        // 3. 等待写入完成
        try {
            CompletableFuture.allOf(iamFuture, cicdFuture).get(5, TimeUnit.SECONDS);
            log.info("权限同步消息双写成功");
        } catch (Exception e) {
            log.error("双写失败，需要补偿", e);
            // 补偿逻辑：记录失败，定时重试
            compensationService.recordDualWriteFailure(permission);
        }
    }
}

@Configuration
public class MultiClusterConfig {
    
    /**
     * 多集群 Kafka 配置
     */
    @Bean("iamKafkaTemplate")
    public KafkaTemplate<String, Object> iamKafkaTemplate() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, 
                 "kafka-iam-1:9092,kafka-iam-2:9092,kafka-iam-3:9092");
        // IAM 集群专用配置
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(props));
    }
    
    @Bean("cicdKafkaTemplate")
    public KafkaTemplate<String, Object> cicdKafkaTemplate() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG,
                 "kafka-cicd-1:9092,kafka-cicd-2:9092"); 
        // CICD 集群专用配置
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(props));
    }
}

@Service
public class KafkaGatewayService {
    
    /**
     * 统一的 Kafka 网关服务
     * 其他系统通过 HTTP API 发送消息，由网关路由到对应集群
     */
    @PostMapping("/api/v1/message/{cluster}/{topic}")
    public ResponseEntity<String> sendMessage(
            @PathVariable String cluster,
            @PathVariable String topic,
            @RequestBody MessageRequest request) {
        
        try {
            KafkaTemplate<String, Object> kafkaTemplate = 
                kafkaTemplateManager.getTemplate(cluster);
                
            kafkaTemplate.send(topic, request.getKey(), request.getValue())
                .get(10, TimeUnit.SECONDS);
                
            return ResponseEntity.ok("消息发送成功");
        } catch (Exception e) {
            log.error("消息发送失败: cluster={}, topic={}", cluster, topic, e);
            return ResponseEntity.status(500).body("消息发送失败");
        }
    }
}

@Component
public class KafkaTemplateManager {
    
    private Map<String, KafkaTemplate<String, Object>> templateMap = new ConcurrentHashMap<>();
    
    /**
     * 管理多个集群的 KafkaTemplate
     */
    @PostConstruct
    public void initTemplates() {
        // 初始化各集群连接
        templateMap.put("iam", createTemplate("kafka-iam-1:9092,kafka-iam-2:9092"));
        templateMap.put("cicd", createTemplate("kafka-cicd-1:9092,kafka-cicd-2:9092"));
        templateMap.put("logs", createTemplate("kafka-logs-1:9092,kafka-logs-2:9092"));
        templateMap.put("monitor", createTemplate("kafka-monitor-1:9092"));
    }
    
    public KafkaTemplate<String, Object> getTemplate(String cluster) {
        KafkaTemplate<String, Object> template = templateMap.get(cluster);
        if (template == null) {
            throw new IllegalArgumentException("未知的Kafka集群: " + cluster);
        }
        return template;
    }
}
```
