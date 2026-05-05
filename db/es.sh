#!/bin/bash
# FilePath    : blog-tool/db/es.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : elasticsearch

# 创建 es 挂载目录
mkdir_es_volume() {
  log_debug "run mkdir_es_volume"

  # 创建目录
  if [ ! -d "$DATA_VOLUME_DIR/es" ]; then
    setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es"
  fi
}

# 获取带 IK 分词器的 ES 镜像标签.
# 参数: $1: es 版本号.
# 返回: 输出本地构建后的 ES 镜像标签.
get_es_image_with_ik() {
  log_debug "run get_es_image_with_ik"

  local es_version="$1"

  if [ -z "$es_version" ]; then
    log_error "获取 ES IK 镜像标签失败, 参数不能为空"
    return 1
  fi

  echo "elasticsearch:$es_version"
}

# 下载指定版本的 IK 分词器插件包.
# 参数: $1: es 版本号.
# 返回: 输出共享插件包路径.
prepare_es_ik_zip() {
  log_debug "run prepare_es_ik_zip"

  local es_version="$1"
  local ik_zip_name=""
  local ik_zip_url=""
  local ik_zip_shared=""

  if [ -z "$es_version" ]; then
    log_error "准备 IK 分词器插件包失败, 参数不能为空"
    return 1
  fi

  ik_zip_name="elasticsearch-analysis-ik-$es_version.zip"
  ik_zip_url="https://release.infinilabs.com/analysis-ik/stable/$ik_zip_name"
  ik_zip_shared="$DATA_VOLUME_DIR/es/plugin/$ik_zip_name"

  setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es/plugin"

  if [ ! -f "$ik_zip_shared" ]; then
    log_info "下载 IK 分词器插件: $ik_zip_url"
    sudo curl -fSL -o "$ik_zip_shared" "$ik_zip_url"
    sudo chown "$ES_UID:$ES_GID" "$ik_zip_shared"
  fi

  echo "$ik_zip_shared"
}

# 确保使用推荐方式构建带 IK 分词器的 ES 镜像.
# 参数: $1: es 版本号.
# 返回: 成功时完成本地镜像构建或复用.
ensure_es_image_with_ik() {
  log_debug "run ensure_es_image_with_ik"

  local es_version="$1"
  local es_image=""
  local build_context_dir="$BLOG_TOOL_ENV/es-image"
  local ik_zip_shared=""
  local image_has_ik_label=""
  local image_label_version=""

  if [ -z "$es_version" ]; then
    log_error "构建 ES IK 镜像失败, 参数不能为空"
    return 1
  fi

  # 先确定目标镜像标签. 这里仍复用 Elasticsearch 官方镜像名称, 但通过本地重建让同名 tag 变为带 IK 的镜像.
  es_image=$(get_es_image_with_ik "$es_version") || return 1

  # 优先复用已经构建好的本地镜像. 通过自定义 label 判断该镜像是否确实由 blog-tool 构建, 且插件版本与 ES 版本匹配.
  if sudo docker image inspect "$es_image" >/dev/null 2>&1; then
    image_has_ik_label=$(sudo docker image inspect --format='{{ index .Config.Labels "blog-tool.es.ik-plugin" }}' "$es_image" 2>/dev/null || true)
    image_label_version=$(sudo docker image inspect --format='{{ index .Config.Labels "blog-tool.es.version" }}' "$es_image" 2>/dev/null || true)

    if [ "$image_has_ik_label" == "true" ] && [ "$image_label_version" == "$es_version" ]; then
      log_debug "检测到已存在带 IK 分词器的 ES 镜像: $es_image"
      return 0
    fi
  fi

  # 构建前先准备插件压缩包. 官方推荐思路是将插件作为镜像构建输入, 而不是等容器启动后再动态安装.
  ik_zip_shared=$(prepare_es_ik_zip "$es_version") || return 1

  # 准备临时构建上下文. 这里动态生成 Dockerfile, 让插件安装发生在 docker build 阶段.
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$BLOG_TOOL_ENV" "$build_context_dir"
  sudo cp "$ik_zip_shared" "$build_context_dir/analysis-ik.zip"
  sudo chown "$JPZ_UID:$JPZ_GID" "$build_context_dir/analysis-ik.zip"

  # 使用官方 Elasticsearch 镜像作为基础镜像.
  # 构建阶段临时切到 root, 是为了安装插件和清理临时文件.
  # 插件安装完成后再切回 1000:0, 保持容器运行身份与官方镜像一致.
  # 这样容器启动时直接使用已预装插件的镜像, 不再依赖启动期动态安装插件.
  sudo tee "$build_context_dir/Dockerfile" >/dev/null <<-EOM
FROM elasticsearch:$es_version
USER root
COPY analysis-ik.zip /tmp/analysis-ik.zip
RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch file:///tmp/analysis-ik.zip \
    && rm -f /tmp/analysis-ik.zip \
    && chown -R $ES_UID:$ES_GID /usr/share/elasticsearch/plugins
USER 1000:0
LABEL blog-tool.es.ik-plugin="true"
LABEL blog-tool.es.version="$es_version"
EOM

  # 通过 docker build 生成最终运行镜像. 这一步成功后, 后续 docker compose up 只负责启动容器, 不再承担插件安装职责.
  log_info "开始构建带 IK 分词器的 ES 镜像: $es_image"
  sudo DOCKER_BUILDKIT=1 docker build --pull --no-cache -t "$es_image" "$build_context_dir"
}

