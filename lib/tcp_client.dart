import 'dart:io';
import 'dart:async';
import 'dart:convert';

class VoskTcpClient {
  Socket? _socket;
  final String host;
  final int port;
  
  // Dinleyiciler
  final void Function(String) onMessage;
  final void Function() onConnected;
  final void Function(String) onError;
  final void Function() onDisconnected;
  
  bool _isListening = false;
  bool get isConnected => _socket != null;
  bool get isListening => _isListening;
  
  VoskTcpClient({
    this.host = '127.0.0.1',
    this.port = 8765,
    required this.onMessage,
    required this.onConnected,
    required this.onError,
    required this.onDisconnected,
  });
  
  Future<bool> connect() async {
    try {
      print('TCP soket bağlantısı deneniyor: $host:$port');
      
      // Varolan soket varsa kapat
      await disconnect();
      
      // Soket bağlantısı kur
      _socket = await Socket.connect(host, port);
      
      // Veri dinlemeye başla
      _socket!.listen(
        // Veri geldiğinde
        (data) {
          final message = utf8.decode(data);
          print('TCP sunucudan: $message');
          onMessage(message);
        },
        
        // Hata oluştuğunda
        onError: (error) {
          print('TCP hata: $error');
          onError(error.toString());
          _socket = null;
        },
        
        // Bağlantı kapandığında
        onDone: () {
          print('TCP bağlantısı kapandı');
          _isListening = false;
          _socket = null;
          onDisconnected();
        },
      );
      
      // Bağlantı kuruldu
      print('TCP bağlantısı kuruldu: $host:$port');
      onConnected();
      
      return true;
    } catch (e) {
      print('TCP bağlantı hatası: $e');
      onError(e.toString());
      _socket = null;
      return false;
    }
  }
  
  // Bağlantıyı kapat
  Future<void> disconnect() async {
    if (_socket != null) {
      _isListening = false;
      await _socket!.close();
      _socket = null;
      print('TCP bağlantısı kapatıldı');
    }
  }
  
  // Dinlemeyi başlat
  void startListening() {
    if (_socket != null) {
      _socket!.write('START_LISTENING\n');
      _isListening = true;
      print('TCP üzerinden dinleme başlatılıyor');
    } else {
      onError('Dinleme için önce bağlantı kurulmalı');
    }
  }
  
  // Dinlemeyi durdur
  void stopListening() {
    if (_socket != null && _isListening) {
      _socket!.write('STOP_LISTENING\n');
      _isListening = false;
      print('TCP üzerinden dinleme durduruluyor');
    }
  }
  
  // PING mesajı gönder
  void ping() {
    if (_socket != null) {
      _socket!.write('PING\n');
    }
  }
  
  // Komut gönder
  void sendCommand(String command) {
    if (_socket != null) {
      _socket!.write('$command\n');
    } else {
      onError('Komut göndermek için bağlantı kurulmalı');
    }
  }
} 