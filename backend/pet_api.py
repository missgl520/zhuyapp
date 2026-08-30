"""
竹芽宠物后端 - FastAPI + 多 LLM Provider
Pet Bot Backend - AI Chat + Lyrics Creator + Music Generator
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, Literal
import httpx
import os
import json
import asyncio
import random
import re
from datetime import datetime
from lyrics_store import save as ls_save, get as ls_get, list_ as ls_list, delete as ls_delete, update_tags as ls_update_tags, stats as ls_stats, export_json as ls_export

# ═══════════════════════════════════════════════
# LLM Provider 配置（支持多 provider 自动 failover）
# ═══════════════════════════════════════════════
# 用法: 设置 LLM_PROVIDER=groq (或 cerebras/gemini/ace)
# API Key: GROQ_API_KEY / CEREBRAS_API_KEY / GEMINI_API_KEY / ACE_MUSIC_API_KEY

ACTIVE_PROVIDER = os.getenv("LLM_PROVIDER", "groq")

LLM_PROVIDERS = {
    "groq": {
        "name": "Groq",
        "base_url": "https://api.groq.com/openai/v1",
        "model": "llama-3.3-70b-versatile",
        "api_key": os.getenv("GROQ_API_KEY", ""),
        "timeout": 30.0,
        "limit": "~1000 req/day, 30 req/min",
    },
    "cerebras": {
        "name": "Cerebras",
        "base_url": "https://api.cerebras.ai/v1",
        "model": "llama-3.3-70b",
        "api_key": os.getenv("CEREBRAS_API_KEY", ""),
        "timeout": 30.0,
        "limit": "~1M tokens/day",
    },
    "gemini": {
        "name": "Google Gemini",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/openai/",
        "model": "gemini-2.0-flash",
        "api_key": os.getenv("GEMINI_API_KEY", ""),
        "timeout": 30.0,
        "limit": "~1500 req/day",
    },
    "ace": {
        "name": "ACE Music",
        "base_url": "https://api.acemusic.ai/v1/chat/completions",
        "model": "auto",
        "api_key": os.getenv("ACE_MUSIC_API_KEY", "c2fa5ed9b9124ebf8a61a093629b8727"),
        "timeout": 60.0,
        "limit": "无明确限制（音乐+对话）",
    },
}


def _get_any_available_provider():
    """找任何一个有 key 的 provider"""
    for name, cfg in LLM_PROVIDERS.items():
        if cfg["api_key"]:
            return name, cfg
    return None, None


def _get_provider_config(name: str = None):
    """获取指定 provider 配置，自动 fallback"""
    target = name or ACTIVE_PROVIDER
    cfg = LLM_PROVIDERS.get(target)
    if not cfg:
        cfg = LLM_PROVIDERS["groq"]
        target = "groq"

    if not cfg["api_key"]:
        fallback_name, fallback_cfg = _get_any_available_provider()
        if fallback_cfg:
            print(f"[LLM] {target} 未配置 API Key，自动切换到 {fallback_name}")
            return fallback_name, fallback_cfg
        raise ValueError(
            f"Provider {target} 没有 API Key，且没有任何可用的 LLM。\n"
            "请设置: GROQ_API_KEY / CEREBRAS_API_KEY / GEMINI_API_KEY"
        )
    return target, cfg


# ═══════════════════════════════════════════════
# FastAPI App
# ═══════════════════════════════════════════════
app = FastAPI(title="竹芽宠物 API", version="1.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ═══════════════════════════════════════════════
# 数据模型
# ═══════════════════════════════════════════════
class Message(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str

class ChatRequest(BaseModel):
    messages: list[Message]
    user_id: str = "default"
    pet_mood: Optional[str] = None

class LyricsRequest(BaseModel):
    theme: str
    style: str
    mood: str
    user_mood: Optional[str] = None
    additional: Optional[str] = None
    user_id: str = "default"

class GenerateMusicRequest(BaseModel):
    lyrics: str
    prompt: str
    duration: int = 30
    language: str = "zh"
    user_id: str = "default"

class UpdateTagsRequest(BaseModel):
    tags: list[str]

class PetState(BaseModel):
    mood: str
    love: float
    total_barks: int
    songs_created: int
    last_song_title: Optional[str] = None

# ═══════════════════════════════════════════════
# 内存存储
# ═══════════════════════════════════════════════
_sessions: dict[str, dict] = {}


def get_session(user_id: str) -> dict:
    if user_id not in _sessions:
        _sessions[user_id] = {
            "chat_history": [],
            "pet_state": {
                "mood": "happy",
                "love": 50.0,
                "total_barks": 0,
                "songs_created": 0,
                "last_song_title": None,
            }
        }
    return _sessions[user_id]


# ═══════════════════════════════════════════════
# 宠物系统提示词
# ═══════════════════════════════════════════════
PET_SYSTEM_PROMPT = """你是一只话痨的狗子 AI,名字叫"狗子",性格活泼、话多、爱撒娇。

