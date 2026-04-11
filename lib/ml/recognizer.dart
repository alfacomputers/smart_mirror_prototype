import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Recognizer {
  late Interpreter interpreter;
  static const String modelPath = 'assets/mobilefacenet.tflite';

  Recognizer() {
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(modelPath);
      print("✅ MobileFaceNet model loaded successfully!");
    } catch (e) {
      print("❌ Error loading model: $e");
    }
  }

  // تحويل صورة الوجه إلى Embedding (Vector)
  Float32List getEmbedding(img.Image faceImage) {
    // Resize الوجه إلى 112x112 (حجم النموذج)
    img.Image resized = img.copyResize(faceImage, width: 112, height: 112);

    var input = Float32List(1 * 112 * 112 * 3);
    var index = 0;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        var pixel = resized.getPixel(x, y);
        input[index++] = (img.getRed(pixel) / 127.5) - 1.0;
        input[index++] = (img.getGreen(pixel) / 127.5) - 1.0;
        input[index++] = (img.getBlue(pixel) / 127.5) - 1.0;
      }
    }

    var output = List.filled(192, 0.0).reshape([1, 192]);

    interpreter.run(input.reshape([1, 112, 112, 3]), output);

    return Float32List.fromList(output[0]);
  }

  // حساب التشابه بين وجهين (Cosine Similarity)
  double similarity(Float32List emb1, Float32List emb2) {
    double dot = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < emb1.length; i++) {
      dot += emb1[i] * emb2[i];
      norm1 += emb1[i] * emb1[i];
      norm2 += emb2[i] * emb2[i];
    }

    return dot / (sqrt(norm1) * sqrt(norm2));
  }
}