# 清理旧版运行期插件安装配置.
# 返回: 删除节点配置中的插件安装清单与插件压缩包, 避免容器启动时再次动态安装插件.
cleanup_es_legacy_plugin_runtime_files() {
  log_debug "run cleanup_es_legacy_plugin_runtime_files"

  local node_dir=""
  local node_config_dir=""

  for node_dir in "$DATA_VOLUME_DIR"/es/node-*/; do
    [ -d "$node_dir" ] || continue

    node_config_dir="${node_dir}config"
    [ -d "$node_config_dir" ] || continue

    sudo rm -f "$node_config_dir/elasticsearch-plugins.yml"
    sudo rm -f "$node_config_dir"/elasticsearch-analysis-ik-*.zip
  done
}

# 复制 es 配置文件
copy_es_config() {
  log_debug "run copy_es_config"

  local is_kibana=$1                       # 是否包含 kibana
  local ca_cert_file="$CA_CERT_DIR/ca.crt" # CA 证书文件
  local ca_key_file="$CA_CERT_DIR/ca.key"  # CA 私钥文件
  local es_image=""

  # 生成 ca 证书
  gen_my_ca_cert

  ensure_es_image_with_ik "$IMG_VERSION_ES" || return 1
  es_image=$(get_es_image_with_ik "$IMG_VERSION_ES") || return 1

  # 创建临时容器,用于复制配置文件
  sudo docker create --name temp_container_es -m 512MB "$es_image" >/dev/null 2>&1 || true

  # 根据 ES 节点数量,循环复制配置文件
  local i
  for ((i = 1; i <= ES_NODE_COUNT; i++)); do
    # ip_node 自增 从 2 开始, 1 为网关
    local ip_node="$IPV4_BASE_ES.$(((i + 1) % 256))"

    # 格式化节点编号
    local formattedI
    formattedI=$(printf "%02d" $i)

    # 节点目录
    local dir_node="$DATA_VOLUME_DIR/es/node-$formattedI"

    sudo rm -rf "$dir_node"                                                      # 删除原来的配置文件
    setup_directory "$ES_UID" "$ES_GID" 755 "$dir_node/config" "$dir_node/data"  # 创建目录
    sudo docker cp temp_container_es:/usr/share/elasticsearch/config "$dir_node" # 配置
    sudo docker cp temp_container_es:/usr/share/elasticsearch/data "$dir_node"   # 数据
    sudo cp "$ca_cert_file" "$dir_node/config/ca.crt"                            # CA 证书

    # 生成证书
    generate_instance_cert "es-$IMG_VERSION_ES-$formattedI" \
      "es-$IMG_VERSION_ES-$formattedI,localhost" \
      "127.0.0.1,$HOST_INTRANET_IP,$ip_node,$PUBLIC_IP_ADDRESS" \
      "$dir_node/config" \
      "$CERT_DAYS_VALID" \
      "$ca_cert_file" \
      "$ca_key_file"

    # 再次赋权
    setup_directory "$ES_UID" "$ES_GID" 755 "$dir_node/config" "$dir_node/data"

    # 安装完插件后添加自定义词典配置
    _setup_ik_custom_dic "$dir_node/"

  done

  # 删除临时容器
  sudo docker rm -f temp_container_es >/dev/null 2>&1 || true
  cleanup_es_legacy_plugin_runtime_files

  # 是否包含 kibana
  if [ "$is_kibana" = "y" ]; then
    # 创建临时容器
    sudo docker create --name temp_container_kibana -m 512MB "kibana:$IMG_VERSION_KIBANA" >/dev/null 2>&1 || true

    # 复制 kibana 配置文件
    sudo rm -rf "$DATA_VOLUME_DIR/es/kibana"                                                                              # 删除原来的配置文件
    setup_directory "$KIBANA_UID" "$KIBANA_GID" 755 "$DATA_VOLUME_DIR/es/kibana/config" "$DATA_VOLUME_DIR/es/kibana/data" # 创建目录
    sudo docker cp temp_container_kibana:/usr/share/kibana/config "$DATA_VOLUME_DIR/es/kibana"                            # 复制配置文件
    sudo docker cp temp_container_kibana:/usr/share/kibana/data "$DATA_VOLUME_DIR/es/kibana"                              # 复制配置文件
    sudo docker rm -f temp_container_kibana >/dev/null 2>&1 || true                                                       # 删除临时容器
    sudo cp "$ca_cert_file" "$DATA_VOLUME_DIR/es/kibana/config/ca.crt"                                                    # CA 证书
    setup_directory "$KIBANA_UID" "$KIBANA_GID" 755 "$DATA_VOLUME_DIR/es/kibana/config" "$DATA_VOLUME_DIR/es/kibana/data" # 再次赋权

    # 向 "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml" 文件追加配置, 切换为中文 i18n.locale: "zh-CN"
    # 首先判断 是否有 i18n.locale, 如果没有则追加, 如果有则替换
    if ! sudo grep -q "i18n.locale" "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"; then
      printf "\ni18n.locale: \"zh-CN\"\n" | sudo tee -a "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"
    else
      sudo sed -i 's/i18n.locale: .*/i18n.locale: "zh-CN"/' "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"
    fi
  fi

  log_info "es 复制配置文件到 volume success"
}

