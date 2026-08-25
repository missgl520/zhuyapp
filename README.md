# 竹芽 🐕

> AI音乐创作伴侣

## 项目结构

```
zhuyapp/
├── frontend/          # Flutter 前端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── modules/pet/       # 宠物模块
│   │   └── services/         # API 服务
│   ├── assets/               # 静态资源
│   └── pubspec.yaml
└── backend/           # FastAPI 后端
    ├── pet_api.py            # 宠物 API
    ├── lyrics_store.py       # 歌词库
    └── moss_tts/             # MOSS TTS 模块
```

## 前端运行

```bash
cd frontend
flutter pub get
flutter run
```

## 后端运行

```bash
cd backend
pip install fastapi uvicorn
uvicorn pet_api:app --reload --port 8000
```

## 技术栈

- **前端**: Flutter + flutter_animate
- **后端**: FastAPI + SQLite + Ollama
