import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

class SmartMirrorScreen extends StatefulWidget {
  const SmartMirrorScreen({super.key});

  @override
  State<SmartMirrorScreen> createState() => _SmartMirrorScreenState();
}

class _SmartMirrorScreenState extends State<SmartMirrorScreen> {
  late final String _cameraViewType;

  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isListening = false;
  bool _isThinking = false;

  String _lastWords = '';
  String _aiResponse = '';

  final List<Map<String, String>> _conversation = [];
  List<Map<String, dynamic>> _reminders = [];

  String emotion = 'loading...';
  String _currentMood = 'neutral';

  DateTime _now = DateTime.now();

  Timer? _timer;
  Timer? _emotionTimer;
  Timer? _listenTimer;

  int _musicIndex = 0;
  int _quranIndex = 0;
  int _adhkarIndex = 0;

  static const String pythonBaseUrl = "http://127.0.0.1:5000";

  final List<String> _musicPlaylist = [
    "assets/audio/music/song1.mp3",
    "assets/audio/music/song2.mp3",
    "assets/audio/music/song3.mp3",
  ];

  final List<String> _quranPlaylist = [
    "assets/audio/quran/yassin.mp3",
    "assets/audio/quran/rahman.mp3",
    "assets/audio/quran/baqara.mp3",
    "assets/audio/quran/mulk.mp3",
    "assets/audio/quran/wakiah.mp3",
  ];

  final List<String> _adhkarPlaylist = [
    "assets/audio/adhkar/adhkar1.mp3",
    "assets/audio/adhkar/adhkar2.mp3",
    "assets/audio/adhkar/adhkar3.mp3",
  ];

  @override
  void initState() {
    super.initState();

    _cameraViewType = 'python-camera-stream';

    ui.platformViewRegistry.registerViewFactory(_cameraViewType, (int viewId) {
      final img = web.HTMLImageElement()
        ..src = "$pythonBaseUrl/video_feed";

      img.style.setProperty('width', '100%');
      img.style.setProperty('height', '100%');
      img.style.setProperty('object-fit', 'cover');

      return img;
    });

    _initVoice();
    _startClock();
    _addDefaultReminders();
    _startEmotionPolling();
  }

  Future<void> _initVoice() async {
    await _speech.initialize();
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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;

        setState(() {
          emotion = data["emotion"] ?? "neutral";
          _currentMood = emotion;
        });
      }
    } catch (_) {}
  }

  void _addDefaultReminders() {
    _reminders = [
      {'time': '08:00', 'title': 'Réveil', 'active': true},
      {'time': '09:30', 'title': 'Réunion équipe', 'active': true},
      {'time': '12:00', 'title': 'Déjeuner', 'active': true},
      {'time': '18:00', 'title': 'Sport', 'active': false},
    ];
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();

    if (!available) {
      _setAnswer("Je ne peux pas accéder au micro.");
      return;
    }

    setState(() {
      _isListening = true;
      _isThinking = false;
      _lastWords = '';
    });

    await _speech.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
      },
    );

    _listenTimer?.cancel();
    _listenTimer = Timer(const Duration(seconds: 9), () async {
      await _finishListening();
    });
  }

  Future<void> _finishListening() async {
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });

    if (_lastWords.trim().isEmpty) {
      _setAnswer("Je n’ai rien entendu. Tu peux répéter ?");
      return;
    }

    await _handleCommand(_lastWords.trim());
  }

  void _stopListening() {
    _listenTimer?.cancel();
    _speech.stop();

    setState(() {
      _isListening = false;
    });

    if (_lastWords.trim().isNotEmpty) {
      _handleCommand(_lastWords.trim());
    }
  }

  Future<void> _playAsset(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(
      AssetSource(path.replaceFirst('assets/', '')),
    );
  }

  Future<void> _playMusic() async {
    await _playAsset(_musicPlaylist[_musicIndex]);
  }

  Future<void> _playQuran() async {
    await _playAsset(_quranPlaylist[_quranIndex]);
  }

  Future<void> _playAdhkar() async {
    await _playAsset(_adhkarPlaylist[_adhkarIndex]);
  }

  Future<void> _nextMusic() async {
    _musicIndex = (_musicIndex + 1) % _musicPlaylist.length;
    await _playMusic();
  }

  Future<void> _nextQuran() async {
    _quranIndex = (_quranIndex + 1) % _quranPlaylist.length;
    await _playQuran();
  }

  Future<void> _nextAdhkar() async {
    _adhkarIndex = (_adhkarIndex + 1) % _adhkarPlaylist.length;
    await _playAdhkar();
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
  }

  void _setAnswer(String text) {
    _aiResponse = text;

    _conversation.add({
      'role': 'assistant',
      'text': _aiResponse,
    });

    setState(() {
      _isThinking = false;
      _isListening = false;
    });

    _speak(_aiResponse);
  }