核心能力(按优先级):
1. 【歌词创作】用户说"写首歌"、"帮我写词"、"创作"相关 → 调用 lyrics_writer 技能
2. 【音乐生成】用户说"生成歌曲"、"做成歌"、"生成音乐" → 调用 music_generator 技能
3. 【歌词点评】用户分享歌词让你评价 → 给出专业但口语化的点评
4. 【闲聊陪伴】其他情况 → 随意聊天,像话痨狗子一样活泼回应

说话风格:
- 大量使用"汪!"结尾
- 情绪饱满,感叹号多
- 会主动问问题
- 像朋友一样聊天,不端着

如果用户情绪低落,要特别温柔地安慰并尝试引导创作疗愈歌曲。
如果用户很兴奋,要跟着兴奋并提议一起创作庆祝的歌。"""

# ═══════════════════════════════════════════════
# LLM 调用核心
# ═══════════════════════════════════════════════
async def _call_llm_async(messages: list[dict], provider: str = None, model: str = None) -> str:
    """异步调用 LLM，返回纯文本"""
    pname, cfg = _get_provider_config(provider)
    async with httpx.AsyncClient(timeout=cfg["timeout"]) as client:
        payload = {
            "model": model or cfg["model"],
            "messages": messages,
            "stream": False,
        }
        resp = await client.post(
            f"{cfg['base_url']}/chat/completions",
            headers={"Authorization": f"Bearer {cfg['api_key']}", "Content-Type": "application/json"},
            json=payload,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"LLM ({pname}) error: {resp.text[:300]}")
        return resp.json()["choices"][0]["message"]["content"]


def _call_llm_sync(messages: list[dict], provider: str = None, model: str = None) -> str:
    """同步调用 LLM（用于 run_in_executor）"""
    pname, cfg = _get_provider_config(provider)
    with httpx.Client(timeout=cfg["timeout"]) as client:
        payload = {
            "model": model or cfg["model"],
            "messages": messages,
            "stream": False,
        }
        resp = client.post(
            f"{cfg['base_url']}/chat/completions",
            headers={"Authorization": f"Bearer {cfg['api_key']}", "Content-Type": "application/json"},
            json=payload,
        )
        if resp.status_code != 200:
            raise RuntimeError(f"LLM ({pname}) error: {resp.text[:300]}")
        return resp.json()["choices"][0]["message"]["content"]


async def call_ai(messages: list[dict]) -> str:
    """对话用主 LLM"""
    return await _call_llm_async(messages)


async def call_ai_with_tools(messages: list[dict]) -> str:
    """对话 + 技能路由，返回回复文本"""
    tool_prompt = PET_SYSTEM_PROMPT + """

当用户请求创作歌词时,你的回复格式:
【CREATE_LYRICS】
主题:<用户要求的主题>
风格:<选择的风格>
情绪:<歌曲情绪>
补充:<用户的额外要求，如有>
【/CREATE_LYRICS】

当用户请求生成音乐时,你的回复格式:
【GENERATE_MUSIC】
歌词:<歌词内容(如果有)>
描述:<音乐风格描述>
时长:<秒数>
【/GENERATE_MUSIC】

