#/bin/bash
read -p "请输入从节点的数量（默认数量1）: " slaveNodeNum
if [ -z "$slaveNodeNum" ]; then
  slaveNodeNum="1"
fi
read -p "请输入master密码（默认数量123456）: " masterPasswd
if [ -z "$masterPasswd" ]; then
  masterPasswd="123456"
fi

read -p "请输入slave密码（默认数量123456）: " slavePasswd
if [ -z "$slavePasswd" ]; then
  slavePasswd="123456"
fi


read -p "请输入master端口, 从节点端口在主节点端口后面顺序累加（默认数量3000）: " masterPort
if [ -z "$masterPort" ]; then
  masterPort="3000"
fi

host=$(ip addr show | grep -w "inet" | grep -v "127.0.0.1" | grep -E "192\.168\..*" | awk '{print $2}' | cut -d/ -f1 | head -n 1)


mkdir -p ./mysql_master/conf
serverId=1
cat > ./mysql_master/conf/my.cnf<< EOF
[mysqld]
server-id=$serverId
log-bin=mysql-bin
bind-address = 0.0.0.0
EOF

content=$(cat << EOF 
services:
  mysql_master: 
    image: mysql:8.0
    container_name: mysql_master
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $masterPasswd
      TZ: 
    ports:
      - $masterPort:3306 
    privileged: true
    volumes:
      - ./mysql_master/log:/var/log/mysql  
      - ./mysql_master/conf/:/etc/mysql/conf.d:ro
      - ./mysql_master/data:/var/lib/mysql
EOF
)
let "serverId++"

index=1
slavePort="$masterPort"
while(( $index<=$slaveNodeNum ))
do
let "slavePort++"

slaveSection=$(cat <<EOF
  mysql_slave0$index:
    image: mysql:8.0
    container_name: mysql_slave0$index
    restart: always
    links:
      - mysql_master
    environment:
      MYSQL_ROOT_PASSWORD: $slavePasswd
    ports:
      - $slavePort:3306
    privileged: true
    volumes:
      - ./mysql_slave0$index/log:/var/log/mysql  
      - ./mysql_slave0$index/conf/:/etc/mysql/conf.d:ro
      - ./mysql_slave0$index/data:/var/lib/mysql
EOF
)
content="$content
$slaveSection"

mkdir -p ./mysql_slave0$index/conf
cat > ./mysql_slave0$index/conf/my.cnf<< EOF
[mysqld]
server-id=$serverId
log-bin=mysql-bin
bind-address = 0.0.0.0
EOF
    let "index++"
    let "serverId++"
done

echo "$content" > docker-compose.yml
docker compose up  -d

sleep 20



# master node
docker exec -ti mysql_master /bin/bash -c "mysql -uroot -p$masterPasswd <<EOL
create user 'slave'@'%' identified with mysql_native_password by '$slavePasswd';
GRANT ALL PRIVILEGES ON *.* TO 'slave'@'%' WITH GRANT OPTION;
flush privileges;
EOL"



mysql_bin=$(docker exec -ti mysql_master /bin/bash -c "mysql -h127.0.0.1  -uroot -p$masterPasswd -e 'show master status;'" | sed -n '/mysql-bin/p' | awk '{print $2}')
echo "mysql_bin_name: $mysql_bin"
echo "***********************************"
mysql_bin_pos=$(docker exec -ti mysql_master /bin/bash -c "mysql -h127.0.0.1  -uroot -p$masterPasswd -e 'show master status;'"|sed -n '/mysql-bin/p'|awk '{print $4}')
echo "mysql_bin_pos $mysql_bin_pos"

# #slave node

nodeIndex=1
while(( $nodeIndex<=$slaveNodeNum ))
do
echo "Slave0$nodeIndex:"
info=$(docker exec -ti mysql_slave0$nodeIndex  /bin/bash -c "mysql -uroot -p$slavePasswd<<EOL
change master to master_host= '$host', master_user='slave', master_password='$slavePasswd', master_port=$masterPort,master_log_file='$mysql_bin', master_log_pos=$mysql_bin_pos;
STOP REPLICA;
START REPLICA;
EOL")
    let "nodeIndex++"
done