# ========================= IK 分词器: 基础工具函数 =========================

# 为单个 ES 节点设置 IK 自定义词典配置
# 参数: $1: node_dir - 节点目录路径(如 $DATA_VOLUME_DIR/es/node-01/)
# 流程: 确保 analysis-ik 目录 → 确保 my.dic 存在 → 更新 IKAnalyzer.cfg.xml ext_dict
_setup_ik_custom_dic() {
  log_debug "run _setup_ik_custom_dic"

  local node_dir="$1"
  local ik_config_dir
  ik_config_dir=$(_ensure_ik_config_dir "$node_dir")
  _ensure_my_dic_file "$ik_config_dir"

  # 处理 IKAnalyzer.cfg.xml: 更新 ext_dict 配置项
  # 注意: copy_es_config 阶段 IK 插件尚未安装, 文件不存在, 需主动创建
  local ik_cfg_file="$ik_config_dir/IKAnalyzer.cfg.xml"
  if [[ -f "$ik_cfg_file" ]]; then
    sudo sed -i 's|<entry key="ext_dict">[^<]*</entry>|<entry key="ext_dict">my.dic</entry>|g' "$ik_cfg_file"
    log_info "更新 IKAnalyzer.cfg.xml ext_dict 配置: $ik_cfg_file"
  else
    # IK 插件启动时会读取此文件, 预先创建以确保自定义词典在首次启动即生效
    sudo tee "$ik_cfg_file" >/dev/null <<-EOM
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
<properties>
        <comment>IK Analyzer 扩展配置</comment>
        <!--用户可以在这里配置自己的扩展字典 -->
        <entry key="ext_dict">my.dic</entry>
         <!--用户可以在这里配置自己的扩展停止词字典-->
        <entry key="ext_stopwords"></entry>
        <!--用户可以在这里配置远程扩展字典 -->
        <!-- <entry key="remote_ext_dict">words_location</entry> -->
        <!--用户可以在这里配置远程扩展停止词字典-->
        <!-- <entry key="remote_ext_stopwords">words_location</entry> -->
</properties>
EOM
    log_info "创建 IKAnalyzer.cfg.xml 并配置 ext_dict: $ik_cfg_file"
  fi

  # 统一赋权, 确保 analysis-ik 目录及其下所有文件权限正确
  setup_directory "$ES_UID" "$ES_GID" 755 "$ik_config_dir"
}

# 确保单个节点的 analysis-ik 目录存在
# 参数: $1: node_dir - 节点目录路径(如 $DATA_VOLUME_DIR/es/node-01/)
# 返回: 通过 stdout 输出 analysis-ik 目录路径
_ensure_ik_config_dir() {
  log_debug "run _ensure_ik_config_dir"

  local node_dir="$1"
  local ik_config_dir="${node_dir}config/analysis-ik"

  if [[ ! -d "$ik_config_dir" ]]; then
    setup_directory "$ES_UID" "$ES_GID" 755 "$ik_config_dir"
    log_debug "创建 IK 配置目录: $ik_config_dir"
  fi

  echo "$ik_config_dir"
}