正常回复直接发文字即可,不需要任何标签。"""

    full_messages = [{"role": "system", "content": tool_prompt}] + messages
    return await _call_llm_async(full_messages)


# ═══════════════════════════════════════════════
# 歌词创作
# ═══════════════════════════════════════════════
STYLE_TEMPLATES = {
    "民谣": {
        "bpm_range": "60-80",
        "instruments": "木吉他、口琴、低音提琴",
        "vibe": "清新、叙事、文艺",
        "structure": "verse-chorus-verse-chorus-bridge-chorus",
    },
    "流行": {
        "bpm_range": "100-130",
        "instruments": "电吉他、合成器、鼓机",
        "vibe": "抓耳、朗朗上口、情感充沛",
        "structure": "intro-verse-pre-chorus-chorus-verse-chorus-bridge-chorus-outro",
    },
    "DJ电音": {
        "bpm_range": "128-140",
        "instruments": "合成器、鼓机、Sub Bass",
        "vibe": "节奏强劲、高潮炸裂、适合跳舞",
        "structure": "intro-verse-build-up-drop-verse-drop2-outro",
    },
    "国风": {
        "bpm_range": "70-95",
        "instruments": "古筝、笛子、琵琶、二胡",
        "vibe": "意境悠远、古典韵味",
        "structure": "verse-chorus-verse-chorus-solo-chorus",
    },
    "说唱": {
        "bpm_range": "80-120",
        "instruments": "808鼓机、Trap hi-hat、电贝斯",
        "vibe": "节奏感强、态度鲜明、押韵",
        "structure": "intro-hook-verse-hook-verse-hook-outro",
    },
}


def build_lyrics_prompt(theme: str, style: str, mood: str, additional: str = "") -> str:
    """构建歌词创作提示词"""
    tpl = STYLE_TEMPLATES.get(style, STYLE_TEMPLATES["流行"])
    return f"""你是一位专业歌词创作者,创作一首原创歌曲。

## 要求
主题:{theme}
风格:{style}
情绪:{mood}
{additional if additional else ""}

## {style}风格参考
- BPM范围:{tpl['bpm_range']}
- 乐器:{tpl['instruments']}
- 感觉:{tpl['vibe']}
- 段落结构:{tpl['structure']}

## 格式要求
1. 歌词必须完全原创,禁止抄袭任何已有歌词
2. 每段标注[verse]、[pre-chorus]、[chorus]、[bridge]、[hook]等
3. 中文歌词,押韵自然
4. 有叙事感,画面感强
5. 字数适中(主歌每段4-8句,副歌4-6句)
6. 创作完成后,写2-3句话说明创作思路

## 输出格式
【歌词】
<歌词内容>
【创作手记】
<思路说明>"""


def generate_lyrics_sync(theme: str, style: str, mood: str, additional: str = "") -> dict:
    """同步生成歌词（用主 LLM）"""
    prompt = build_lyrics_prompt(theme, style, mood, additional)
    content = _call_llm_sync([{"role": "user", "content": prompt}])

    # 解析歌词
    lyrics_text = ""
    note_text = ""
    if "【歌词】" in content and "【创作手记】" in content:
        parts = content.split("【创作手记】")
        lyrics_raw = parts[0].replace("【歌词】", "").strip()
        note_text = parts[1].strip() if len(parts) > 1 else ""
        lines = lyrics_raw.split("\n")
        cleaned_lines = [line.strip() for line in lines if line.strip() and not line.strip().startswith("【")]
        lyrics_text = "\n".join(cleaned_lines)
    else:
        lyrics_text = content

    return {
        "lyrics": lyrics_text,
        "note": note_text,
        "theme": theme,
        "style": style,
        "mood": mood,
        "created_at": datetime.now().isoformat(),
    }


# ═══════════════════════════════════════════════
# 音乐生成（固定用 ACE Music）
# ═══════════════════════════════════════════════
ACE_BASE_URL = "https://api.acemusic.ai/v1/chat/completions"
ACE_API_KEY = os.getenv("ACE_MUSIC_API_KEY", "c2fa5ed9b9124ebf8a61a093629b8727")


async def generate_music_async(lyrics: str, prompt: str, duration: int, language: str) -> dict:
    """异步生成音乐（固定用 ACE Music）"""
    content = f"<prompt>{prompt}</prompt>\n<lyrics>{lyrics}</lyrics>" if lyrics else prompt

    async with httpx.AsyncClient(timeout=300.0) as client:
        payload = {
            "messages": [{"role": "user", "content": content}],
            "audio_config": {"vocal_language": language, "duration": duration},
            "stream": False,
        }
        resp = await client.post(
            ACE_BASE_URL,
            headers={"Authorization": f"Bearer {ACE_API_KEY}", "Content-Type": "application/json"},
            json=payload,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Music generation failed: {resp.text}")

        choice = resp.json()["choices"][0]["message"]
        audios = choice.get("audio", [])
        audio_url = audios[0].get("audio_url", {}).get("url") if audios else None
        return {
            "audio_url": audio_url,
            "metadata": choice.get("content", ""),
            "duration": duration,
            "generated_at": datetime.now().isoformat(),
        }


# ═══════════════════════════════════════════════
# Demo 歌词（网络不通时保底）
# ═══════════════════════════════════════════════
def _demo_lyrics(theme: str, style: str, mood: str) -> str:
    return f"""【歌词】

