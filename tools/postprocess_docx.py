#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""docx 印刷细节后处理（在 html-to-doc 转换之后执行）：

1. 补 A4 页面尺寸（11906 x 16838 twips），转换器只写了页边距没写纸张大小；
2. 封面独立成页：在封面署名段落之后插入分页符；
3. 表格首行设为「标题行重复」，所有行禁止跨页断行（长表跨页时表头不丢）。

只改 word/document.xml，其余部件原样回写，不破坏可编辑性。
"""
import re
import shutil
import sys
import zipfile

BREAK_P = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
PG_SZ = '<w:pgSz w:w="11906" w:h="16838"/>'


def add_page_size(xml: str) -> str:
    if '<w:pgSz' in xml:
        return xml
    return xml.replace('<w:sectPr>', '<w:sectPr>' + PG_SZ, 1)


def add_cover_break(xml: str, anchor: str) -> str:
    if 'w:type="page"' in xml:
        return xml
    for m in re.finditer(r'<w:p [^>]*>.*?</w:p>', xml, re.S):
        txt = ''.join(re.findall(r'<w:t[^>]*>([^<]*)</w:t>', m.group(0)))
        if anchor in txt:
            return xml[:m.end()] + BREAK_P + xml[m.end():]
    return xml


def fix_tables(xml: str) -> str:
    def repl(m):
        tr = m.group(0)
        if '<w:trPr>' in tr:
            return tr
        # 仅首个数据行需要 tblHeader，统一标记由外层处理
        return tr.replace('<w:tr>', '<w:tr><w:trPr><w:cantSplit/></w:trPr>', 1)

    xml = re.sub(r'<w:tr>.*?</w:tr>', repl, xml, flags=re.S)

    # 每个表格第一行加 tblHeader
    out, pos = [], 0
    for t in re.finditer(r'<w:tbl>.*?</w:tbl>', xml, re.S):
        tbl = t.group(0)
        first = re.search(r'<w:tr>.*?</w:tr>', tbl, re.S)
        if first and 'tblHeader' not in tbl:
            new_tr = first.group(0).replace('<w:cantSplit/>', '<w:tblHeader/><w:cantSplit/>', 1)
            tbl = tbl.replace(first.group(0), new_tr, 1)
        out.append(xml[pos:t.start()])
        out.append(tbl)
        pos = t.end()
    out.append(xml[pos:])
    return ''.join(out)


def process(path: str, anchor: str) -> None:
    tmp = path + '.tmp'
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == 'word/document.xml':
                xml = data.decode('utf-8')
                xml = add_page_size(xml)
                xml = add_cover_break(xml, anchor)
                xml = fix_tables(xml)
                data = xml.encode('utf-8')
            zout.writestr(item, data)
    shutil.move(tmp, path)

    with zipfile.ZipFile(path) as z:
        xml = z.read('word/document.xml').decode('utf-8')
    print(f'{path}  分页符={xml.count(chr(34).join(["w:type=", "page"]))}  '
          f'A4={"<w:pgSz" in xml}  tblHeader={xml.count("tblHeader")}  '
          f'cantSplit={xml.count("cantSplit")}')


if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '任宴庆')
