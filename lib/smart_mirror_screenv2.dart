import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';

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
  Timer? _weatherTimer;

  int _musicIndex = 0;
  int _quranIndex = 0;
  int _adhkarIndex = 0;

  // ─── Configuration serveur Python (caméra + émotions) ───────────────────────
  static const String pythonBaseUrl = "http://127.0.0.1:5000";

  // ─── Configuration OpenRouter + GPT-4o ──────────────────────────────────────
  static const String _openRouterApiKey =
      "";
  static const String _openRouterUrl =
      "https://openrouter.ai/api/v1/chat/completions";
  static const String _openRouterModel = "openai/gpt-4o";

  // ─── Configuration OpenWeatherMap ────────────────────────────────────────────
  static const String _weatherApiKey = ""; // ← Ta vraie clé ici
  static const String _weatherLang = "fr";
  static const String _weatherUnits = "metric";

  // ─── État météo ───────────────────────────────────────────────────────────────
  double _temperature = 0;
  String _weatherDescription = 'Chargement...';
  String _weatherIcon = '';
  bool _weatherLoaded = false;

  // ─── Géolocalisation ─────────────────────────────────────────────────────────
  String _detectedCity = 'Ma position';
  double? _userLat;
  double? _userLon;
  String _locationStatus = 'Localisation...';

  // ─── Playlists audio ─────────────────────────────────────────────────────────
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

  // ────────────────────────────────────────────────────────────────────────────
  //  INIT
  // ────────────────────────────────────────────────────────────────────────────

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

    // Géolocalisation → météo au démarrage, puis toutes les 10 minutes
    _initLocationAndWeather();
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _fetchWeatherByCoords(),
    );
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

  // ────────────────────────────────────────────────────────────────────────────
  //  GÉOLOCALISATION
  // ────────────────────────────────────────────────────────────────────────────

  /// Demande la permission de localisation, récupère les coordonnées GPS,
  /// puis charge la météo par coordonnées.
  Future<void> _initLocationAndWeather() async {
    try {
      // 1. Vérifier si le service de localisation est activé
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationStatus = 'GPS désactivé';
            _weatherDescription = 'GPS désactivé';
          });
        }
        // Fallback : ville par défaut
        await _fetchWeatherByCity('Tunis');
        return;
      }

      // 2. Vérifier / demander la permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationStatus = 'Permission refusée';
              _weatherDescription = 'Permission refusée';
            });
          }
          await _fetchWeatherByCity('Tunis');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationStatus = 'Permission refusée définitivement';
            _weatherDescription = 'Activer la localisation dans les paramètres';
          });
        }
        await _fetchWeatherByCity('Tunis');
        return;
      }

      // 3. Obtenir la position actuelle
      if (mounted) {
        setState(() => _locationStatus = 'Localisation en cours...');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLon = position.longitude;
          _locationStatus = 'Position obtenue';
        });
      }

      // 4. Charger la météo avec les coordonnées réelles
      await _fetchWeatherByCoords();
    } catch (e) {
      print("Geolocation error: $e");
      if (mounted) {
        setState(() => _locationStatus = 'Erreur GPS');
      }
      // Fallback sur ville par défaut
      await _fetchWeatherByCity('Tunis');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  WEATHER — par coordonnées GPS (position réelle)
  // ────────────────────────────────────────────────────────────────────────────

  /// Récupère la météo via lat/lon (plus précis, pas de problème d'accent).
  Future<void> _fetchWeatherByCoords() async {
    if (_userLat == null || _userLon == null) {
      // Coordonnées pas encore dispo → réessayer via géolocalisation
      await _initLocationAndWeather();
      return;
    }

    try {
      final uri = Uri.https(
        'api.openweathermap.org',
        '/data/2.5/weather',
        {
          'lat': _userLat!.toString(),
          'lon': _userLon!.toString(),
          'appid': _weatherApiKey,
          'units': _weatherUnits,
          'lang': _weatherLang,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _parseAndApplyWeather(data);
      } else {
        print("Weather API error ${response.statusCode}: ${response.body}");
        if (mounted) {
          setState(() {
            _weatherDescription = "Erreur ${response.statusCode}";
            _weatherLoaded = false;
          });
        }
      }
    } catch (e) {
      print("Weather fetch error: $e");
      if (mounted) {
        setState(() {
          _weatherDescription = "Hors ligne";
          _weatherLoaded = false;
        });
      }
    }
  }

  /// Fallback : récupère la météo par nom de ville.
  Future<void> _fetchWeatherByCity(String city) async {
    try {
      final uri = Uri.https(
        'api.openweathermap.org',
        '/data/2.5/weather',
        {
          'q': city,
          'appid': _weatherApiKey,
          'units': _weatherUnits,
          'lang': _weatherLang,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _parseAndApplyWeather(data);
      } else {
        if (mounted) {
          setState(() {
            _weatherDescription = "Erreur ${response.statusCode}";
            _weatherLoaded = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherDescription = "Hors ligne";
          _weatherLoaded = false;
        });
      }
    }
  }

  /// Parse la réponse JSON OpenWeatherMap et met à jour le state.
  void _parseAndApplyWeather(Map<String, dynamic> data) {
    if (!mounted) return;

    final main = data['main'] as Map<String, dynamic>;
    final weatherList = data['weather'] as List<dynamic>;
    final weather = weatherList.first as Map<String, dynamic>;

    // Nom de la ville renvoyé par l'API (ex: "Sousse", "Paris")
    final cityName = data['name'] as String? ?? _detectedCity;

    setState(() {
      _temperature = (main['temp'] as num).toDouble();
      _weatherDescription = _capitalise(weather['description'] as String);
      _weatherIcon = weather['icon'] as String;
      _detectedCity = cityName;
      _weatherLoaded = true;
      _locationStatus = cityName;
    });
  }

  /// Rafraîchit manuellement (relance la géoloc si nécessaire).
  Future<void> _refreshWeather() async {
    if (_userLat != null && _userLon != null) {
      await _fetchWeatherByCoords();
    } else {
      await _initLocationAndWeather();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  WEATHER HELPERS
  // ────────────────────────────────────────────────────────────────────────────

  IconData _weatherIconData(String iconCode) {
    if (iconCode.isEmpty) return Icons.cloud;
    final day = iconCode.endsWith('d');
    final code = iconCode.substring(0, 2);

    switch (code) {
      case '01':
        return day ? Icons.wb_sunny : Icons.nights_stay;
      case '02':
        return day ? Icons.wb_cloudy : Icons.nights_stay;
      case '03':
        return Icons.cloud;
      case '04':
        return Icons.cloud_queue;
      case '09':
        return Icons.grain;
      case '10':
        return Icons.umbrella;
      case '11':
        return Icons.thunderstorm;
      case '13':
        return Icons.ac_unit;
      case '50':
        return Icons.foggy;
      default:
        return Icons.cloud;
    }
  }

  Color _weatherIconColor(String iconCode) {
    if (iconCode.isEmpty) return Colors.blueGrey;
    final code = iconCode.substring(0, 2);
    switch (code) {
      case '01':
        return Colors.orange;
      case '02':
      case '03':
      case '04':
        return Colors.blueGrey;
      case '09':
      case '10':
        return Colors.lightBlue;
      case '11':
        return Colors.yellow;
      case '13':
        return Colors.white;
      case '50':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String get _tempDisplay =>
      "${_temperature.round()}°${_weatherUnits == 'metric' ? 'C' : 'F'}";

  // ────────────────────────────────────────────────────────────────────────────
  //  EMOTION
  // ────────────────────────────────────────────────────────────────────────────

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

  // ────────────────────────────────────────────────────────────────────────────
  //  REMINDERS
  // ────────────────────────────────────────────────────────────────────────────

  void _addDefaultReminders() {
    _reminders = [
      {'time': '08:00', 'title': 'Réveil', 'active': true},
      {'time': '09:30', 'title': 'Réunion équipe', 'active': true},
      {'time': '12:00', 'title': 'Déjeuner', 'active': true},
      {'time': '18:00', 'title': 'Sport', 'active': false},
    ];
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

  // ────────────────────────────────────────────────────────────────────────────
  //  VOICE / SPEECH
  // ────────────────────────────────────────────────────────────────────────────

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
      _setAnswer("Je n'ai rien entendu. Tu peux répéter ?");
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

  void _speak(String text) {
    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = 'fr-FR'
      ..pitch = 1
      ..rate = 0.9
      ..volume = 1;

    web.window.speechSynthesis.cancel();
    web.window.speechSynthesis.speak(utterance);
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  AUDIO PLAYBACK
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _playAsset(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(AssetSource(path.replaceFirst('assets/', '')));
  }

  Future<void> _playMusic() async => _playAsset(_musicPlaylist[_musicIndex]);
  Future<void> _playQuran() async => _playAsset(_quranPlaylist[_quranIndex]);
  Future<void> _playAdhkar() async => _playAsset(_adhkarPlaylist[_adhkarIndex]);

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

  Future<void> _stopAudio() async => _audioPlayer.stop();

  // ────────────────────────────────────────────────────────────────────────────
  //  COMMAND ROUTING
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _handleCommand(String cmd) async {
    final text = cmd.toLowerCase();

    _conversation.add({'role': 'user', 'text': cmd});

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
    } else if (text.contains('suivante') || text.contains('next')) {
      if (text.contains('sourate')) {
        await _nextQuran();
        _setAnswer("Je passe à la sourate suivante 📖");
      } else if (text.contains('adhkar')) {
        await _nextAdhkar();
        _setAnswer("Je passe aux adhkar suivants 🤍");
      } else {
        await _nextMusic();
        _setAnswer("Je passe à la musique suivante 🎵");
      }
    } else if (text.contains('stop') ||
        text.contains('arrête') ||
        text.contains('arrete')) {
      await _stopAudio();
      _setAnswer("D'accord, j'arrête la lecture.");
    } else if (text.contains('météo') ||
        text.contains('meteo') ||
        text.contains('temps')) {
      // Commande vocale météo → rafraîchit avec la position réelle
      await _refreshWeather();
      if (_weatherLoaded) {
        _setAnswer(
            "Il fait actuellement $_tempDisplay à $_detectedCity. $_weatherDescription.");
      } else {
        _setAnswer("Je n'arrive pas à récupérer la météo pour le moment.");
      }
    } else {
      await _askAI(cmd);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  GPT-4o VIA OPENROUTER
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _askAI(String message) async {
    try {
      setState(() => _isThinking = true);

      final String systemPrompt = """
Tu es Najma, une assistante IA intégrée dans un miroir connecté intelligent.
Tu réponds TOUJOURS en français, de façon concise, chaleureuse et naturelle.
Tu es utile, bienveillante et informée sur tous les sujets.

Contexte actuel :
- Date et heure : ${_now.day}/${_now.month}/${_now.year} à ${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}
- Météo à $_detectedCity : $_tempDisplay, $_weatherDescription
- Humeur détectée de l'utilisateur : $_currentMood
- Adapte ton ton selon l'humeur : si triste → réconfortant, si heureux → enthousiaste, si en colère → calme et posé, si neutre → amical.

Tu peux répondre à toutes les questions : actualités, science, histoire, cuisine, santé, blagues, poésie, conseils, etc.
Garde tes réponses courtes (2-4 phrases max) pour être affichées sur le miroir.
""";

      final List<Map<String, String>> messages = [
        {"role": "system", "content": systemPrompt},
      ];

      final recentConversation = _conversation.length > 10
          ? _conversation.sublist(_conversation.length - 10)
          : _conversation;

      for (final msg in recentConversation) {
        if (msg['text'] != null && msg['text']!.isNotEmpty) {
          messages.add({
            "role": msg['role'] == 'user' ? "user" : "assistant",
            "content": msg['text']!,
          });
        }
      }

      messages.add({"role": "user", "content": message});

      final response = await http.post(
        Uri.parse(_openRouterUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_openRouterApiKey",
          "HTTP-Referer": "http://localhost",
          "X-Title": "Smart Mirror Najma",
        },
        body: jsonEncode({
          "model": _openRouterModel,
          "messages": messages,
          "max_tokens": 300,
          "temperature": 0.7,
          "stream": false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawAnswer =
            data["choices"][0]["message"]["content"] as String? ??
                "Je n'ai pas compris.";

        final cleanAnswer = rawAnswer
            .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
            .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
            .replaceAll(RegExp(r'#{1,6} '), '')
            .trim();

        _setAnswer(cleanAnswer);
      } else {
        print("OpenRouter error ${response.statusCode}: ${response.body}");

        if (response.statusCode == 401) {
          _setAnswer("Clé API invalide. Vérifie ta configuration OpenRouter.");
        } else if (response.statusCode == 429) {
          _setAnswer("Limite de requêtes atteinte. Réessaie dans un instant.");
        } else {
          _setAnswer("Erreur serveur (${response.statusCode}). Réessaie.");
        }
      }
    } catch (e) {
      print("AI ERROR: $e");
      _setAnswer("Erreur de connexion à GPT-4o. Vérifie ta connexion internet.");
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  RESPONSE HANDLER
  // ────────────────────────────────────────────────────────────────────────────

  void _setAnswer(String text) {
    _aiResponse = text;
    _conversation.add({'role': 'assistant', 'text': _aiResponse});

    setState(() {
      _isThinking = false;
      _isListening = false;
    });

    _speak(_aiResponse);
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  DISPOSE
  // ────────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _speech.stop();
    _audioPlayer.dispose();
    _timer?.cancel();
    _emotionTimer?.cancel();
    _listenTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // ── Colonne gauche : heure, météo, humeur, conversation ──────────────
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Heure
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

                  // ── Météo géolocalisée ───────────────────────────────────────
                  GestureDetector(
                    onTap: _refreshWeather,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: _weatherLoaded
                          ? Row(
                              children: [
                                Icon(
                                  _weatherIconData(_weatherIcon),
                                  color: _weatherIconColor(_weatherIcon),
                                  size: 30,
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _tempDisplay,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      _weatherDescription,
                                      style: TextStyle(
                                        color: _weatherIconColor(_weatherIcon),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.white54,
                                          size: 11,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _detectedCity,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.refresh,
                                  color: Colors.white30,
                                  size: 16,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.cyanAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _locationStatus,
                                  style: const TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                    ),
                  ),
                  // ─────────────────────────────────────────────────────────────

                  const SizedBox(height: 20),

                  // Badge humeur
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

                  // Conversation
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

          // ── Colonne centrale : caméra ────────────────────────────────────────
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

          // ── Colonne droite : micro, réponse IA, rappels ──────────────────────
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isThinking)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Najma réfléchit...',
                            style: TextStyle(color: Colors.amber),
                          ),
                        ],
                      ),
                    ),

                  if (_aiResponse.isNotEmpty && !_isThinking)
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

                  if (_lastWords.isNotEmpty)
                    Text(
                      'Vous: $_lastWords',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 30),

                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            color: Colors.deepPurpleAccent, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'GPT-4o via OpenRouter',
                          style: TextStyle(
                            color: Colors.deepPurpleAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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

  // ────────────────────────────────────────────────────────────────────────────
  //  HELPERS
  // ────────────────────────────────────────────────────────────────────────────

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

