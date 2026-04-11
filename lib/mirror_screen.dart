import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

class SmartMirrorScreen extends StatefulWidget {
  const SmartMirrorScreen({super.key});

  @override
  State<SmartMirrorScreen> createState() => _SmartMirrorScreenState();
}

class _SmartMirrorScreenState extends State<SmartMirrorScreen> {
  late final String _cameraViewType;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isThinking = false;

  String _lastCommand = '';
  String _aiResponse = '';

  final List<Map<String, String>> _conversation = [];
  List<Map<String, dynamic>> _reminders = [];

  String emotion = 'loading...';
  String _currentMood = 'Neutre';

  DateTime _now = DateTime.now();
  Timer? _timer;
  Timer? _emotionTimer;

  static const String pythonBaseUrl = "http://127.0.0.1:5000";

  @override
  void initState() {
    super.initState();
    _cameraViewType = 'python-camera-stream';

ui.platformViewRegistry.registerViewFactory(_cameraViewType, (int viewId) {
  final img = web.HTMLImageElement()
    ..src = "$pythonBaseUrl/video_feed"
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover';

  return img;
});
    _initVoice();
    _initTTS();
    _startClock();
    _addDefaultReminders();
    _startEmotionPolling();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _checkReminders();
    });
  }

  void _startEmotionPolling() {
    getEmotion();

    _emotionTimer?.cancel();
    _emotionTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;
      await getEmotion();
    });
  }

  Future<void> getEmotion() async {
    try {
      final response = await http.get(
        Uri.parse("$pythonBaseUrl/current-emotion"),
      );

      debugPrint("STATUS = ${response.statusCode}");
      debugPrint("BODY = ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (!mounted) return;
        setState(() {
          emotion = data["emotion"]?.toString() ?? "error";
          _currentMood = emotion;
        });
      }
    } catch (e) {
      debugPrint("ERROR = $e");
    }
  }

  void _addDefaultReminders() {
    _reminders = [
      {'time': '08:00', 'title': 'Réveil', 'active': true},
      {'time': '09:30', 'title': 'Réunion équipe', 'active': true},
      {'time': '12:00', 'title': 'Déjeuner', 'active': true},
      {'time': '18:00', 'title': 'Sport', 'active': false},
    ];
  }

  Future<void> _initVoice() async {
    await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'done' && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => debugPrint('Speech error: $error'),
    );
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.9);
  }

  Future<void> _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      _isThinking = false;
      _aiResponse = '';
      _lastCommand = '';
    });

    await _speech.listen(
      onResult: (result) async {
        if (!mounted) return;
        setState(() {
          _lastCommand = result.recognizedWords;
        });
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      localeId: 'fr_FR',
      cancelOnError: true,
    );

    Future.delayed(const Duration(seconds: 6), () async {
      if (!mounted) return;

      await _speech.stop();

      if (!mounted) return;
      setState(() {
        _isListening = false;
      });

      if (_lastCommand.trim().isNotEmpty) {
        await _processWithAI(_lastCommand.trim());
      }
    });
  }

  Future<void> _processWithAI(String userText) async {
    if (!mounted) return;

    setState(() {
      _isListening = false;
      _isThinking = true;
    });

    _conversation.add({'role': 'user', 'text': userText});

    await Future.delayed(const Duration(milliseconds: 300));
    await _processCommandLocal(userText);
  }

  Future<void> _processCommandLocal(String command) async {
    final lower = command.toLowerCase();

    if (lower.contains('bonjour') ||
        lower.contains('bnjr') ||
        lower.contains('salut') ||
        lower.contains('hello') ||
        lower.contains('صباح')) {
      _aiResponse =
          'Bonjour 😊 cv ? أنا Najma، موجودة باش نعاونك. تحب نوريك الطقس، الوقت، ولا الرابلات؟';
    } else if (lower.contains('cv') ||
        lower.contains('ça va') ||
        lower.contains('ca va')) {
      _aiResponse =
          'أنا لاباس، ونتي cv ؟ إذا تحب نوريك المتيو، الوقت، والرابلات متاعك.';
    } else if (lower.contains('météo') ||
        lower.contains('meteo') ||
        lower.contains('جو')) {
      _aiResponse = 'الجو زين، 24 درجة وشمس';
    } else if (lower.contains('heure') ||
        lower.contains('وقت') ||
        lower.contains('ساعة')) {
      _aiResponse =
          'توّا الساعة ${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}.';
    } else if (lower.contains('rappel') ||
        lower.contains('rappels') ||
        lower.contains('تذكير')) {
      final activeReminders =
          _reminders.where((r) => r['active'] == true).toList();

      if (activeReminders.isEmpty) {
        _aiResponse = 'ما عندك حتى rappel actif توّا.';
      } else {
        final text =
            activeReminders.map((r) => '${r['title']} à ${r['time']}').join(', ');
        _aiResponse = 'عندك الرابلات هاذم: $text';
      }
    } else if (lower.contains('calme')) {
      _changeMood('Calme');
      _aiResponse = 'حاضر، بدلت المود إلى calme. خذ نفس وارتاح شوية.';
    } else if (lower.contains('triste')) {
      _changeMood('Triste');
      _aiResponse =
          'أنا معاك. بدلت المود إلى triste، وإذا تحب نهدّيك ونفكرك تشرب ماء وتاخذ راحة.';
    } else if (lower.contains('énergique') ||
        lower.contains('energetique')) {
      _changeMood('Énergique');
      _aiResponse = 'هاو المود ولى énergique! يعطيك الطاقة.';
    } else if (lower.contains('eau') || lower.contains('ماء')) {
      _aiResponse = 'تذكير صغير: اشرب ماء، صحتك تهمني برشة 💙';
    } else {
      _aiResponse =
          'سمعتك، أما ما فهمتش مليح. تنجم تقلي bonjour، météo، heure، rappels، calme.';
    }

    _conversation.add({'role': 'assistant', 'text': _aiResponse});

    if (!mounted) return;
    setState(() {
      _isThinking = false;
    });

    await _speak(_aiResponse);
  }

  Future<void> _speak(String text) async {
    debugPrint('TTS => $text');

    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    await _tts.setLanguage('fr-FR');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.9);
    await _tts.speak(text);
  }

  void _changeMood(String mood) {
    if (!mounted) return;
    setState(() => _currentMood = mood);
  }

  void _checkReminders() {
    final currentTime =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

    for (final reminder in _reminders) {
      if (reminder['time'] == currentTime && reminder['active'] == true) {
        _speak('تذكير: ${reminder['title']}');
        reminder['active'] = false;
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _timer?.cancel();
    _emotionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 70,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${_now.day}/${_now.month}/${_now.year}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wb_sunny, color: Colors.orange, size: 30),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '24°C',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Ensoleillé',
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getMoodColor().withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _getMoodColor()),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mood, color: _getMoodColor()),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            emotion == "no_face"
                                ? "Humeur: no face"
                                : "Humeur: $emotion",
                            style: TextStyle(color: _getMoodColor()),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONVERSATION',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _conversation.length,
                              itemBuilder: (context, index) {
                                final msg = _conversation[index];
                                final isUser = msg['role'] == 'user';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? Colors.blue.withOpacity(0.3)
                                        : Colors.green.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${isUser ? "Vous" : "Najma"}: ${msg['text']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                width: 640,
                height: 480,
                decoration: BoxDecoration(
                  border: Border.all(color: _getMoodColor(), width: 4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                   child: HtmlElementView(
                    viewType: _cameraViewType,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isThinking)
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Najma réfléchit...',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  if (_aiResponse.isNotEmpty && !_isThinking)
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.greenAccent),
                      ),
                      child: Text(
                        'Najma: $_aiResponse',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  GestureDetector(
                    onTap: _startListening,
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.red.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color:
                              _isListening ? Colors.red : Colors.cyanAccent,
                          width: 3,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            size: 60,
                            color:
                                _isListening ? Colors.red : Colors.cyanAccent,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isListening ? 'J\'écoute...' : 'Parlez à Najma',
                            style: TextStyle(
                              color: _isListening
                                  ? Colors.red
                                  : Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_lastCommand.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Vous: "$_lastCommand"',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 30),
                  const Text(
                    'RAPPELS',
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: _reminders
                          .map(
                            (r) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: r['active']
                                    ? Colors.purpleAccent.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: r['active']
                                      ? Colors.purpleAccent
                                      : Colors.grey,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    r['active']
                                        ? Icons.alarm_on
                                        : Icons.alarm_off,
                                    color: r['active']
                                        ? Colors.purpleAccent
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r['time'],
                                          style: TextStyle(
                                            color: r['active']
                                                ? Colors.purpleAccent
                                                : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          r['title'],
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getMoodColor() {
    switch (_currentMood.toLowerCase()) {
      case 'happy':
        return Colors.greenAccent;
      case 'sad':
        return Colors.blueAccent;
      case 'angry':
        return Colors.redAccent;
      case 'surprise':
        return Colors.orangeAccent;
      case 'neutral':
        return Colors.greenAccent;
      case 'no_face':
        return Colors.grey;
      case 'camera_error':
        return Colors.redAccent;
      case 'error':
        return Colors.redAccent;
      case 'calme':
        return Colors.blueAccent;
      case 'énergique':
        return Colors.orangeAccent;
      case 'triste':
        return Colors.grey;
      default:
        return Colors.greenAccent;
    }
  }
}