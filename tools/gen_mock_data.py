#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
生成 ODS 层 6 张表的模拟 CSV（含任务书描述的各类脏数据），用于本地跑通数据导入与清洗流程。
行数严格对齐《第1周部署操作手册》的预期行数。

⚠️ 这是自造模拟数据：官方《模拟数据字典》下发后，请用官方 CSV 替换 data/ 下同名文件。
"""
import csv
import os
import random

random.seed(20261026)

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
os.makedirs(OUT_DIR, exist_ok=True)

PROVINCES = {
    "山东省": ["青岛市", "济南市", "烟台市", "潍坊市"],
    "江苏省": ["南京市", "苏州市", "无锡市", "徐州市"],
    "浙江省": ["杭州市", "宁波市", "温州市"],
    "广东省": ["深圳市", "广州市", "东莞市", "佛山市"],
    "四川省": ["成都市", "绵阳市"],
}
PROV_LIST = [(p, c) for p, cs in PROVINCES.items() for c in cs]

CATEGORIES = ["休闲零食", "乳品饮料", "生鲜果蔬", "粮油调味", "日用百货", "个护清洁"]
PAY_TYPES = ["wxpay", "alipay", "cash", "card"]
ORDER_STATUS = ["pending", "paid", "shipped", "done", "cancelled"]
CHANNELS = ["app", "mini_program", "h5", "store"]
ACTIONS = ["view", "cart", "buy", "fav"]
LEVELS = ["普通会员", "银卡", "金卡", "钻石"]
STORE_TYPES = ["直营店", "加盟店", "前置仓"]


def d(y, m, dd):
    return f"{y:04d}-{m:02d}-{dd:02d}"


def write_csv(name, header, rows):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"{name}: {len(rows)} 行 -> {path}")


# ---------------- 1. ods_user 1000 ----------------
user_rows = []
for i in range(1, 1001):
    uid = f"U{i:06d}"
    name = f"用户{i:04d}"
    # 性别：少量脏值（M/F/空）
    r = random.random()
    gender = "男" if r < 0.48 else "女" if r < 0.96 else random.choice(["M", "F", ""])
    # 年龄：5% 空、2% 负数、1% 超 120
    ra = random.random()
    if ra < 0.05:
        age = ""
    elif ra < 0.07:
        age = random.choice([-1, -5, -18])
    elif ra < 0.08:
        age = random.choice([130, 150, 200])
    else:
        age = random.randint(16, 72)
    prov, city = random.choice(PROV_LIST)
    reg = d(random.randint(2021, 2025), random.randint(1, 12), random.randint(1, 28))
    level = random.choices(LEVELS, weights=[60, 25, 12, 3])[0]
    phone = f"1{random.choice(['3', '5', '7', '8', '9'])}{random.randint(0, 999999999):09d}"
    if random.random() < 0.02:
        phone = random.choice(["12345", "", "1380013800", "abc12345678"])
    email = f"user{i:04d}@{random.choice(['qq.com', '163.com', 'gmail.com'])}"
    if random.random() < 0.08:
        email = ""
    user_rows.append([uid, name, gender, age, city, prov, reg, level, phone, email])

write_csv(
    "ods_user.csv",
    ["user_id", "user_name", "gender", "age", "city", "province",
     "register_date", "member_level", "phone", "email"],
    user_rows,
)

# ---------------- 2. ods_product 600 ----------------
product_rows = []
for i in range(1, 601):
    pid = f"P{i:05d}"
    cat = random.choice(CATEGORIES)
    price = round(random.uniform(5, 500), 2)
    r = random.random()
    if r < 0.03:
        price = ""
    elif r < 0.05:
        price = round(-random.uniform(1, 50), 2)
    stock = random.randint(0, 2000)
    # 状态：少量非法枚举
    status = random.choices(["在售", "下架", "缺货"], weights=[75, 18, 7])[0]
    if random.random() < 0.03:
        status = random.choice(["ON_SALE", "1", "在售中"])
    launch = d(random.randint(2022, 2025), random.randint(1, 12), random.randint(1, 28))
    if random.random() < 0.06:
        launch = ""
    product_rows.append([pid, f"{cat}商品{i:04d}", cat, price, stock, status, launch])

write_csv(
    "ods_product.csv",
    ["product_id", "product_name", "category", "price", "stock", "status", "launch_date"],
    product_rows,
)

# ---------------- 3. ods_store 60 ----------------
store_rows = []
for i in range(1, 61):
    prov, city = random.choice(PROV_LIST)
    store_rows.append([
        f"S{i:03d}", f"{city}{random.choice(['万象城', '万达', '印象城', '中心'])}店",
        city, prov,
        d(random.randint(2018, 2025), random.randint(1, 12), random.randint(1, 28)),
        random.choice(STORE_TYPES),
    ])
write_csv("ods_store.csv",
          ["store_id", "store_name", "city", "province", "open_date", "store_type"],
          store_rows)

# ---------------- 4. ods_order 15600 ----------------
# 先生成唯一订单，再人为制造重复（整行重复 + 主键重复内容不同）
order_rows = []
order_ids = []
for i in range(1, 15001):
    oid = f"O{2025000000 + i}"
    uid = f"U{random.randint(1, 1000):06d}"
    sid = f"S{random.randint(1, 60):03d}"
    od = d(2025, random.randint(1, 12), random.randint(1, 28))
    ot = f"{random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}"
    amount = round(random.uniform(9.9, 3000), 2)
    if random.random() < 0.03:
        amount = ""
    elif random.random() < 0.02:
        amount = round(-random.uniform(1, 500), 2)
    discount = round(random.uniform(0, 200), 2)
    order_rows.append([
        oid, uid, sid, od, ot, amount, discount,
        random.choices(PAY_TYPES, weights=[45, 35, 12, 8])[0],
        random.choices(ORDER_STATUS, weights=[10, 25, 20, 40, 5])[0],
        random.choice(CHANNELS),
    ])
    order_ids.append(oid)

# 追加 400 条整行完全重复
for _ in range(300):
    order_rows.append(list(random.choice(order_rows)))
# 追加 300 条主键重复但内容不同（金额/状态不同，时间更晚 = 最新记录）
for _ in range(300):
    src = list(random.choice(order_rows[:15000]))
    src[5] = round(random.uniform(9.9, 3000), 2)
    src[8] = "cancelled"
    src[4] = "23:59:59"
    order_rows.append(src)

random.shuffle(order_rows)
write_csv("ods_order.csv",
          ["order_id", "user_id", "store_id", "order_date", "order_time",
           "pay_amount", "discount_amount", "pay_type", "order_status", "channel"],
          order_rows)

# ---------------- 5. ods_order_item 37549 ----------------
item_rows = []
ITEM_N = 37549
for i in range(1, ITEM_N + 1):
    oid = random.choice(order_ids)
    pid = f"P{random.randint(1, 600):05d}"
    qty = random.randint(1, 5)
    price = round(random.uniform(5, 500), 2)
    item_rows.append([f"I{i:07d}", oid, pid, qty, price, round(qty * price, 2)])
write_csv("ods_order_item.csv",
          ["item_id", "order_id", "product_id", "quantity", "unit_price", "amount"],
          item_rows)

# ---------------- 6. ods_user_behavior 60000 ----------------
beh_rows = []
for i in range(1, 60001):
    ts_day = d(2025, random.randint(1, 12), random.randint(1, 28))
    ts = f"{ts_day} {random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}"
    beh_rows.append([
        f"B{i:07d}", f"U{random.randint(1, 1000):06d}", f"P{random.randint(1, 600):05d}",
        random.choices(ACTIONS, weights=[65, 18, 9, 8])[0], ts,
    ])
write_csv("ods_user_behavior.csv",
          ["behavior_id", "user_id", "product_id", "action", "action_time"],
          beh_rows)

print("\n完成：模拟数据已生成到 data/ 目录")