Future<void> _askAI(String message) async {
  try {

    setState(() {
      _isThinking = true;
    });

    final response = await http.post(
      Uri.parse("http://127.0.0.1:5050/ask-agent"),

      headers: {
        "Content-Type": "application/json",
      },

      body: jsonEncode({
        "message": message,
      }),
    );

    if (response.statusCode == 200) {

      final data = jsonDecode(response.body);

      String answer =
          data["answer"] ?? "Je n’ai pas compris.";

      String action =
          data["action"] ?? "none";

      if (action == "play_music") {
        await _playMusic();
      }

      if (action == "play_quran") {
        await _playQuran();
      }

      if (action == "play_adhkar") {
        await _playAdhkar();
      }

      if (action == "stop_audio") {
        await _stopAudio();
      }

      _setAnswer(answer);

    } else {

      _setAnswer("Erreur serveur AI.");
    }

  } catch (e) {

    print("AI ERROR: $e");

    _setAnswer("Erreur connexion DeepSeek.");
  }
}

  Future<void> _handleCommand(String cmd) async {
    final text = cmd.toLowerCase();

    _conversation.add({
      'role': 'user',
      'text': cmd,
    });

    if (text.contains('musique') ||
        text.contains('music') ||
        text.contains('chanson') ||
        text.contains('ghne') ||
        text.contains('ghneya')) {
      await _playMusic();
      _setAnswer("Avec plaisir 🎵 je lance la musique.");
    } else if (text.contains('coran') ||
        text.contains('quran') ||
        text.contains('qoran') ||
        text.contains('sourate')) {
      await _playQuran();
      _setAnswer("Je lance le Coran 📖");
    } else if (text.contains('adhkar') ||
        text.contains('azkar') ||
        text.contains('dhikr')) {
      await _playAdhkar();
      _setAnswer("Je lance les adhkar 🤍");
    } else if (text.contains('next') ||
        text.contains('suivant') ||
        text.contains('suivante')) {
      await _nextMusic();
      _setAnswer("Je passe à la musique suivante 🎵");
    } else if (text.contains('sourate suivante')) {
      await _nextQuran();
      _setAnswer("Je passe à la sourate suivante 📖");
    } else if (text.contains('adhkar suivant')) {
      await _nextAdhkar();
      _setAnswer("Je passe aux adhkar suivants 🤍");
    } else if (text.contains('stop') ||
        text.contains('arrête') ||
        text.contains('arrete')) {
      await _stopAudio();
      _setAnswer("D’accord, j’arrête la lecture.");
    } else {
      await _askAI(cmd);
    }
  }

  void _speak(String text) {
    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = 'fr-FR'
      ..pitch = 1
      ..rate = 0.9
      ..volume = 1;

    web.window.speechSynthesis.cancel();
    web.window.speechSynthesis.speak(utterance);
  }

  void _checkReminders() {
    final currentTime =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

    for (final reminder in _reminders) {
      if (reminder['time'] == currentTime && reminder['active'] == true) {
        _speak('Rappel ${reminder['title']}');
        reminder['active'] = false;
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _audioPlayer.dispose();
    _timer?.cancel();
    _emotionTimer?.cancel();
    _listenTimer?.cancel();
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
                      color: Colors.white.withValues(alpha: 0.1),
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
                      color: _getMoodColor().withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _getMoodColor()),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.mood, color: _getMoodColor()),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Humeur: $emotion",
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
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.3),
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
                                        ? Colors.blue.withValues(alpha: 0.3)
                                        : Colors.green.withValues(alpha: 0.3),
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
                  child: HtmlElementView(viewType: _cameraViewType),
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
                  if (_aiResponse.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
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
                    onTap: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: _isListening ? Colors.red : Colors.cyanAccent,
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
                            _isListening ? 'J’écoute...' : 'Parlez à Najma',
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
                  if (_lastWords.isNotEmpty)
                    Text(
                      'Vous: $_lastWords',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
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
                      children: _reminders.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: r['active']
                                ? Colors.purpleAccent.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
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
                        );
                      }).toList(),
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
      default:
        return Colors.greenAccent;
    }
  }
}