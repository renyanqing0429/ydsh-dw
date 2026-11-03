#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Markdown -> 带封面与 A4 排版的 HTML（供 html-to-doc 的 convert_doc.py 转 docx）。

支持：# ~ #### 标题、管道表格（含对齐）、围栏代码、引用、有序/无序列表、
行内 **粗体** / `代码` / ⚠️；另外把文档里的两处 ASCII 图（四层架构、星型模型）
替换为表格化的框图，避免在 Word 里用等宽字符拼图对不齐。
"""
import io
import os
import re
import sys

# ---------- 行内格式 ----------
def inline(t: str) -> str:
    t = (t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))
    t = re.sub(r'`([^`]+)`', r'<span style="font-family:Consolas,\'Courier New\',monospace;'
                             r'font-size:9.5pt;color:#8a3324;">\1</span>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'(?<!\*)\*([^*\n]+)\*(?!\*)', r'<em>\1</em>', t)
    return t


TD = 'style="border:1px solid #bfbfbf;padding:5px 7px;font-size:9.5pt;line-height:1.5;vertical-align:middle;"'
TH = ('style="border:1px solid #bfbfbf;padding:5px 7px;font-size:9.5pt;font-weight:bold;'
      'background:#eef2f7;line-height:1.5;vertical-align:middle;"')


def align_style(spec: str) -> str:
    spec = spec.strip()
    if spec.endswith(':') and spec.startswith(':'):
        return 'center'
    if spec.endswith(':'):
        return 'right'
    return 'left'


# ---------- 表格化框图 ----------
def box(text_html: str, bg: str, border: str, extra: str = '') -> str:
    return (f'<table style="border-collapse:collapse;width:100%;margin:0;"><tr>'
            f'<td style="border:1.2pt solid {border};background:{bg};padding:9px 12px;'
            f'font-size:9.5pt;line-height:1.6;{extra}">{text_html}</td></tr></table>')


ARROW = ('<p style="margin:3px 0;text-align:center;font-size:9pt;color:#666666;'
         'line-height:1.3;">▼</p>')


def diagram_arch() -> str:
    layers = [
        ('ODS 贴源层', 'ydsh_ods.ods_*', '#F2F5F9', '#5B7B9A',
         '原样接入，不做业务加工，保留原始脏数据证据；TEXTFILE，全量快照'),
    ]
    parts = [box('<strong>ODS 贴源层</strong>　<span style="color:#555">ydsh_ods.ods_*</span><br/>'
                 '<span style="font-size:9pt">定位：原样接入，不做任何业务加工，保留原始脏数据证据<br/>'
                 '粒度：最细粒度（原始行）　｜　存储：TEXTFILE　｜　生命周期：全量快照</span>',
                 '#F2F5F9', '#5B7B9A')]
    parts.append(ARROW.replace('▼', '▼　清洗：缺失值填充 / 去重 / 枚举标准化 / 异常值修正 / 格式统一'))
    parts.append(box('<strong>STG 清洗中间层</strong>　<span style="color:#555">ydsh_dwd.stg_*</span>'
                     '（本项目为便于复盘而增设）<br/>'
                     '<span style="font-size:9pt">定位：承接 ODS → DWD 的清洗过程，分步骤落中间结果，可逐步验证<br/>'
                     '粒度：同 ODS　｜　存储：默认格式　｜　可随时重跑</span>',
                     '#FAF7F0', '#B39B6E'))
    parts.append(ARROW.replace('▼', '▼　建模：星型模型、维度退化与编码映射'))
    parts.append(box('<strong>DWD 明细层</strong>　<span style="color:#555">ydsh_dwd.dwd_* / dim_*</span><br/>'
                     '<span style="font-size:9pt">定位：清洗 + 标准化 + 维度关联后的明细数据，全仓库唯一事实来源<br/>'
                     '粒度：事务粒度（订单 / 明细 / 行为）　｜　存储：ORC　｜　分区：按日期</span>',
                     '#EAF1EA', '#5F8A5F'))
    parts.append(ARROW.replace('▼', '▼　汇总：按主题域轻度聚合（日 / 周 / 月 + 维度）'))
    parts.append(box('<strong>DWS 汇总层</strong>　<span style="color:#555">ydsh_dws.dws_*</span>'
                     '（第 3 周落地，本期完成设计）<br/>'
                     '<span style="font-size:9pt">定位：面向分析主题的宽表，一次加工多次复用，降低 ADS 计算成本<br/>'
                     '粒度：日 / 周 / 月 + 维度组合　｜　存储：ORC + 分区</span>',
                     '#EDEFF7', '#6B6F9C'))
    parts.append(ARROW.replace('▼', '▼　应用：指标口径固化、报表直读'))
    parts.append(box('<strong>ADS 应用层</strong>　<span style="color:#555">ydsh_ads.ads_*</span>'
                     '（第 4 周落地，本期完成设计）<br/>'
                     '<span style="font-size:9pt">定位：面向报表与可视化的结果表，一行即一个指标<br/>'
                     '粒度：指标级　｜　存储：ORC（小结果集可导 MySQL 供 BI 直连）</span>',
                     '#F7EEEE', '#9C6B6B'))
    parts.append(ARROW)
    parts.append('<p style="text-align:center;font-size:10pt;margin:4px 0;">'
                 '<strong>经营分析看板</strong>（可视化 / 报表 / 大屏）</p>')
    return '<div style="margin:10px 0 14px 0;">' + ''.join(parts) + '</div>'


def diagram_star() -> str:
    tbl = (
        '<table border="1" cellspacing="0" cellpadding="4" style="border-collapse:collapse;width:100%;font-size:9.5pt;">'
        f'<tr><td {TH} width="26%">维度表</td><td {TH} width="30%">关联键</td>'
        f'<td {TH} width="44%">事实表</td></tr>'
        f'<tr><td {TD}>dim_user（1,000 行）</td><td {TD}>user_id</td>'
        f'<td {TD} rowspan="2"><strong>dwd_order</strong>（订单粒度，15,000 行）<br/>'
        '<span style="font-size:9pt">分区 order_date（366 个）</span></td></tr>'
        f'<tr><td {TD}>dim_store（60 行）</td><td {TD}>store_id</td></tr>'
        f'<tr><td {TD}>dim_date（366 行）</td><td {TD}>order_date → date_id</td>'
        f'<td {TD}>同上（时间维度直接挂分区字段）</td></tr>'
        f'<tr><td {TD}>dim_user</td><td {TD}>user_id</td>'
        f'<td {TD} rowspan="2"><strong>dwd_user_behavior</strong>（行为粒度，60,000 行）<br/>'
        '<span style="font-size:9pt">分区 behavior_date；另建 8 桶分桶版本</span></td></tr>'
        f'<tr><td {TD}>dim_product（600 行）</td><td {TD}>product_id</td></tr>'
        f'<tr><td {TD}>dim_product</td><td {TD}>product_id</td>'
        f'<td {TD}><strong>dwd_order_item</strong>（商品粒度，37,549 行）<br/>'
        '<span style="font-size:9pt">分区 order_date；通过 order_id 上挂 dwd_order</span></td></tr>'
        '</table>'
    )
    return ('<div style="margin:8px 0 14px 0;">'
            '<p style="font-size:9pt;color:#666;margin:0 0 6px 0;">星型模型：三张事实表共享四张维度表，'
            '维度表只存描述属性，度量全部落在事实表。</p>' + tbl + '</div>')


def maybe_diagram(code: str):
    if 'ODS 贴源层' in code and 'ADS 应用层' in code:
        return diagram_arch()
    if 'dim_date' in code and 'dwd_order' in code:
        return diagram_star()
    return None


# ---------- 主体解析 ----------
def convert(md: str) -> tuple:
    lines = md.split('\n')
    title, subtitle = '', ''
    meta = []
    body_start = 0

    # 1) 找标题；2) 紧后续的引用块作为封面元信息
    for i, ln in enumerate(lines):
        if ln.startswith('# ') and not title:
            raw = ln[2:].strip()
            if '——' in raw:
                a, b = raw.split('——', 1)
                subtitle, title = a.strip(), b.strip()
            else:
                title = raw
            body_start = i + 1
            break

    j = body_start
    while j < len(lines) and not lines[j].strip():
        j += 1
    while j < len(lines) and lines[j].strip().startswith('>'):
        text = lines[j].strip().lstrip('>').strip().replace('\u3000', ' ').strip()
        if text:
            meta.append(text)
        j += 1
    body_start = j

    out = []
    i = body_start
    n = len(lines)
    while i < n:
        ln = lines[i]
        s = ln.rstrip()

        if not s.strip():
            i += 1
            continue

        if s.startswith('---'):
            i += 1
            continue

        # 围栏代码
        if s.lstrip().startswith('```'):
            i += 1
            buf = []
            while i < n and not lines[i].lstrip().startswith('```'):
                buf.append(lines[i])
                i += 1
            i += 1
            code = '\n'.join(buf)
            dg = maybe_diagram(code)
            if dg:
                out.append(dg)
            else:
                out.append('<div style="border:1px solid #d5d5d5;background:#f7f7f7;'
                           'padding:8px 10px;margin:8px 0 12px 0;">'
                           '<pre style="margin:0;font-family:Consolas,\'Courier New\',monospace;'
                           'font-size:9pt;line-height:1.45;white-space:pre-wrap;">'
                           + inline(code) + '</pre></div>')
            continue

        # 标题
        m = re.match(r'^(#{2,4})\s+(.*)$', s)
        if m:
            level = len(m.group(1))
            txt = inline(m.group(2).strip())
            if level == 2:
                out.append(f'<h2 style="font-family:\'Microsoft YaHei\',sans-serif;font-size:15pt;'
                           f'color:#1f3b57;margin:20px 0 8px 0;padding-bottom:4px;'
                           f'border-bottom:1.5pt solid #1f3b57;">{txt}</h2>')
            elif level == 3:
                out.append(f'<h3 style="font-family:\'Microsoft YaHei\',sans-serif;font-size:12.5pt;'
                           f'color:#2c5b82;margin:14px 0 6px 0;">{txt}</h3>')
            else:
                out.append(f'<h4 style="font-family:\'Microsoft YaHei\',sans-serif;font-size:11pt;'
                           f'color:#333;margin:10px 0 4px 0;">{txt}</h4>')
            i += 1
            continue

        # 表格
        if s.startswith('|') and i + 1 < n and re.match(r'^\|[\s:|-]+\|$', lines[i + 1].strip()):
            header = [c.strip() for c in s.strip().strip('|').split('|')]
            specs = [c.strip() for c in lines[i + 1].strip().strip('|').split('|')]
            aligns = [align_style(x) for x in specs]
            i += 2
            rows = []
            while i < n and lines[i].strip().startswith('|'):
                rows.append([c.strip() for c in lines[i].strip().strip('|').split('|')])
                i += 1
            t = ['<table border="1" cellspacing="0" cellpadding="4" style="border-collapse:collapse;width:100%;margin:8px 0 12px 0;">']
            t.append('<tr>' + ''.join(
                f'<td {TH} style="border:1px solid #bfbfbf;padding:5px 7px;font-size:9.5pt;'
                f'font-weight:bold;background:#eef2f7;text-align:{aligns[k] if k < len(aligns) else "left"};">'
                f'{inline(h)}</td>' for k, h in enumerate(header)) + '</tr>')
            for r in rows:
                cells = []
                for k, c in enumerate(r):
                    al = aligns[k] if k < len(aligns) else 'left'
                    cells.append(f'<td style="border:1px solid #bfbfbf;padding:5px 7px;'
                                 f'font-size:9.5pt;line-height:1.5;text-align:{al};">{inline(c)}</td>')
                t.append('<tr>' + ''.join(cells) + '</tr>')
            t.append('</table>')
            out.append(''.join(t))
            continue

        # 引用
        if s.startswith('>'):
            buf = []
            while i < n and lines[i].strip().startswith('>'):
                buf.append(inline(lines[i].strip()[1:].strip()))
                i += 1
            out.append('<div style="border-left:3pt solid #9ab;background:#f6f8fa;'
                       'padding:8px 12px;margin:10px 0 12px 0;font-size:9.5pt;color:#444;">'
                       + '<br/>'.join(x for x in buf if x) + '</div>')
            continue

        # 列表
        if re.match(r'^\s*([-*]|\d+\.)\s+', s):
            ordered = bool(re.match(r'^\s*\d+\.\s+', s))
            items = []
            while i < n and re.match(r'^\s*([-*]|\d+\.)\s+', lines[i]):
                body = re.sub(r'^\s*([-*]|\d+\.)\s+', '', lines[i])
                items.append(inline(body.strip()))
                i += 1
            tag = 'ol' if ordered else 'ul'
            lis = ''.join(f'<li style="margin:2px 0;line-height:1.6;">{x}</li>' for x in items)
            out.append(f'<{tag} style="margin:6px 0 10px 0;padding-left:22px;font-size:10pt;">{lis}</{tag}>')
            continue

        # 普通段落（合并连续行）
        buf = [s.strip()]
        i += 1
        while i < n and lines[i].strip() and not re.match(
                r'^(#{2,4}\s|\||>\s*```|\s*([-*]|\d+\.)\s)', lines[i]) and not lines[i].lstrip().startswith('```'):
            buf.append(lines[i].strip())
            i += 1
        out.append(f'<p style="margin:6px 0 10px 0;font-size:10pt;line-height:1.75;text-align:justify;text-indent:2em;">'
                   f'{inline(" ".join(buf))}</p>')

    return title, subtitle, meta, '\n'.join(out)


def build(title, subtitle, meta, body, footer):
    meta_rows = []
    for m in meta:
        if '：' in m:
            k, v = m.split('：', 1)
        elif ':' in m:
            k, v = m.split(':', 1)
        else:
            continue
        meta_rows.append(f'<tr><td style="border:none;padding:3px 14px 3px 0;font-size:9.5pt;'
                         f'color:#666;white-space:nowrap;">{inline(k.strip())}</td>'
                         f'<td style="border:none;padding:3px 0;font-size:9.5pt;">{inline(v.strip())}</td></tr>')
    meta_tbl = ('<table style="border-collapse:collapse;margin:34px 0 0 0;">'
                + ''.join(meta_rows) + '</table>') if meta_rows else ''

    cover = (
        '<div style="padding-top:96px;">'
        '<p style="font-size:10pt;color:#5b7b9a;letter-spacing:2px;margin:0 0 10px 0;">'
        '企业项目实战实训　·　第 2 周</p>'
        f'<p style="font-size:24pt;font-weight:bold;color:#1f3b57;margin:0 0 10px 0;'
        f'font-family:\'Microsoft YaHei\',sans-serif;line-height:1.35;">{inline(title)}</p>'
        f'<p style="font-size:11pt;color:#555;margin:0 0 6px 0;">{inline(subtitle)}</p>'
        '<div style="width:80px;height:3pt;background:#1f3b57;margin:18px 0 0 0;"></div>'
        + meta_tbl +
        f'<p style="font-size:9.5pt;color:#777;margin:56px 0 0 0;">{inline(footer)}</p>'
        '</div>'
        '<div style="page-break-after:always;"></div>'
    )
    css = (
        '@page { size: A4; margin: 2.2cm 2.0cm; }'
        'body { font-family: "Microsoft YaHei", "微软雅黑", sans-serif; font-size: 10pt;'
        ' line-height: 1.75; color: #222; }'
        'table { border-collapse: collapse; }'
        'td, th { word-break: break-word; }'
    )
    return (
        '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"/>'
        f'<title>{title}</title><style>{css}</style></head><body>'
        + cover
        + f'<div style="font-family:\'Microsoft YaHei\',sans-serif;">{body}</div>'
        + '</body></html>'
    )


def main():
    src, dst, footer = sys.argv[1], sys.argv[2], sys.argv[3]
    md = io.open(src, encoding='utf-8').read()
    title, subtitle, meta, body = convert(md)
    html = build(title, subtitle, meta, body, footer)
    io.open(dst, 'w', encoding='utf-8').write(html)
    print(f'OK {os.path.basename(dst)}  title={title}  meta={len(meta)}  body={len(body)}')


if __name__ == '__main__':
    main()
