// 仅用于本地预览「音乐狗子」3D 宠物（验证穿模修复等），不参与主流程。
// 构建：flutter run -t lib/dog_preview_main.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() => runApp(const DogPreviewApp());

class DogPreviewApp extends StatelessWidget {
  const DogPreviewApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 380,
                  height: 560,
                  child: ModelViewer(
                    src: 'assets/vrm_test/dog_avatar.glb',
                    alt: 'music dog',
                    autoPlay: true,
                    cameraControls: true,
                    cameraOrbit: '15deg 70deg 1.5m',
                    cameraTarget: '0m 0.34m 0m',
                    fieldOfView: '42deg',
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
              const Positioned(
                top: 16,
                left: 16,
                child: Text(
                  'TARGET = assets/vrm_test/dog_avatar.glb',
                  style: TextStyle(fontSize: 13, color: Colors.black, backgroundColor: Colors.yellow),
                ),
              ),
            ],
          ),
        ),
      );
}