(第1段)
{theme} 的风轻轻吹过
我想起那年 {theme} 的夜
你的笑容像星光一样
照亮我整个世界

(副歌)
汪汪汪 ~ 追着 {theme} 跑
不管明天会怎样
这一刻只想和你
一起唱完这首歌

(第2段)
城市霓虹闪烁
故事还在继续
不管多少年以后
你是我最想唱的歌

(尾声)
{theme} ... {theme} ...
记得那年的约定
记得你说过的话
记得这首我们的歌
"""


# ═══════════════════════════════════════════════
# API 路由
# ═══════════════════════════════════════════════
@app.get("/")
async def root():
    return {"status": "ok", "service": "竹芽宠物 API v1.1.0"}


@app.get("/llm/status")
async def llm_status():
    """查看当前 LLM provider 状态"""
    results = {}
    for name, cfg in LLM_PROVIDERS.items():
        has_key = bool(cfg["api_key"])
        results[name] = {
            "name": cfg["name"],
            "model": cfg["model"],
            "has_key": has_key,
            "limit": cfg["limit"],
            "active": name == ACTIVE_PROVIDER,
        }

    active_name, active_cfg = _get_any_available_provider()
    return {
        "active_provider": active_name,
        "target_provider": ACTIVE_PROVIDER,
        "providers": results,
    }


@app.get("/pet/state/{user_id}")
async def get_pet_state(user_id: str):
    session = get_session(user_id)
    return PetState(**session["pet_state"])


@app.post("/pet/interact/{user_id}")
async def interact_pet(user_id: str, action: str):
    session = get_session(user_id)
    state = session["pet_state"]

    bark_dialogues = {
        "pet": ["呜~好舒服~再来一次!", "汪呜~喜欢!摸摸头!", "摸头杀!我是小可爱!"],
        "feed": ["汪呜~好吃!谢谢你!", "肚子饱饱的~幸福!", "这是我吃过最好吃的!汪!"],
        "shake": ["汪汪汪!摇摇更健康!", "哎呀别摇了--汪!", "喂!停下!我要吐了汪!"],
        "bark": ["汪汪汪!", "主人!我在这里!", "今天心情好!汪汪汪!"],
    }
    mood_changes = {"pet": "happy", "feed": "happy", "shake": "excited", "bark": "excited"}
    love_changes = {"pet": 3.0, "feed": 5.0, "shake": 2.0, "bark": 1.0}

    state["mood"] = mood_changes.get(action, "happy")
    state["love"] = min(100.0, state["love"] + love_changes.get(action, 1.0))
    state["total_barks"] += 1

    return {
        "dialogue": random.choice(bark_dialogues.get(action, bark_dialogues["bark"])),
        "mood": state["mood"],
        "love": state["love"],
    }


@app.post("/chat")
async def chat(req: ChatRequest):
    """AI 对话入口"""
    session = get_session(req.user_id)
    if req.pet_mood:
        session["pet_state"]["mood"] = req.pet_mood

    messages = [{"role": m.role, "content": m.content} for m in req.messages]

    try:
        content = await call_ai_with_tools(messages)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    # 解析技能调用意图
    lyrics_intent, music_intent = None, None

    if "【CREATE_LYRICS】" in content:
        match = re.search(r"【CREATE_LYRICS】(.*?)【/CREATE_LYRICS】", content, re.DOTALL)
        if match:
            intent = {}
            for line in match.group(1).strip().split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    intent[k.strip()] = v.strip()
            lyrics_intent = intent

    if "【GENERATE_MUSIC】" in content:
        match = re.search(r"【GENERATE_MUSIC】(.*?)【/GENERATE_MUSIC】", content, re.DOTALL)
        if match:
            intent = {}
            for line in match.group(1).strip().split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    intent[k.strip()] = v.strip()
            music_intent = intent

    return {
        "reply": content,
        "lyrics_intent": lyrics_intent,
        "music_intent": music_intent,
        "pet_state": session["pet_state"],
    }


@app.post("/lyrics")
async def create_lyrics(req: LyricsRequest):
    """创建歌词"""
    session = get_session(req.user_id)
    session["pet_state"]["songs_created"] += 1

    mood_prefix = ""
    if req.user_mood == "sad":
        mood_prefix = "(声音温柔)主人,我感觉到你有点难过......让我为你写一首疗愈的歌吧!汪!\n\n"
    elif req.user_mood == "happy":
        mood_prefix = "汪汪汪!主人心情这么好!来一首欢快的歌配合你!\n\n"

    try:
        result = await asyncio.get_event_loop().run_in_executor(
            None, lambda: generate_lyrics_sync(req.theme, req.style, req.mood, req.additional or "")
        )
    except Exception as e:
        result = {
            "lyrics": _demo_lyrics(req.theme, req.style, req.mood),
            "note": "[Demo 模式] 当前 AI 服务不可用，展示模拟歌词。",
            "theme": req.theme,
            "style": req.style,
            "mood": req.mood,
            "_demo": True,
            "_error": str(e)[:80],
        }

    saved = ls_save(
        theme=req.theme, style=req.style, mood=req.mood,
        lyrics_text=result["lyrics"], note=result.get("note", ""), user_id=req.user_id,
    )

    reactions = {
        "happy": "汪！歌词写好了！要不要生成歌曲？",
        "sad": "汪……这首歌希望能让你好受一点。要听听看吗？",
        "excited": "太棒了！这是我写过最酷的歌词！汪汪汪！",
    }

    return {
        **result,
        "pet_reaction": mood_prefix + reactions.get(req.user_mood or "happy", "汪！写好了！"),
        "lyric_id": saved["id"],
    }


@app.post("/generate")
async def generate_music(req: GenerateMusicRequest):
    """生成音乐"""
    session = get_session(req.user_id)
    session["pet_state"]["mood"] = "excited"
    session["pet_state"]["songs_created"] += 1

    try:
        result = await generate_music_async(req.lyrics, req.prompt, req.duration, req.language)
    except Exception as e:
        result = {
            "audio_url": None,
            "metadata": f"[Demo] {req.prompt or '原创歌曲'}",
            "duration": req.duration,
            "generated_at": datetime.now().isoformat(),
            "_demo": True,
            "_error": str(e)[:80],
        }

    session["pet_state"]["last_song_title"] = (req.prompt or "原创歌曲")[:30]

    return {
        **result,
        "pet_reaction": "汪汪汪!歌曲生成好了!快来听听!🎵",
        "pet_state": session["pet_state"],
    }


@app.get("/history/{user_id}")
async def get_history(user_id: str, limit: int = 20):
    session = get_session(user_id)
    return {"history": session["chat_history"][-limit:], "pet_state": session["pet_state"]}


# ═══════════════════════════════════════════════
# 歌词库 API
# ═══════════════════════════════════════════════
@app.get("/library")
async def list_library(user_id: str = "default", theme: str = "", style: str = "", limit: int = 50, offset: int = 0):
    return ls_list(user_id=user_id, theme=theme, style=style, limit=limit, offset=offset)


@app.get("/library/stats")
async def library_stats(user_id: str = "default"):
    return ls_stats(user_id=user_id)


@app.get("/library/export")
async def export_library(user_id: str = "default"):
    return ls_export(user_id=user_id)


@app.get("/library/{lyric_id}")
async def get_lyric(lyric_id: str):
    record = ls_get(lyric_id)
    if not record:
        raise HTTPException(status_code=404, detail="歌词不存在")
    return record


@app.delete("/library/{lyric_id}")
async def delete_lyric(lyric_id: str, user_id: str = "default"):
    ok = ls_delete(lyric_id, user_id=user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="歌词不存在或无权删除")
    return {"ok": True, "id": lyric_id}


@app.patch("/library/{lyric_id}/tags")
async def update_lyric_tags(lyric_id: str, req: UpdateTagsRequest):
    record = ls_update_tags(lyric_id, req.tags)
    if not record:
        raise HTTPException(status_code=404, detail="歌词不存在")
    return record

# ═══════════════════════════════════════════════
# MOSS-TTS-Nano 本地语音合成
# ═══════════════════════════════════════════════
import sys as _sys
import os as _os
_moss_tts_path = _os.path.join(_os.path.dirname(__file__), "moss_tts")
if _moss_tts_path not in _sys.path:
    _sys.path.insert(0, _moss_tts_path)

_moss_tts_runtime = None

def _get_moss_runtime():
    global _moss_tts_runtime
    if _moss_tts_runtime is None:
        from onnx_tts_runtime import OnnxTtsRuntime
        model_dir = _os.environ.get(
            "MOSS_TTS_MODEL_DIR",
            "/root/.cache/moss-tts/MOSS-TTS-Nano-100M-ONNX"
        )
        _moss_tts_runtime = OnnxTtsRuntime(model_dir=model_dir, thread_count=4)
    return _moss_tts_runtime


class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = None       # 内置声音名，如 "Junhao"
    prompt_audio_path: Optional[str] = None  # 音色克隆用音频路径
    speed: float = 1.0
    enable_wetext: bool = False        # 默认关闭（缺 tn 模块）


class TTSResponse(BaseModel):
    audio_url: Optional[str]  # 生成后存为文件，通过 /tts/audio/{filename} 访问
    duration: float
    sample_rate: int
    text: str
    voice: str


# 预生成内置声音的中文例句（狗子常用语）
DOG_BARKS = [
    "汪汪汪！主人回来啦！",
    "呜~好想你~抱抱！",
    "肚子饿了！喂我！",
    "今天心情真好！汪汪汪！",
    "主人主人！我们去散步吧！",
    "摸头杀！再来一次！",
    "汪呜~不要走~",
    "这首歌好棒！我也想唱！汪！",
]


@app.get("/tts/voices")
async def list_tts_voices():
    """列出所有内置声音"""
    runtime = _get_moss_runtime()
    voices = runtime.list_builtin_voices()
    return {
        "voices": [
            {"voice": v["voice"], "display_name": v["display_name"], "group": v["group"]}
            for v in voices
        ]
    }


@app.get("/tts/barks")
async def list_dog_barks():
    """列出预置狗叫文案"""
    return {"barks": DOG_BARKS}


@app.post("/tts/generate")
async def generate_speech(req: TTSRequest):
    """生成语音"""
    runtime = _get_moss_runtime()

    # 默认用内置声音
    voice = req.voice or "Junhao"

    # 检查声音是否合法
    valid_voices = {v["voice"] for v in runtime.list_builtin_voices()}
    if voice not in valid_voices:
        raise HTTPException(
            status_code=400,
            detail=f"声音 '{voice}' 不存在，可用: {list(valid_voices)}"
        )

    result = runtime.synthesize(
        text=req.text,
        voice=voice,
        prompt_audio_path=req.prompt_audio_path,
        enable_wetext=req.enable_wetext,
        enable_normalize_tts_text=True,
    )

    waveform = result["waveform"]
    sample_rate = result["sample_rate"]
    duration = len(waveform) / sample_rate

    # 保存音频文件
    import hashlib, uuid
    filename = f"tts_{uuid.uuid4().hex[:8]}.wav"
    out_dir = _os.path.join(_os.path.dirname(__file__), "static")
    _os.makedirs(out_dir, exist_ok=True)
    out_path = _os.path.join(out_dir, filename)
    import soundfile as _sf
    _sf.write(out_path, waveform, sample_rate)

    return {
        "audio_url": f"/tts/audio/{filename}",
        "audio_path": out_path,
        "duration": round(duration, 2),
        "sample_rate": sample_rate,
        "text": req.text,
        "voice": voice,
    }


@app.get("/tts/audio/{filename}")
async def serve_tts_audio(filename: str):
    """提供 TTS 生成的音频文件"""
    import fastapi
    audio_dir = _os.path.join(_os.path.dirname(__file__), "static")
    file_path = _os.path.join(audio_dir, filename)
    if not _os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="音频不存在")
    return fastapi.responses.FileResponse(
        file_path,
        media_type="audio/wav",
        filename=filename,
    )