# 确保单个节点的 my.dic 文件存在(已存在则跳过, 避免覆盖)
# 参数: $1: ik_config_dir - analysis-ik 目录路径
_ensure_my_dic_file() {
  log_debug "run _ensure_my_dic_file"

  local ik_config_dir="$1"
  local my_dic_file="$ik_config_dir/my.dic"

  if [[ ! -f "$my_dic_file" ]]; then
    sudo touch "$my_dic_file"
    sudo chown "$ES_UID:$ES_GID" "$my_dic_file"
    log_info "创建自定义词典文件: $my_dic_file"
  else
    log_debug "自定义词典文件已存在, 跳过创建: $my_dic_file"
  fi
}

# 读取词典内容: 交互式输入
# 返回: 通过 stdout 输出词典内容
_read_dic_content_interactive() {
  log_debug "run _read_dic_content_interactive"

  local dic_content=""
  log_info "请输入自定义词条(每行一个词, 输入空行结束):"
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    if [[ -z "$dic_content" ]]; then
      dic_content="$line"
    else
      dic_content="$dic_content"$'\n'"$line"
    fi
  done

  echo "$dic_content"
}

# 将词典内容写入所有 ES 节点的 my.dic 并可选重启
# 参数: $1: dic_content - 词典内容字符串
_write_dic_to_all_nodes() {
  log_debug "run _write_dic_to_all_nodes"

  local dic_content="$1"
  local es_base_dir="$DATA_VOLUME_DIR/es"

  if [[ -z "$dic_content" ]]; then
    log_warn "词典内容为空, 未做任何更新"
    return 0
  fi

  local word_count
  word_count=$(echo "$dic_content" | wc -l)
  log_info "待写入词条数: $word_count"

  # 遍历所有节点写入 my.dic
  local node_dir ik_config_dir my_dic_file updated_count=0
  for node_dir in "$es_base_dir"/node-*/; do
    [[ -d "$node_dir" ]] || continue

    ik_config_dir="${node_dir}config/analysis-ik"
    if [[ ! -d "$ik_config_dir" ]]; then
      log_warn "analysis-ik 目录不存在, 跳过: $ik_config_dir"
      continue
    fi

    my_dic_file="$ik_config_dir/my.dic"

    # 追加写入词典内容(不覆盖原有内容)
    echo "$dic_content" | sudo tee -a "$my_dic_file" >/dev/null

    # 统一赋权, 确保 analysis-ik 目录及其下所有文件权限正确
    setup_directory "$ES_UID" "$ES_GID" 755 "$ik_config_dir"
    log_debug "已更新词典: $my_dic_file"
    ((updated_count++)) || true
  done

  if [[ "$updated_count" -eq 0 ]]; then
    log_error "未找到任何 ES 节点的 analysis-ik 目录, 请先安装 ES"
    return 1
  fi

  log_info "已更新 $updated_count 个节点的 my.dic 词典"

  # 重启 ES 使词典生效
  local is_restart
  is_restart=$(read_user_input "是否重启 ES 使词典生效(默认y) [y|n]? " "y")
  if [[ "$is_restart" == "y" ]]; then
    restart_db_es
    log_info "ES 已重启, 自定义词典已生效"
  else
    log_warn "词典已写入但未重启 ES, 需手动重启后生效"
  fi
}

# ========================= IK 分词器: 业务函数 =========================

# 交互式更新所有 ES 节点的 IK 自定义词典 my.dic
# 流程: 交互式逐行输入词条 → 写入所有节点 my.dic → 可选重启 ES
update_my_dic() {
  log_debug "run update_my_dic"

  local dic_content
  dic_content=$(_read_dic_content_interactive)
  _write_dic_to_all_nodes "$dic_content"
}

# 通过文件更新所有 ES 节点的 IK 自定义词典 my.dic
# 参数: $1: 词典文件路径(每行一个词)
# 流程: 从文件读取词条 → 写入所有节点 my.dic → 可选重启 ES
update_my_dic_by_file() {
  log_debug "run update_my_dic_by_file"

  local dic_source="$1"

  if [[ -z "$dic_source" ]]; then
    log_error "请指定词典文件路径, 用法: update_my_dic_by_file /path/to/words.txt"
    return 1
  fi

  if [[ ! -f "$dic_source" ]]; then
    log_error "词典文件不存在: $dic_source"
    return 1
  fi

  local dic_content
  dic_content=$(sudo cat "$dic_source")
  log_info "从文件读取词典内容: $dic_source"
  _write_dic_to_all_nodes "$dic_content"
}

