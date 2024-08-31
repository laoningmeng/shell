#!/bin/bash
wget https://github.com/cloudreve/Cloudreve/releases/download/3.8.3/cloudreve_3.8.3_linux_amd64.tar.gz

tar -zxvf cloudreve_3.8.3_linux_amd64.tar.gz

path=$(pwd)

if [ ! -d "/usr/lib/systemd/system" ]; then
    mkdir -p /usr/lib/systemd/system
fi


cat > /usr/lib/systemd/system/cloudreve.service << EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target
After=mysqld.service
Wants=network.target

[Service]
WorkingDirectory=$path
ExecStart=$path/cloudreve
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

StandardOutput=null
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

cat > start.sh << EOF
#!/bin/bash

if [ -f "mima" ]; then
    systemctl start cloudreve
else
    echo "【生成账号密码，等待3s可以ctrl+c 停止，重新运行此脚本，密码信息在mima文件中寻找】"
    ./cloudreve>>mima
fi
EOF


cat > stop.sh << EOF
#!/bin/bash
systemctl stop cloudreve
EOF

cat > restart.sh << EOF
#!/bin/bash
systemctl restart cloudreve
EOF


cat > status.sh << EOF
#!/bin/bash
systemctl status cloudreve
EOF

systemctl daemon-reload
systemctl enable cloudreve
echo "【安装成功，启动请执行start.sh, 停止使用stop.sh, 重启使用restart 查看状态使用status.sh】"
