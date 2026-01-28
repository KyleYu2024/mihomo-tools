FROM python:3.9-slim

ENV TZ=Asia/Shanghai
WORKDIR /app

# 安装基础环境
RUN apt-get update && apt-get install -y \
    curl git supervisor tzdata iproute2 iptables ca-certificates \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 伪造 systemctl
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

# 下载 Mihomo (v1.18.1)
RUN curl -L https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz -o /tmp/mihomo.gz \
    && gzip -d /tmp/mihomo.gz \
    && mv /tmp/mihomo /usr/local/bin/mihomo \
    && chmod +x /usr/local/bin/mihomo

# 准备目录
RUN mkdir -p /etc/mihomo/scripts /etc/mihomo/ui /var/log

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY manager/ /app/manager/

# 暴露端口: 7838(Web), 7890(Http), 7891(Socks), 9090(API), 53(DNS)
EXPOSE 7838 7890 7891 9090 53/tcp 53/udp

CMD ["/usr/bin/supervisord"]