# 创建 es 配置文件
create_docker_compose_es() {
  log_debug "run create_docker_compose_es"

  local all_remove_data # 是否删除历史数据 默认不删除
  local is_kibana       # 是否包含 kibana 默认包含

  # 提示用户输入

  # 根据运行模式决定是否询问
  if run_mode_is_dev; then
    all_remove_data=$(read_user_input "[1/2]是否删除 es 信息(默认n) [y|n]? " "n")
    is_kibana=$(read_user_input "[2/2]是否包含 kibana (默认n) [y|n]? " "n")
  fi
  if run_mode_is_pro; then
    all_remove_data=$(read_user_input "是否删除 es 信息(默认n) [y|n]? " "n")
    is_kibana="n"
  fi

  if [ ! -d "$DATA_VOLUME_DIR" ]; then
    # 如果不存在则创建
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
  fi

  setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es" # 创建目录

  # 创建一个名为 docker-compose.yaml 的新文件
  local docker_compose_file="$DOCKER_COMPOSE_FILE_ES"

  # 如果存在 docker-compose.yaml 执行docker compose down
  if [ -f "$docker_compose_file" ]; then
    sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" down || true # 删除容器
    touch "$docker_compose_file"
  fi

  # 参考
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-basic
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-compose
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-prod#docker-set-heap-size
  # https://www.elastic.co/docs/reference/elasticsearch/jvm-settings#set-jvm-heap-size
  # https://github.com/elastic/elasticsearch/blob/main/docs/reference/setup/install/docker/docker-compose.yml

  cat >"$docker_compose_file" <<-EOM
services:
EOM

  # 配置文件目录
  local i
  for ((i = 1; i <= ES_NODE_COUNT; i++)); do
    local formattedI
    formattedI=$(printf "%02d" "$i")
    local dir_node="$DATA_VOLUME_DIR/es/node-$formattedI"
    local ip_node="$IPV4_BASE_ES.$(((i + 1) % 256))" # ip_node 自增 从 2 开始, 1 为网关

    # 生成 es 配置文件
    initial_master_nodes=$(generate_items_all "es-$IMG_VERSION_ES" "$ES_NODE_COUNT") # 生成所有 es 节点
    seed_hosts=$(generate_items_exclude "es-$IMG_VERSION_ES" "$i" "$ES_NODE_COUNT")  # 生成所有 es 节点,排除当前节点
    # 追加写入主节点 docker-compose 配置文件
    cat >>"$docker_compose_file" <<-EOM

  # 补全两位小数显示
  es-$IMG_VERSION_ES-$formattedI:
    image: elasticsearch:$IMG_VERSION_ES
    container_name: es-$IMG_VERSION_ES-$formattedI
    restart: always
    volumes:
      - $dir_node/data:/usr/share/elasticsearch/data
      - $dir_node/config:/usr/share/elasticsearch/config
    user: "$ES_UID:$ES_GID"
EOM
    # 仅当 i = 0 时添加 ports 部分 和 entrypoint 部分
    if [ "$i" -eq 1 ]; then
      cat >>"$docker_compose_file" <<-EOM
    ports:
      - $ES_PORT:9200
EOM
    fi

    cat >>"$docker_compose_file" <<-EOM
    environment:
      - node.name=es-$IMG_VERSION_ES-$formattedI
      - cluster.name=$ES_CLUSTER_NAME
EOM
    # 仅当 $ES_NODE_COUNT > 1 时添加 cluster 部分
    if [ "$ES_NODE_COUNT" -gt 1 ]; then
      cat >>"$docker_compose_file" <<-EOM
      - cluster.initial_master_nodes=$initial_master_nodes
      - discovery.seed_hosts=$seed_hosts
EOM
    else # 仅有一个节点时
      cat >>"$docker_compose_file" <<-EOM
      - discovery.type=single-node
EOM
    fi

    cat >>"$docker_compose_file" <<-EOM
      # Password for the 'elastic' user (at least 6 characters)
      - ELASTIC_PASSWORD=$ELASTIC_PASSWORD
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.key
      - xpack.security.http.ssl.certificate=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.crt
      - xpack.security.http.ssl.certificate_authorities=/usr/share/elasticsearch/config/ca.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.key
      - xpack.security.transport.ssl.certificate=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.crt
      - xpack.security.transport.ssl.certificate_authorities=/usr/share/elasticsearch/config/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.license.self_generated.type=$ES_LICENSE
      - xpack.ml.use_auto_machine_memory_percent=false
      $ES_JAVA_OPTS_ENV

    $MEM_LIMIT_ES 

    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert /usr/share/elasticsearch/config/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120
      start_period: 30s
    networks: # docker 网络设置
      $BRIDGE_ES: # 网络名称
          ipv4_address: $ip_node
EOM
  done

  # 删除历史数据 es
  if [ "$all_remove_data" == "y" ]; then

    # 删除历史数据
    sudo rm -rf "$DATA_VOLUME_DIR/es"

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # 创建新目录并复制初始配置
    copy_es_config "$is_kibana"

    log_info "已删除 es 历史数据"
  else
    log_info "未删除 es 历史数据"
  fi

  # ========================================================= es 结束

  # ========================================================= kibana 开始
  if [ "$is_kibana" == "y" ]; then
    cat >>"$docker_compose_file" <<-EOM
  # kibana 服务 
  kibana:
    depends_on:
EOM

    # 动态生成 depends_on 部分
    for ((i = 1; i <= ES_NODE_COUNT; i++)); do
      formattedI=$(printf "%02d" "$i")
      cat >>"$docker_compose_file" <<-EOM
      es-$IMG_VERSION_ES-$formattedI:
        condition: service_healthy
EOM
    done

    cat >>"$docker_compose_file" <<-EOM
    image: kibana:$IMG_VERSION_KIBANA
    container_name: kibana-$IMG_VERSION_KIBANA
    restart: always
    volumes:
      - $DATA_VOLUME_DIR/es/kibana/data:/usr/share/kibana/data
      - $DATA_VOLUME_DIR/es/kibana/config:/usr/share/kibana/config
    user: "$ES_UID:$ES_GID"
    ports:
      - $KIBANA_PORT:5601
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=https://es-$IMG_VERSION_ES-01:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=$KIBANA_PASSWORD
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/ca.crt
    $MEM_LIMIT_KIBANA
    
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s -I http://localhost:5601 | grep -q 'HTTP/1.1 302 Found'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120
      start_period: 30s

    networks: # 网络配置
      $BRIDGE_ES: # 网络名称
        ipv4_address: "$IPV4_BASE_ES.$(((ES_NODE_COUNT + 2) % 256))" # IP地址
EOM
  fi

  # 添加网络配置
  cat >>"$docker_compose_file" <<-EOM

networks: # 网络配置
  $BRIDGE_ES: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_ES # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_ES" # 子网
          gateway: "$GATEWAY_ES" # 网关
EOM

  # ========================================================= kibana 结束
}

