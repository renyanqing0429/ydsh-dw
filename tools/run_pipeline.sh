#!/usr/bin/env bash
# 一键执行第1周数据流水线：启动容器 -> 建库建表 -> 导入 -> 质量扫描 -> 清洗
# 用法：bash tools/run_pipeline.sh [create|load|quality|clean|all]
set -u

cd "$(dirname "$0")/.." || exit 1
STEP="${1:-all}"

export PATH="$PATH:/c/Program Files/Docker/Docker/resources/bin"
if ! docker info >/dev/null 2>&1; then
  echo "[错误] Docker 引擎未运行，请先启动 Docker Desktop"
  exit 1
fi

BEELINE="docker exec hive-server beeline -u jdbc:hive2://localhost:10000 --silent=true --outputformat=tsv2"

wait_hive() {
  echo "[1/6] 启动容器..."
  docker compose up -d
  echo "[2/6] 等待 HiveServer2 就绪（最长 5 分钟）..."
  for i in $(seq 1 60); do
    if docker exec hive-server bash -c 'echo > /dev/tcp/localhost/10000' 2>/dev/null; then
      echo "      HiveServer2 已就绪（~$((i*5))s）"
      return 0
    fi
    sleep 5
  done
  echo "[警告] HiveServer2 未在预期时间内就绪，请查看 docker logs hive-server"
  return 1
}

run_sql() {
  local file="$1" desc="$2"
  echo "  -> $desc ($file)"
  $BEELINE -f "$file"
}

mkdir -p "docs/执行结果"

case "$STEP" in
  create|all)
    wait_hive || exit 1
    echo "[3/6] 建库建表..."
    run_sql /sql/ods/create_ods.sql "ODS 建表" | tee docs/执行结果/01_建表结果.txt
    ;;
esac

case "$STEP" in
  load|all)
    echo "[4/6] 导入数据并校验行数..."
    run_sql /sql/ods/load_data.sql "数据加载" | tee docs/执行结果/02_导入结果.txt
    ;;
esac

case "$STEP" in
  quality|all)
    echo "[5/6] 数据质量预评估..."
    run_sql /sql/quality/quality_check.sql "五维度扫描" | tee docs/执行结果/03_质量扫描结果.txt
    ;;
esac

case "$STEP" in
  clean|all)
    echo "[6/6] 缺失值与重复值清洗..."
    run_sql /sql/clean/missing_values.sql "缺失值处理" | tee docs/执行结果/04_缺失值处理结果.txt
    run_sql /sql/clean/dedup.sql "重复值去重" | tee docs/执行结果/05_去重结果.txt
    ;;
esac

echo "完成。"
