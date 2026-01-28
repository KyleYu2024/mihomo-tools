FROM python:3.9-slim

# 设置时区和工作目录
ENV TZ=Asia/Shanghai
WORKDIR /app

# 1. 安装基础工具和 Supervisor
RUN apt-get update && apt-get install -y \
    curl \
    git \
    supervisor \
    tzdata \
    iproute2 \
    iptables \
    ca-certificates \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. 【黑魔法】创建伪造的 systemctl 脚本
# 这样 app.py 调用 subprocess.run("systemctl ...") 时实际上是在控制 supervisord
RUN echo '#!/bin/bash\n\
if [ "$1" == "is-active" ]; then\n\
    supervisorctl status $2 | grep -q "RUNNING" && exit 0 || exit 1\n\
elif [ "$1" == "start" ]; then\n\
    supervisorctl start $2\n\
elif [ "$1" == "stop" ]; then\n\
    supervisorctl stop $2\n\
elif [ "$1" == "restart" ]; then\n\
    supervisorctl restart $2\n\
fi' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl

# 3. 下载 Mihomo 内核 (这里下载的是 v1.18.1，你可以换成 latest)
# 架构默认为 amd64，如果是树莓派需改为 arm64
RUN curl -L https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz -o /tmp/mihomo.gz \
    && gzip -d /tmp/mihomo.gz \
    && mv /tmp/mihomo /usr/local/bin/mihomo \
    && chmod +x /usr/local/bin/mihomo

# 4. 准备目录结构
RUN mkdir -p /etc/mihomo/scripts /etc/mihomo/ui /var/log

# 5. 复制 Python 依赖并安装
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 6. 复制项目文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY manager/ /app/manager/
# 如果你有 scripts 目录，也取消注释下面这就行
# COPY scripts/ /etc/mihomo/scripts/

# 7. 创建空白日志文件以防报错
RUN touch /var/log/mihomo.log

# 8. 暴露端口
# 8080: Web管理 | 7890: HTTP代理 | 7891: Socks5 | 9090: API | 53: DNS
EXPOSE 8080 7890 7891 9090 53/tcp 53/udp

# 启动 Supervisor
CMD ["/usr/bin/supervisord"]