# es kibana 并健康检查
health_check_db_es() {
  log_debug "run health_check_db_es"

  local es_container="" # 第一个 ES 节点容器名
  local kibana_password_masked=""

  es_container=$(get_runtime_es_container_name "$DOCKER_COMPOSE_FILE_ES" "01")
  log_warn "等待 Elasticsearch 启动, 这可能需要几分钟时间... 请勿中断！"

  # 通过 docker inspect 检查容器健康状态(依赖 docker-compose 中已配置的 healthcheck)
  until sudo docker inspect --format='{{.State.Health.Status}}' "$es_container" 2>/dev/null | grep -q 'healthy'; do
    # 等待 10 秒, 并显示动画
    waiting 10
  done

  log_info "Elasticsearch 启动完成"

  kibana_password_masked="${KIBANA_PASSWORD:0:3}***${KIBANA_PASSWORD: -3}"
  log_debug "设置 kibana_system 用户密码为 $kibana_password_masked"

  # 通过 docker exec 在容器内执行, 避免宿主机网络问题
  until sudo docker exec "$es_container" curl -s --cacert /usr/share/elasticsearch/config/ca.crt -u "elastic:$ELASTIC_PASSWORD" -X POST -H "Content-Type: application/json" "https://localhost:9200/_security/user/kibana_system/_password" -d "{\"password\":\"$KIBANA_PASSWORD\"}" 2>/dev/null | grep -q "^{}"; do
    # 等待 5 秒, 并显示动画
    waiting 5
  done
}

