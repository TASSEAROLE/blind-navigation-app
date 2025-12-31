import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  // ⚠️ IMPORTANT: Pour émulateur Android, utilise http://10.0.2.2:8000
  // Pour téléphone physique sur même WiFi, utilise l'IP de ton PC (ex: http://192.168.1.10:8000)
  static const String baseUrl = 'http://10.2.6.181:8000';
  
  /// Transcrit un fichier audio en texte et extrait la destination
  static Future<Map<String, dynamic>> transcribeAudio(String audioPath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/speech/transcribe'),
      );
      
      // Ajouter le fichier audio
      request.files.add(
       await http.MultipartFile.fromPath(
       'audio', 
       audioPath,
      contentType: MediaType('audio', 'wav'),  // ✅ AJOUTÉ
       ),
      );
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur transcription: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur transcribeAudio: $e');
      rethrow;
    }
  }
  
  /// Confirme si l'utilisateur dit "Oui" ou "Non"
  static Future<Map<String, dynamic>> confirmDestination(String audioPath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/speech/confirm'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath(
        'audio', 
        audioPath,
        contentType: MediaType('audio', 'wav'),  // ✅ AJOUTÉ
        ),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur confirmation: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur confirmDestination: $e');
      rethrow;
    }
  }
  
  /// Obtient l'itinéraire depuis une destination textuelle
  static Future<Map<String, dynamic>> getRoute({
    required String destination,
    required double originLat,
    required double originLng,
  }) async {
    try {
      var response = await http.post(
        Uri.parse('$baseUrl/navigation/get-route'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'destination': destination,
          'origin_lat': originLat,
          'origin_lng': originLng,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur itinéraire: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur getRoute: $e');
      rethrow;
    }
  }
  
  /// Met à jour la position GPS en temps réel
  static Future<Map<String, dynamic>> updatePosition({
    required double currentLat,
    required double currentLng,
    required String destination,
  }) async {
    try {
      var response = await http.post(
        Uri.parse('$baseUrl/navigation/update-position'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'current_lat': currentLat,
          'current_lng': currentLng,
          'destination': destination,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Erreur position: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur updatePosition: $e');
      rethrow;
    }
  }
}