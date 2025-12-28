import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'services/api_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation Aveugle',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const NavigationScreen(),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  // Services
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _audioRecorder = AudioRecorder();
  
  // État de l'application
  String _status = 'Prêt';
  bool _isRecording = false;
  bool _isNavigating = false;
  String? _destination;
  String? _currentInstruction;
  Timer? _gpsTimer;
  
  @override
  void initState() {
    super.initState();
    _initTts();
    _requestPermissions();
  }
  
  @override
  void dispose() {
    _gpsTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
  
  /// Initialise le Text-to-Speech
  void _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }
  
  /// Demande les permissions nécessaires
  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.location.request();
    await Permission.locationWhenInUse.request();
  }
  
  /// Parle à l'utilisateur et ATTEND que ça finisse
  Future<void> _speak(String text) async {
    print('🔊 TTS: $text');
    setState(() => _status = text);
    await _tts.speak(text);
    
    // Attendre un peu pour être sûr que le TTS finit
    await Future.delayed(Duration(milliseconds: (text.length * 50) + 1000));
  }
  
  /// Enregistre l'audio SANS parler pendant
  Future<String?> _recordAudio() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isRecording = true;
          _status = '🎤 Enregistrement en cours...';
        });
        
        // Obtenir le chemin du fichier
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String filePath = '${appDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        // Démarrer l'enregistrement IMMÉDIATEMENT
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: filePath,
        );
        
        // Enregistrer pendant 5 secondes
        await Future.delayed(const Duration(seconds: 5));
        
        // Arrêter l'enregistrement
        await _audioRecorder.stop();
        
        setState(() {
          _isRecording = false;
          _status = 'Traitement en cours...';
        });
        
        return filePath;
      }
    } catch (e) {
      print('❌ Erreur enregistrement: $e');
      setState(() {
        _isRecording = false;
        _status = 'Erreur d\'enregistrement';
      });
      await _speak('Erreur lors de l\'enregistrement');
    }
    return null;
  }
  
  /// ÉTAPE 1: Enregistrer et transcrire la destination
  Future<void> _startVoiceNavigation() async {
    try {
      // Annoncer et attendre
      await _speak('Dites votre destination après le bip');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Bip sonore (optionnel)
      // await SystemSound.play(SystemSoundType.click);
      
      // Enregistrer MAINTENANT (sans parler)
      final audioPath = await _recordAudio();
      if (audioPath == null) {
        await _speak('Impossible d\'enregistrer. Réessayez.');
        return;
      }
      
      await _speak('Merci, je traite votre demande');
      
      // Envoyer au backend pour transcription
      final response = await ApiService.transcribeAudio(audioPath);
      
      print('📥 Réponse transcription: $response');
      
      if (response['success'] != true) {
        final error = response['error'] ?? 'Erreur de transcription';
        await _speak(error);
        return;
      }
      
      final destination = response['destination'];
      final confirmationText = response['confirmation_text'];
      
      if (destination == null || destination.isEmpty) {
        await _speak('Je n\'ai pas compris la destination. Réessayez.');
        return;
      }
      
      setState(() => _destination = destination);
      
      // Lire la confirmation
      await _speak(confirmationText);
      
      // Demander confirmation
      await _confirmDestination();
      
    } catch (e) {
      print('❌ Erreur startVoiceNavigation: $e');
      await _speak('Erreur lors du traitement. Veuillez réessayer.');
    }
  }
  
  /// ÉTAPE 2: Confirmer la destination
  Future<void> _confirmDestination() async {
    try {
      // Annoncer
      await _speak('Dites oui pour confirmer ou non pour annuler');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Enregistrer la réponse
      final audioPath = await _recordAudio();
      if (audioPath == null) {
        await _speak('Impossible d\'enregistrer. Réessayez.');
        return;
      }
      
      await _speak('Traitement de votre réponse');
      
      // Envoyer au backend
      final response = await ApiService.confirmDestination(audioPath);
      
      print('📥 Réponse confirmation: $response');
      
      final confirmed = response['confirmed'] ?? false;
      final message = response['message'] ?? '';
      final needsRetry = response['needs_retry'] ?? false;
      
      if (needsRetry) {
        // Réponse ambiguë - redemander
        await _speak('Je n\'ai pas compris. Dites clairement oui ou non.');
        await _confirmDestination();
      } else if (confirmed) {
        // Confirmé - lancer la navigation
        await _speak('Parfait ! Je lance la navigation.');
        await _startNavigation();
      } else {
        // Refusé - recommencer
        await _speak('D\'accord. Quelle est votre destination ?');
        setState(() => _destination = null);
        await _startVoiceNavigation();
      }
      
    } catch (e) {
      print('❌ Erreur confirmDestination: $e');
      await _speak('Erreur lors de la confirmation. Réessayez.');
    }
  }
  
  /// ÉTAPE 3: Démarrer la navigation
  Future<void> _startNavigation() async {
    try {
      await _speak('Recherche de l\'itinéraire en cours');
      
      // Obtenir la position actuelle
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      print('📍 Position: ${position.latitude}, ${position.longitude}');
      
      // Obtenir l'itinéraire
      final route = await ApiService.getRoute(
        destination: _destination!,
        originLat: position.latitude,
        originLng: position.longitude,
      );
      
      print('📥 Réponse navigation: $route');
      
      if (route['success'] != true) {
        final error = route['error'] ?? 'Impossible de trouver l\'itinéraire';
        await _speak(error);
        setState(() {
          _destination = null;
          _status = 'Erreur de navigation';
        });
        return;
      }
      
      // Lire les instructions vocales
      final voiceInstructions = route['voice_instructions'] as List?;
      if (voiceInstructions != null && voiceInstructions.isNotEmpty) {
        for (var instruction in voiceInstructions) {
          await _speak(instruction.toString());
        }
      }
      
      // Lancer la boucle GPS temps réel
      setState(() => _isNavigating = true);
      _startGpsLoop();
      
    } catch (e) {
      print('❌ Erreur startNavigation: $e');
      await _speak('Impossible de trouver l\'itinéraire. Vérifiez votre connexion.');
      setState(() {
        _destination = null;
        _status = 'Erreur';
      });
    }
  }
  
  /// ÉTAPE 4: Boucle GPS temps réel
  void _startGpsLoop() {
    print('🚀 Démarrage boucle GPS');
    
    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        // Obtenir position GPS
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        print('📍 Position GPS: ${position.latitude}, ${position.longitude}');
        
        // Envoyer au backend
        final response = await ApiService.updatePosition(
          currentLat: position.latitude,
          currentLng: position.longitude,
          destination: _destination!,
        );
        
        print('📥 Mise à jour position: $response');
        
        if (response['success'] != true) {
          print('⚠️ Erreur mise à jour position');
          return;
        }
        
        final instruction = response['current_instruction'] ?? '';
        final stepCompleted = response['step_completed'] ?? false;
        final journeyCompleted = response['journey_completed'] ?? false;
        final message = response['message'] ?? '';
        
        // Si nouvelle instruction (étape complétée)
        if (stepCompleted && _currentInstruction != instruction) {
          print('✅ Nouvelle étape: $message');
          _currentInstruction = instruction;
          await _speak(message);
        }
        
        // Si arrivé à destination
        if (journeyCompleted) {
          print('🎉 Destination atteinte !');
          timer.cancel();
          setState(() {
            _isNavigating = false;
            _currentInstruction = null;
            _destination = null;
            _status = 'Arrivé à destination';
          });
          await _speak('Félicitations ! Vous êtes arrivé à destination.');
        } else {
          setState(() => _currentInstruction = instruction);
        }
        
      } catch (e) {
        print('❌ Erreur GPS loop: $e');
      }
    });
  }
  
  /// Arrêter la navigation
  void _stopNavigation() {
    print('🛑 Arrêt navigation');
    _gpsTimer?.cancel();
    setState(() {
      _isNavigating = false;
      _currentInstruction = null;
      _destination = null;
      _status = 'Navigation arrêtée';
    });
    _speak('Navigation arrêtée');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Titre
                const Text(
                  '🦯 Navigation',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
                
                // Statut
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Instruction actuelle
                if (_currentInstruction != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Text(
                      _currentInstruction!,
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                const SizedBox(height: 60),
                
                // GROS BOUTON PRINCIPAL
                GestureDetector(
                  onTap: _isRecording || _isNavigating
                      ? null
                      : _startVoiceNavigation,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? Colors.red
                          : _isNavigating
                              ? Colors.green
                              : Colors.blue,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording
                                  ? Colors.red
                                  : _isNavigating
                                      ? Colors.green
                                      : Colors.blue)
                              .withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording
                                ? Icons.mic
                                : _isNavigating
                                    ? Icons.navigation
                                    : Icons.record_voice_over,
                            size: 80,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isRecording
                                ? 'ÉCOUTE...'
                                : _isNavigating
                                    ? 'EN ROUTE'
                                    : 'PARLER',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Bouton STOP (si en navigation)
                if (_isNavigating)
                  ElevatedButton(
                    onPressed: _stopNavigation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 20,
                      ),
                    ),
                    child: const Text(
                      'ARRÊTER',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}