# 启动 es 容器
start_db_es() {
  log_debug "run start_db_es"

  local runtime_es_version=""

  runtime_es_version=$(get_docker_compose_image_version_or_default "$DOCKER_COMPOSE_FILE_ES" "elasticsearch" "$IMG_VERSION_ES")
  ensure_es_image_with_ik "$runtime_es_version" || return 1
  cleanup_es_legacy_plugin_runtime_files

  # 权限设置
  setup_directory "$ES_UID" "$ES_GID" 700 "$DATA_VOLUME_DIR/es" # 创建目录

  sudo docker compose -f "$DOCKER_COMPOSE_FILE_ES" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" up -d

  # 进行健康检查
  health_check_db_es
}

# 停止 es 容器
stop_db_es() {
  log_debug "run stop_db_es"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_ES" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" down || true
}

# 按当前 docker compose 直接重启 es 容器.
# 返回: 完成 down/up 与健康检查流程.
restart_db_es_by_compose() {
  log_debug "run restart_db_es_by_compose"

  restart_db_by_handlers "stop_db_es" "start_db_es"
}

# 判断 ES 是否发生版本降级.
# 参数: $1: 当前 es 版本.
# 参数: $2: 目标 es 版本.
# 返回: 目标版本低于当前版本时返回 0, 否则返回 1.
is_es_version_downgrade() {
  log_debug "run is_es_version_downgrade"

  local current_es_version="$1"
  local target_es_version="$2"
  local highest_version=""

  if [ -z "$current_es_version" ] || [ -z "$target_es_version" ]; then
    log_error "判断 ES 是否降级失败, 参数不能为空"
    return 1
  fi

  highest_version=$(printf "%s\n%s\n" "$current_es_version" "$target_es_version" | sort -V | tail -n 1)
  [ "$highest_version" == "$current_es_version" ] && [ "$current_es_version" != "$target_es_version" ]
}

# 处理 ES 版本降级时的数据兼容性.
# 参数: $1: 当前 es 版本.
# 参数: $2: 目标 es 版本.
# 返回: 无需降级或已清理数据时返回 0, 用户取消时返回非 0.
handle_es_downgrade_data() {
  log_debug "run handle_es_downgrade_data"

  local current_es_version="$1"
  local target_es_version="$2"
  local node_data_dir=""
  local clear_data_choice=""
  local has_node_data=false

  if ! is_es_version_downgrade "$current_es_version" "$target_es_version"; then
    return 0
  fi

  for node_data_dir in "$DATA_VOLUME_DIR"/es/node-*/data; do
    if [ -d "$node_data_dir" ]; then
      has_node_data=true
      break
    fi
  done

  if [ "$has_node_data" != true ]; then
    log_warn "检测到 ES 版本降级, 但未发现节点数据目录, 跳过数据清理"
    return 0
  fi

  clear_data_choice=$(read_user_input "\n检测到 es 从 $current_es_version 降级到 $target_es_version. Elasticsearch 不允许直接使用高版本节点数据降级启动.\n是否删除现有 es 节点数据后继续, 默认否 [y|n]: " "n")

  if [ "$clear_data_choice" != "y" ]; then
    log_error "已取消 ES 降级重启. 如需降级, 请确认删除现有 es 节点数据后重试"
    return 1
  fi

  for node_data_dir in "$DATA_VOLUME_DIR"/es/node-*/data; do
    [ -d "$node_data_dir" ] || continue
    sudo rm -rf "$node_data_dir"
    setup_directory "$ES_UID" "$ES_GID" 755 "$node_data_dir"
  done

  log_warn "已清空 ES 节点数据目录, 继续执行版本降级: $current_es_version -> $target_es_version"
}

# 同步 ES 的 IK 分词插件版本.
# 参数: $1: 当前 es 版本.
# 参数: $2: 目标 es 版本.
# 返回: 完成目标版本镜像构建, 并清理旧的运行期插件安装配置.
sync_es_ik_plugin_version() {
  log_debug "run sync_es_ik_plugin_version"

  local current_es_version="$1"
  local target_es_version="$2"

  if [ -z "$current_es_version" ] || [ -z "$target_es_version" ]; then
    log_error "同步 IK 分词插件版本失败, 参数不能为空"
    return 1
  fi

  if [ "$current_es_version" == "$target_es_version" ]; then
    log_info "IK 分词插件版本未变化, 跳过同步: $target_es_version"
    return 0
  fi

  ensure_es_image_with_ik "$target_es_version" || return 1
  cleanup_es_legacy_plugin_runtime_files

  log_info "已切换为构建期预装 IK 分词器镜像: $current_es_version -> $target_es_version"
}

