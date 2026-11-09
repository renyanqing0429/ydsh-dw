# -*- coding: utf-8 -*-
"""
第 3 周 子任务 3：大模型 API 统一接入与密钥安全管理
----------------------------------------------------
安全规范（任务书要求）：
  1. API Key 一律放项目根目录 .env 文件，通过环境变量读取，严禁硬编码进源码；
  2. .env 已列入 .gitignore，不会进入版本库；
  3. 统一适配多平台（DeepSeek / 通义千问 / 文心一言，均为 OpenAI 兼容接口）。
"""
import os
from dataclasses import dataclass

from dotenv import load_dotenv

# 从项目根目录加载 .env
_BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
load_dotenv(os.path.join(_BASE, ".env"))


@dataclass
class LLMConfig:
    platform: str
    api_key: str
    base_url: str
    model: str


def get_llm_config() -> LLMConfig:
    """按优先级读取平台配置：DeepSeek > 通义千问 > 文心一言。

    密钥只从环境变量读取；找不到任何可用配置时返回 platform='none'，
    调用方（nl2sql / insight）据此进入 dry-run 模式，程序不崩溃。
    """
    if os.environ.get("DEEPSEEK_API_KEY"):
        return LLMConfig("deepseek", os.environ["DEEPSEEK_API_KEY"],
                         os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
                         os.environ.get("DEEPSEEK_MODEL", "deepseek-chat"))
    if os.environ.get("QWEN_API_KEY"):
        return LLMConfig("qwen", os.environ["QWEN_API_KEY"],
                         os.environ.get("QWEN_BASE_URL",
                                        "https://dashscope.aliyuncs.com/compatible-mode/v1"),
                         os.environ.get("QWEN_MODEL", "qwen-plus"))
    if os.environ.get("ERNIE_API_KEY"):
        return LLMConfig("ernie", os.environ["ERNIE_API_KEY"],
                         os.environ.get("ERNIE_BASE_URL", "https://qianfan.baidubce.com/v2"),
                         os.environ.get("ERNIE_MODEL", "ernie-4.0-8k"))
    return LLMConfig("none", "", "", "")


def chat(messages: list, temperature: float = 0.1, max_tokens: int = 1024) -> str:
    """统一的大模型对话入口（OpenAI 兼容协议）。无 Key 时抛 RuntimeError。"""
    cfg = get_llm_config()
    if cfg.platform == "none":
        raise RuntimeError(
            "未检测到可用的 API Key：请复制 src/llm/.env.example 为项目根目录 .env 并填入真实 Key")
    from openai import OpenAI
    client = OpenAI(api_key=cfg.api_key, base_url=cfg.base_url)
    resp = client.chat.completions.create(
        model=cfg.model, messages=messages,
        temperature=temperature, max_tokens=max_tokens)
    return resp.choices[0].message.content.strip()
