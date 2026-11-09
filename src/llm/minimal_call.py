# -*- coding: utf-8 -*-
"""
第 3 周 子任务 3：最小化大模型调用验证（连通性 + 返回格式）
----------------------------------------------------------
运行：python src/llm/minimal_call.py
验证通过标准（任务书）：能成功返回一次大模型回复。
无 Key 时打印配置自检结果并给出接入指引（退出码 1，不泄露任何密钥内容）。
"""
import sys

from llm_config import chat, get_llm_config


def main() -> int:
    cfg = get_llm_config()
    key_state = "已配置(长度 %d)" % len(cfg.api_key) if cfg.api_key else "未配置"
    print(f"平台: {cfg.platform} | 模型: {cfg.model or '-'} | "
          f"base_url: {cfg.base_url or '-'} | Key: {key_state}")

    if cfg.platform == "none":
        print("\n[dry-run] 未检测到 API Key，跳过真实调用。")
        print("接入步骤：cp src/llm/.env.example .env → 填入真实 Key → 重跑本脚本")
        return 1

    reply = chat([
        {"role": "system", "content": "你是经营分析助手，回答保持简洁。"},
        {"role": "user", "content": "用一句话说明什么是客单价（AOV）。"},
    ])
    print(f"\n模型回复：{reply}")
    print(f"\n验证通过：连通性 OK，返回为文本（长度 {len(reply)} 字符）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