# 同步 ES 的节点证书版本.
# 参数: $1: 当前 es 版本.
# 参数: $2: 目标 es 版本.
# 返回: 使用现有 CA 为各节点重新生成目标版本证书, 以匹配 compose 中的证书路径.
sync_es_cert_version() {
  log_debug "run sync_es_cert_version"

  local current_es_version="$1"
  local target_es_version="$2"
  local es_base_dir="$DATA_VOLUME_DIR/es"
  local ca_cert_file="$CA_CERT_DIR/ca.crt"
  local ca_key_file="$CA_CERT_DIR/ca.key"
  local node_dir=""
  local node_config_dir=""
  local formatted_i=""
  local target_cert_base=""
  local ip_node=""
  local generated_count=0

  if [ -z "$current_es_version" ] || [ -z "$target_es_version" ]; then
    log_error "同步 ES 证书版本失败, 参数不能为空"
    return 1
  fi

  if [ "$current_es_version" == "$target_es_version" ]; then
    log_info "ES 证书版本未变化, 跳过重新生成: $target_es_version"
    return 0
  fi

  gen_my_ca_cert

  for node_dir in "$es_base_dir"/node-*/; do
    [ -d "$node_dir" ] || continue

    formatted_i=$(basename "$node_dir" | sed 's/^node-//')
    node_config_dir="${node_dir}config"
    target_cert_base="es-$target_es_version-$formatted_i"
    ip_node="$IPV4_BASE_ES.$(((10#$formatted_i + 1) % 256))"

    if [ ! -d "$node_config_dir" ]; then
      log_warn "ES 节点证书目录不存在, 跳过证书生成: $node_config_dir"
      continue
    fi

    sudo rm -f "$node_config_dir/$target_cert_base.key" "$node_config_dir/$target_cert_base.crt"

    generate_instance_cert "$target_cert_base" \
      "$target_cert_base,localhost" \
      "127.0.0.1,$HOST_INTRANET_IP,$ip_node,$PUBLIC_IP_ADDRESS" \
      "$node_config_dir" \
      "$CERT_DAYS_VALID" \
      "$ca_cert_file" \
      "$ca_key_file"

    setup_directory "$ES_UID" "$ES_GID" 755 "$node_config_dir"
    generated_count=$((generated_count + 1))
  done

  if [ "$generated_count" -eq 0 ]; then
    log_warn "未找到可生成证书的 ES 节点目录, 跳过证书处理"
    return 0
  fi

  log_info "已为 $generated_count 个 ES 节点重新生成目标版本证书: $current_es_version -> $target_es_version"
}

# 替换 es 相关 docker compose 镜像版本.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 当前 es 版本.
# 参数: $3: 目标 es 版本.
# 返回: 完成 compose 文件中的全量版本替换, 并同步 IK 分词插件与证书版本.
replace_db_es_compose_version() {
  log_debug "run replace_db_es_compose_version"

  local docker_compose_file="$1"
  local current_es_version="$2"
  local target_es_version="$3"

  handle_es_downgrade_data "$current_es_version" "$target_es_version" || return 1
  sync_es_ik_plugin_version "$current_es_version" "$target_es_version"
  sync_es_cert_version "$current_es_version" "$target_es_version"
  replace_docker_compose_image_version "$docker_compose_file" "elasticsearch" "$current_es_version" "$target_es_version"
}

# 对比版本后重启 es 容器.
# 返回: 版本一致时直接重启; 版本不一致时先替换 compose 中镜像版本再重启.
restart_db_es() {
  log_debug "run restart_db_es"

  restart_db_with_version_choice \
    "es" \
    "$DOCKER_COMPOSE_FILE_ES" \
    "elasticsearch" \
    "$IMG_VERSION_ES" \
    "restart_db_es_by_compose" \
    "replace_db_es_compose_version" \
    "stop_db_es" \
    "start_db_es"
}

# 安装 es kibana
install_es_kibana() {
  log_debug "run install_es_kibana"

  # shellcheck disable=SC2329
  run() {
    # 创建目录
    mkdir_es_volume
    # 创建 docker-compose.yaml
    create_docker_compose_es

    # 启动服务
    start_db_es
  }

  log_timer "es 安装" run

  log_info "es 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 删除 es kibana
delete_es_kibana() {
  log_debug "run delete_es_kibana"

  local is_delete
  is_delete=$(read_user_input "确认停止 es 服务并删除数据吗(默认n) [y|n]? " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_es

    # 删除 es kibana 数据
    sudo rm -rf "$DATA_VOLUME_DIR/es"
  fi
}
