FROM python:3.9-slim

# 设置时区
ENV TZ=Asia/Shanghai
WORKDIR /app

# 1. 安装基础工具 (包含 iptables, iproute2 用于透明网关)
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

# 2. 伪造 systemctl (保持不变)
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

# 3. 下载 Mihomo (保持不变)
RUN curl -L https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz -o /tmp/mihomo.gz \
    && gzip -d /tmp/mihomo.gz \
    && mv /tmp/mihomo /usr/local/bin/mihomo \
    && chmod +x /usr/local/bin/mihomo

# 4. 目录准备
RUN mkdir -p /etc/mihomo/scripts /etc/mihomo/ui /var/log

# 5. 依赖安装
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 6. 复制文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY manager/ /app/manager/

# 7. 创建日志文件
RUN touch /var/log/mihomo.log

# 8. 【修改这里】暴露新端口
# 7838: Web面板 | 1053: DNS | 其他保持不变
EXPOSE 7838 7890 7891 9090 1053/tcp 1053/udp

CMD ["/usr/bin/supervisord"]
