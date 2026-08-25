"""
竹芽歌词库 — 本地持久化存储
Lyrics Store — 本地 SQLite + JSON 双轨
"""
import sqlite3
import json
import os
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

DB_PATH = Path(__file__).parent / "lyrics_store.db"
STORE_DIR = Path(__file__).parent / "lyrics_store"

# ─── 初始化 ───────────────────────────────────────────────
STORE_DIR.mkdir(exist_ok=True)

_conn: Optional[sqlite3.Connection] = None

def _get_conn() -> sqlite3.Connection:
    global _conn
    if _conn is None:
        _conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
        _conn.execute("PRAGMA journal_mode=WAL")
        for stmt in _CREATE_TABLE.split(";"):
            stmt = stmt.strip()
            if stmt:
                _conn.execute(stmt)
    return _conn

_CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS lyrics (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL DEFAULT 'default',
    theme       TEXT NOT NULL DEFAULT '',
    style       TEXT NOT NULL DEFAULT '流行',
    mood        TEXT NOT NULL DEFAULT 'happy',
    lyrics_text TEXT NOT NULL,
    note        TEXT NOT NULL DEFAULT '',
    tags        TEXT NOT NULL DEFAULT '[]',
    title       TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_lyrics_user ON lyrics(user_id);
CREATE INDEX IF NOT EXISTS idx_lyrics_theme ON lyrics(theme);
CREATE INDEX IF NOT EXISTS idx_lyrics_created ON lyrics(created_at DESC);
"""

# ─── CRUD ──────────────────────────────────────────────────

def save(theme: str, style: str, mood: str, lyrics_text: str,
         note: str = "", tags: list = None, user_id: str = "default",
         title: str = "") -> dict:
    """保存歌词，返回记录"""
    conn = _get_conn()
    now = datetime.now().isoformat()
    lid = str(uuid.uuid4())[:8]

    if not title:
        # 从歌词第一行提取标题
        first_line = lyrics_text.strip().split("\n")[0].strip()
        title = first_line[:40] if first_line else theme[:20]

    conn.execute("""
        INSERT INTO lyrics (id, user_id, theme, style, mood, lyrics_text, note, tags, title, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (lid, user_id, theme, style, mood, lyrics_text, note,
          json.dumps(tags or [], ensure_ascii=False), title, now, now))
    conn.commit()

    return get(lid) or {}


def get(lid: str) -> Optional[dict]:
    """按 ID 查一条"""
    conn = _get_conn()
    row = conn.execute("SELECT * FROM lyrics WHERE id = ?", (lid,)).fetchone()
    if not row:
        return None
    cols = [c[0] for c in conn.execute("SELECT * FROM lyrics LIMIT 0").description]
    record = dict(zip(cols, row))
    record["tags"] = json.loads(record["tags"] or "[]")
    return record


def list_(user_id: str = "default", theme: str = "", style: str = "",
          limit: int = 50, offset: int = 0) -> dict:
    """
    列表查询，返回分页结果。
    支持按 user_id / theme / style 过滤。
    """
    conn = _get_conn()
    where = ["user_id = ?"]
    params: list = [user_id]

    if theme:
        where.append("theme LIKE ?")
        params.append(f"%{theme}%")
    if style:
        where.append("style = ?")
        params.append(style)

    where_sql = " AND ".join(where)

    total = conn.execute(
        f"SELECT COUNT(*) FROM lyrics WHERE {where_sql}", params
    ).fetchone()[0]

    rows = conn.execute(f"""
        SELECT id, user_id, theme, style, mood, title, note, tags, created_at, updated_at
        FROM lyrics
        WHERE {where_sql}
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    """, params + [limit, offset]).fetchall()

    cols = ["id", "user_id", "theme", "style", "mood", "title", "note", "tags", "created_at", "updated_at"]
    items = []
    for row in rows:
        item = dict(zip(cols, row))
        item["tags"] = json.loads(item["tags"] or "[]")
        # 只返回歌词摘要（前3行）
        lyrics_full = conn.execute(
            "SELECT lyrics_text FROM lyrics WHERE id = ?", (item["id"],)
        ).fetchone()
        if lyrics_full:
            preview = "\n".join(lyrics_full[0].strip().split("\n")[:3])
            item["lyrics_preview"] = preview + ("..." if "\n" in lyrics_full[0] else "")
        items.append(item)

    return {
        "items": items,
        "total": total,
        "limit": limit,
        "offset": offset,
    }


def delete(lid: str, user_id: str = "default") -> bool:
    """删除歌词（只允许删除自己的）"""
    conn = _get_conn()
    cur = conn.execute(
        "DELETE FROM lyrics WHERE id = ? AND user_id = ?", (lid, user_id)
    )
    conn.commit()
    return cur.rowcount > 0


def update_tags(lid: str, tags: list, user_id: str = "default") -> Optional[dict]:
    """更新标签"""
    conn = _get_conn()
    now = datetime.now().isoformat()
    cur = conn.execute(
        "UPDATE lyrics SET tags = ?, updated_at = ? WHERE id = ? AND user_id = ?",
        (json.dumps(tags, ensure_ascii=False), now, lid, user_id)
    )
    conn.commit()
    if cur.rowcount == 0:
        return None
    return get(lid)


def stats(user_id: str = "default") -> dict:
    """统计：总数、各风格数量"""
    conn = _get_conn()
    total = conn.execute(
        "SELECT COUNT(*) FROM lyrics WHERE user_id = ?", (user_id,)
    ).fetchone()[0]
    by_style = conn.execute("""
        SELECT style, COUNT(*) as cnt
        FROM lyrics WHERE user_id = ?
        GROUP BY style
        ORDER BY cnt DESC
    """, (user_id,)).fetchall()
    by_mood = conn.execute("""
        SELECT mood, COUNT(*) as cnt
        FROM lyrics WHERE user_id = ?
        GROUP BY mood
        ORDER BY cnt DESC
    """, (user_id,)).fetchall()
    return {
        "total": total,
        "by_style": [{"style": r[0], "count": r[1]} for r in by_style],
        "by_mood":  [{"mood": r[0], "count": r[1]}  for r in by_mood],
    }


def export_json(user_id: str = "default") -> list:
    """导出用户所有歌词为 JSON 列表"""
    conn = _get_conn()
    rows = conn.execute(
        "SELECT * FROM lyrics WHERE user_id = ? ORDER BY created_at DESC",
        (user_id,)
    ).fetchall()
    cols = [c[0] for c in conn.execute("SELECT * FROM lyrics LIMIT 0").description]
    result = []
    for row in rows:
        record = dict(zip(cols, row))
        record["tags"] = json.loads(record["tags"] or "[]")
        result.append(record)
    return result
