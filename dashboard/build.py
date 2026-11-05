# -*- coding: utf-8 -*-
"""把 ADS 层导出的 TSV 打包成单页看板 index.html。

数据来源：dashboard/data/*.tsv（由 beeline --outputformat=tsv2 导出，首行带列名）
输出：dashboard/index.html（数据内联，无外部依赖，可直接双击打开）
用法：python dashboard/build.py
"""
import io, json, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')

# 表名 -> 输出 key
TABLES = {
    'ads_gmv_summary': 'summary',
    'ads_daily_trend': 'daily',
    'ads_category_rank': 'category',
    'ads_channel_dist': 'channel',
    'ads_province_rank': 'province',
    'ads_user_value_seg': 'userSeg',
    'ads_member_level_compare': 'member',
    'ads_rfm_seg_summary': 'rfm',
    'ads_behavior_coverage': 'behavior',
    'ads_order_funnel': 'funnel',
    'ads_product_rank': 'product',
    'ads_store_efficiency': 'store',
}


def cast(v):
    """空值 -> None；能转数字就转（科学计数法也认）"""
    v = v.strip()
    if v == '' or v.upper() in ('NULL', '\\N'):
        return None
    try:
        f = float(v)
        return int(f) if f.is_integer() and abs(f) < 1e15 and '.' not in v and 'E' not in v.upper() else f
    except ValueError:
        return v


def load(name):
    path = os.path.join(DATA, name + '.tsv')
    if not os.path.exists(path):
        return []
    with io.open(path, encoding='utf-8') as f:
        lines = [l.rstrip('\n').rstrip('\r') for l in f if l.strip()]
    if not lines:
        return []
    header = [h.split('.', 1)[-1].strip() for h in lines[0].split('\t')]
    rows = []
    for line in lines[1:]:
        cells = line.split('\t')
        if len(cells) < len(header):
            cells += [''] * (len(header) - len(cells))
        rows.append({header[i]: cast(cells[i]) for i in range(len(header))})
    return rows


def main():
    data = {}
    for tbl, key in TABLES.items():
        rows = load(tbl)
        data[key] = rows[0] if key == 'summary' and rows else rows
    data['meta'] = {
        'built': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
        'tables': len(TABLES),
        'source': 'Hive 4.0 · ydsh_ads',
    }

    tpl_path = os.path.join(HERE, 'template.html')
    with io.open(tpl_path, encoding='utf-8') as f:
        html = f.read()
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    html = html.replace('__DATA__', payload)

    out = os.path.join(HERE, 'index.html')
    with io.open(out, 'w', encoding='utf-8') as f:
        f.write(html)

    size = os.path.getsize(out) / 1024
    counts = {k: (1 if isinstance(v, dict) else len(v)) for k, v in data.items() if k != 'meta'}
    print('written', out, round(size, 1), 'KB')
    print(counts)


if __name__ == '__main__':
    main()
