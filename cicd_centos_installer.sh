#/bin/bash

ip=$(ip addr show | grep -w "inet" | grep -v "127.0.0.1" | grep -E "192\.168\..*" | awk '{print $2}' | cut -d/ -f1 | head -n 1)
read -p "请输入安装位置（绝对路径, 默认/root）: " path
if [ -z "$path" ]; then
  path="/root"
fi
read -p "请输入gitlab访问端口号(默认 8000): " gitlabPort
if [ -z "$gitlabPort" ]; then
  gitlabPort=8000
fi
read -p "请输入gitlab ssh端口号(默认 23): " gitlabSshPort
if [ -z "$gitlabSshPort" ]; then
  gitlabSshPort=23
fi
read -p "请输入jenkins端口号(默认 8001): " jenkinsPort
if [ -z "$jenkinsPort" ]; then
  jenkinsPort=8001
fi
read -p "请输入nexus端口号(默认 8002): " nexusPort
if [ -z "$nexusPort" ]; then
  nexusPort=8002
fi

mkdir $path/nexus
chmod 777 $path/nexus
mkdir $path/gitlab
chmod 777 $path/gitlab
mkdir $path/jenkins
chmod 777 $path/jenkins


echo "#########################################"
echo "#         1.安装java                     #"
echo "#########################################"

if ! command -v java &> /dev/null; then
    echo "java 未安装，正在安装 maven..."

    # 安装java
    wget -P /usr/local/src/ https://repo.huaweicloud.com/java/jdk/8u202-b08/jdk-8u202-linux-x64.tar.gz

    tar -zxvf /usr/local/src/jdk-8u202-linux-x64.tar.gz -C /usr/local/src
    mv /usr/local/src/jdk1.8.0_202/ /usr/local/java

    cat <<EOL >> /etc/profile
export JAVA_HOME=/usr/local/java
export JRE_HOME=/usr/local/java/jre
export CLASSPATH=\$JAVA_HOME/lib:\$JRE_HOME/lib
export PATH=\$PATH:\$JAVA_HOME/bin:\$JRE_HOME/bin
EOL
    source /etc/profile
else
    echo "java 已安装!"
fi



echo "#########################################"
echo "#         2.安装maven                    #"
echo "#########################################"

if ! command -v mvn &> /dev/null; then
    echo "maven 未安装，正在安装 maven..."

    wget -P /usr/local/src/ https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz --no-check-certificate
    tar -zxvf /usr/local/src/apache-maven-3.9.9-bin.tar.gz  -C /usr/local/src
    mv /usr/local/src/apache-maven-3.9.9 /usr/local/maven
    cat <<EOL >> /etc/profile
export PATH=\$PATH:/usr/local/maven/bin
EOL
    source /etc/profile
else
    echo "maven 已安装!"
fi


echo "#########################################"
echo "#         3.安装git                     #"
echo "#########################################"

if ! command -v git &> /dev/null; then
    echo "git 未安装，正在安装 git..."

    dnf install -y git-all
else
    echo "git 已安装!"
fi



echo "#########################################"
echo "#         4.安装docker                   #"
echo "#########################################"


if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，正在安装 Docker..."

    curl -fsSL https://get.docker.com -o /usr/local/src/get-docker.sh
    sh get-docker.sh
else
    echo "Docker 已安装!"
fi


echo "#########################################"
echo "#         5.安装nginx                    #"
echo "#########################################"

if ! command -v nginx &> /dev/null; then
    echo "nginx 未安装，正在安装 nginx..."
    dnf install -y  gcc gcc-c++ pcre pcre-devel zlib zlib-devel  openssl openssl-devel
    wget -P /usr/local/src/ https://nginx.org/download/nginx-1.26.2.tar.gz  --no-check-certificate
    tar -zxvf /usr/local/src/nginx-1.26.2.tar.gz  -C /usr/local/src
    cd  /usr/local/src/nginx-1.26.2
    ./configure --prefix=/usr/local/nginx
    make 
    make install
    cat <<EOL >> /etc/profile
export PATH=\$PATH:/usr/local/nginx/sbin
EOL
  source /etc/profile
  mkdir /usr/local/nginx/conf/servers
  sed -i '$i include servers/*;' /usr/local/nginx/conf/nginx.conf
  cat > /usr/local/nginx/conf/servers/gitlab.com.conf << EOF
server {
        listen       80;
        server_name  gitlab.com;
        location / {
                proxy_pass http://$ip:$gitlabPort/;
        }
}
EOF
  cat > /usr/local/nginx/conf/servers/jenkins.com.conf << EOF
server {
        listen       80;
        server_name  jenkins.com;
        location / {
                proxy_pass http://$ip:$jenkinsPort;
        }
}

EOF
  cat > /usr/local/nginx/conf/servers/nexus.com.conf << EOF
server {
        listen       80;
        server_name  nexus.com;
        location / {
                proxy_pass http://$ip:$nexusPort;
        }
}
EOF
  nginx -s reload
else
    echo "nginx 已安装!"
fi


echo "#########################################"
echo "#         6.安装docker-compose.yml       #"
echo "#########################################"

cat > $path/docker-compose.yml << EOF
version: '3'
services:
  nexus:
    image: sonatype/nexus3
    container_name: nexus
    restart: always
    privileged: true
    environment:
      - TZ=Asia/Shanghai
    ports:
      - $nexusPort:8081
    volumes:
      - $path/nexus:/nexus-data
  jenkins:
    image: jenkins/jenkins
    container_name: jenkins
    ports:
      - $jenkinsPort:8080
      - 50000:50000
    privileged: true
    links:
      - nexus
    volumes:
      - $path/jenkins:/var/jenkins_home
      - /usr/local/maven:/usr/local/maven
      - /usr/local/java:/usr/local/java
      - /usr/bin/git:/usr/local/git
      - /etc/localtime:/etc/localtime
    restart: always
  gitlab:
    image: gitlab/gitlab-ce:17.1.6-ce.0
    hostname: '$ip'
    container_name: gitlab
    privileged: true
    restart: always
    ports:
      - $gitlabPort:80
      - 443:443
      - $gitlabSshPort:22
    volumes:
      - $path/gitlab/config:/etc/gitlab
      - $path/gitlab/logs:/var/log/gitlab
      - $path/gitlab/data:/var/opt/gitlab
    shm_size: '256m'
EOF


echo "#########################################"
echo "#         7.安装管理脚本                  #"
echo "#########################################"

cat > /usr/local/bin/cicd << EOF
#!/bin/bash

case "\$1" in
  up)
    docker compose -f $path/docker-compose.yml up -d
    ;;
  down)
    docker compose -f $path/docker-compose.yml down
    ;;
  *)
    echo "Usage: $0 {up|down}"
    exit 1
    ;;
esac
EOF
chmod +x /usr/local/bin/cicd



cat > $path/build_info << EOF
################################################################
                            内容说明                           
 IP: $ip                                                      
 gitlabPort: $gitlabPort                                      
 gitlabSshPort: $gitlabSshPort                                
 jenkinsPort: $jenkinsPort                                    
 nexusPort: $nexusPort                                        
 gitlab访问: http://$ip:$gitlabPort 或者 http://gitlab.com     
 jenkins访问: http://$ip:$jenkinsPort 或者 http://jenkins.com  
 nexus访问: http://$ip:$nexusPort 或者 http://nexus.com        
 启动/关闭快捷命令 cicd up/down                                  
 docker-compose.yml位置: $path/docker-compose.yml              
#################################################################
EOF

cat $path/build_info




