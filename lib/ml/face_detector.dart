import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'recognizer.dart';

class FaceDetectorService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      enableLandmarks: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  final Recognizer recognizer = Recognizer();

  Map<String, Float32List> registeredFaces = {};

  // تسجيل وجه جديد (مبسط)
  Future<void> registerFace(String userId, CameraImage cameraImage, Face face) async {
    final cropped = await _cropFace(cameraImage, face);
    if (cropped == null) return;

    final embedding = recognizer.getEmbedding(cropped);
    registeredFaces[userId] = embedding;
    print("✅ Face registered for: $userId");
  }

  // التعرف على الوجه
  Future<String?> recognizeFace(CameraImage cameraImage, Face face) async {
    final cropped = await _cropFace(cameraImage, face);
    if (cropped == null) return null;

    final newEmb = recognizer.getEmbedding(cropped);

    double bestSim = 0.0;
    String? bestUser;

    registeredFaces.forEach((userId, emb) {
      final sim = recognizer.similarity(newEmb, emb);
      if (sim > bestSim && sim > 0.7) {
        bestSim = sim;
        bestUser = userId;
      }
    });

    return bestUser;
  }

  Future<img.Image?> _cropFace(CameraImage image, Face face) async {
    try {
      final bytes = image.planes[0].bytes;
      final imgImage = img.decodeImage(bytes);
      if (imgImage == null) return null;

      final box = face.boundingBox;
      return img.copyCrop(
        imgImage,
        x: box.left.toInt(),
        y: box.top.toInt(),
        width: box.width.toInt(),
        height: box.height.toInt(),
      );
    } catch (e) {
      print("Crop error: $e");
      return null;
    }
  }

  void dispose() {
    _faceDetector.close();
  }
}