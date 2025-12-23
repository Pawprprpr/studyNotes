Volumes和Bind mounts核心区别
Volumes用docker命令划分出一块区域出来并命名，Bind mounts直接挂宿主机路径
Volumes可以直接挂EFS
区别如下
先mount -t nfs到主机目录
再docker run -v /host/nfsdir:/container/path
卷驱动方式：
docker volume create --driver local --opt type=nfs
docker run -v volume-name:/container/path
