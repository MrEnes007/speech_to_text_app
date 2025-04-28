import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart';  // Sistem hata mesajları için
import 'tcp_client.dart';  // TCP istemcisini import ediyoruz

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpeechToTextApp());
}

class SpeechToTextApp extends StatelessWidget {
  const SpeechToTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konuşma Tanıma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SpeechScreen(),
    );
  }
}

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _text = 'Mikrofon butonuna dokunarak konuşmaya başlayın...';
  double _confidence = 1.0;
  double _soundLevel = 0.0;
  List<String> _history = [];
  late AnimationController _animationController;
  bool _isSpeechAvailable = false;
  bool _isInitializing = false;
  bool _isWindows = false;
  
  // WebSocket için değişkenler
  WebSocketChannel? _channel;
  bool _isConnectedToServer = false;
  String _serverAddress = 'ws://localhost:8765';
  
  // TCP istemcisi
  VoskTcpClient? _tcpClient;
  String _tcpHost = '127.0.0.1';
  int _tcpPort = 8765;
  
  // Desteklenen diller
  final List<Map<String, dynamic>> _supportedLanguages = [
    {'name': 'Turkish', 'localeId': 'tr-TR'},
    {'name': 'English', 'localeId': 'en-US'},
    {'name': 'German', 'localeId': 'de-DE'},
    {'name': 'French', 'localeId': 'fr-FR'},
  ];
  
  List<stt.LocaleName> _localeNames = [];
  String _currentLocaleId = '';
  
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    // Windows kontrolü
    if (!kIsWeb && Platform.isWindows) {
      print('Windows platformu algılandı');
      _isWindows = true;
      
      // Windows'ta speech_to_text yerine Vosk kullanılacak
      // Default olarak hazır olduğunu göstermeyelim
      _isSpeechAvailable = false;
      
      // 2 saniye bekleyip TCP bağlantısını deneyelim
      Future.delayed(const Duration(seconds: 2), () {
        // Windows'ta ise TCP bağlantısını otomatik dene
        _connectToTcpServer();
      });
      
    } else {
      print('Windows dışı platform algılandı, yerel konuşma tanıma kullanılacak');
    }
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Başlangıçta konuşma tanıma sistemini başlat (Windows dışı platformlar için)
    if (!_isWindows) {
      _initSpeech();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _disconnectFromTcpServer();
    super.dispose();
  }
  
  Future<void> _initSpeech() async {
    if (_isInitializing) return;
    
    setState(() {
      _isInitializing = true;
    });
    
    try {
      // Önce izinleri kontrol et
      if (!kIsWeb) {
        await _requestPermissions();
      }
      
      // Konuşma tanıma motorunu başlat
      _isSpeechAvailable = await _speech.initialize(
        onStatus: (status) {
          print('Durum: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
            }
            _animationController.reverse();
          }
        },
        onError: (errorNotification) {
          print('Hata: $errorNotification');
          if (mounted) {
            setState(() {
              _isListening = false;
              _isSpeechAvailable = false;
            });
            _animationController.reverse();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Hata oluştu: ${errorNotification.errorMsg}'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: 'Tekrar Dene',
                  onPressed: _initSpeech,
                ),
              ),
            );
          }
        },
        debugLogging: true,
      );
      
      if (_isSpeechAvailable) {
        // Kullanılabilir dilleri al
        try {
          var locales = await _speech.locales();
          
          if (mounted && locales.isNotEmpty) {
            setState(() {
              _localeNames = locales;
              
              // Filtre uygula - sadece desteklenen dilleri göster
              _localeNames = locales.where((locale) {
                return _supportedLanguages.any((lang) => 
                  locale.localeId.startsWith(lang['localeId'].split('-')[0]));
              }).toList();
              
              // Türkçe veya varsayılan dil seçimi
              var defaultLocale = _localeNames.firstWhere(
                (locale) => locale.localeId.startsWith('tr-'),
                orElse: () => _localeNames.firstWhere(
                  (locale) => locale.localeId.startsWith('en-'),
                  orElse: () => _localeNames.first,
                ),
              );
              
              _currentLocaleId = defaultLocale.localeId;
            });
          } else {
            // Dil listesi boş ise manuel olarak desteklenen dilleri ekle
            if (mounted) {
              setState(() {
                _currentLocaleId = 'en-US'; // Varsayılan olarak İngilizce
              });
            }
          }
        } catch (e) {
          print('Diller alınamadı: $e');
          if (mounted) {
            // Desteklenen dilleri manuel olarak oluştur
            setState(() {
              _localeNames = _supportedLanguages.map((lang) => 
                stt.LocaleName(lang['name'], lang['localeId'])).toList();
              _currentLocaleId = 'en-US'; // Hata durumunda İngilizce
            });
          }
        }
      } else {
        // Başlatma başarısız olduysa kullanıcıya bildir
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Konuşma tanıma başlatılamadı. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Tekrar Dene',
                onPressed: _initSpeech,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Başlatma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Beklenmeyen hata: $e\nPython Vosk sunucusu kullanmak için README.md dosyasını okuyun.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }
  
  Future<void> _requestPermissions() async {
    try {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mikrofon izni verilmedi. Ses tanıma çalışmayabilir.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('İzin hatası: $e');
    }
  }

  Future<void> _connectToTcpServer() async {
    // Eğer zaten bağlıysak önce bağlantıyı kapat
    if (_tcpClient != null) {
      await _disconnectFromTcpServer();
    }
    
    setState(() {
      _isInitializing = true;
    });
    
    // TCP istemcisi oluştur
    _tcpClient = VoskTcpClient(
      host: _tcpHost,
      port: _tcpPort,
      onMessage: (message) {
        // Sunucudan gelen metin
        setState(() {
          if (message.isNotEmpty) {
            _text = message;
            
            // Ses seviyesini simüle et
            _soundLevel = 5.0;
            
            // Eğer dinleme durdurulduysa geçmişe ekle
            if (!_isListening && message != 'Bağlantı başarılı. \'START_LISTENING\' komutu göndererek başlayın.' 
              && message != 'Dinleme başladı...' && message != 'Dinleme durduruldu.') {
              _addToHistory(message);
            }
          }
        });
      },
      onConnected: () {
        setState(() {
          _isConnectedToServer = true;
          _isInitializing = false;
          _isSpeechAvailable = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TCP Vosk sunucusuna bağlandı. Mikrofon butonuna basarak konuşmayı başlatabilirsiniz.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      },
      onError: (error) {
        setState(() {
          _isConnectedToServer = false;
          _isInitializing = false;
          _isSpeechAvailable = false;
          _isListening = false;
        });
        
        _animationController.reverse();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TCP bağlantı hatası: $error\nPython TCP sunucusunu başlattınız mı?'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Tekrar Dene',
              onPressed: _connectToTcpServer,
            ),
          ),
        );
      },
      onDisconnected: () {
        setState(() {
          _isConnectedToServer = false;
          _isInitializing = false;
          _isSpeechAvailable = false;
          _isListening = false;
        });
        
        _animationController.reverse();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TCP sunucusu ile bağlantı kesildi.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      },
    );
    
    // Bağlantıyı başlat
    await _tcpClient!.connect();
  }
  
  // TCP bağlantısını kapat
  Future<void> _disconnectFromTcpServer() async {
    if (_tcpClient != null) {
      await _tcpClient!.disconnect();
      _tcpClient = null;
      
      setState(() {
        _isConnectedToServer = false;
        _isListening = false;
      });
    }
  }

  Future<void> _listen() async {
    // Windows'ta TCP sunucusuna bağlanmayı dene
    if (_isWindows) {
      if (!_isConnectedToServer) {
        print('Windows: Sunucuya bağlı değil, bağlanmayı deniyorum...');
        // Eğer bağlı değilse bağlanmayı dene
        setState(() {
          _isInitializing = true;
        });
        
        await _connectToTcpServer();
        
        setState(() {
          _isInitializing = false;
        });
        
        if (!_isConnectedToServer) {
          print('Windows: Sunucuya bağlanılamadı, uyarı gösteriliyor');
          _showWindowsAlert();
          return;
        }
      }
      
      // Dinleme durumunu değiştir
      setState(() {
        _isListening = !_isListening;
        
        // Eğer dinliyorsa, HAZIR durumunda olsun
        if (_isListening) {
          _isSpeechAvailable = true;
        }
      });
      
      if (_isListening) {
        print('Windows: Dinleme başlatıldı, TCP Vosk sunucusu kullanılıyor');
        _animationController.forward();
        
        // Kullanıcıya bilgi verelim
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konuşun... TCP Vosk sunucusu dinliyor.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Windows'ta TCP dinleme durumunu sunucuya iletmek gerekiyor
        _tcpClient?.startListening();
      } else {
        print('Windows: Dinleme durduruldu');
        _animationController.reverse();
        
        // Sunucuya dinlemeyi durdur komutu gönder
        _tcpClient?.stopListening();
        
        // Eğer tanınan bir metin varsa, geçmişe ekleyelim
        if (_text.isNotEmpty && _text != 'Mikrofon butonuna dokunarak konuşmaya başlayın...') {
          _addToHistory(_text);
        }
      }
      return;
    }
    
    // Eğer Windows değilse standart speech_to_text işlemleri
    // Eğer konuşma tanıma özelliği başlatılmamışsa, tekrar başlat
    if (!_isSpeechAvailable) {
      await _initSpeech();
      if (!_isSpeechAvailable) return; // Başlatma başarısız olduysa çık
    }
    
    if (!_isListening) {
      setState(() => _isListening = true);
      _animationController.forward();
      
      try {
        await _speech.listen(
          onResult: _onSpeechResult,
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          onSoundLevelChange: (level) {
            if (mounted) {
              setState(() {
                _soundLevel = level;
              });
            }
          },
          localeId: _currentLocaleId,
          cancelOnError: true,
        );
      } catch (e) {
        print('Dinleme hatası: $e');
        if (mounted) {
          setState(() => _isListening = false);
          _animationController.reverse();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dinleme başlatılamadı: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        setState(() => _isListening = false);
      }
      _animationController.reverse();
      await _speech.stop();
    }
  }
  
  void _showWindowsAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Windows\'ta konuşma tanıma için Python sunucusuna bağlanmanız gerekiyor. '
          'Python ve Vosk kurulup "python server.py" komutu çalıştırılmalı.'
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Nasıl Yapılır?',
          onPressed: () => _pythonSetupInfo(),
        ),
      ),
    );
  }

  void _showServerSettings() {
    final TextEditingController _serverController = TextEditingController(text: _serverAddress);
    bool _isTesting = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Vosk Sunucu Ayarları'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _serverController,
                decoration: const InputDecoration(
                  labelText: 'WebSocket Sunucu Adresi',
                  hintText: 'ws://localhost:8765',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Not: Python sunucusunun çalıştığından emin olun.'),
              const SizedBox(height: 8),
              const Text('Sunucu başlatma komutu:'),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(6),
                color: Colors.black.withOpacity(0.05),
                child: const Text(
                  'python server.py',
                  style: TextStyle(fontFamily: 'monospace'),
                ),
              ),
              if (_isTesting)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Bağlantı test ediliyor...'),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: _isTesting ? null : () async {
                // Test bağlantısı için UI state güncelle
                setState(() {
                  _isTesting = true;
                });
                
                try {
                  print('Test bağlantısı yapılıyor: ${_serverController.text}');
                  final testChannel = WebSocketChannel.connect(Uri.parse(_serverController.text));
                  
                  // 2 saniye bekleyip bağlantıyı test et
                  await Future.delayed(const Duration(seconds: 2));
                  
                  // Eğer buraya kadar gelebildiyse, bağlantı başarılı
                  testChannel.sink.close();
                  
                  if (context.mounted) {
                    setState(() {
                      _isTesting = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bağlantı başarılı! Sunucu çalışıyor.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  print('Test bağlantı hatası: $e');
                  if (context.mounted) {
                    setState(() {
                      _isTesting = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Bağlantı başarısız: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Test Et'),
            ),
            ElevatedButton(
              onPressed: _isTesting ? null : () {
                final newAddress = _serverController.text;
                Navigator.pop(context);
                
                if (newAddress != _serverAddress) {
                  setState(() {
                    _serverAddress = newAddress;
                    _isConnectedToServer = false;
                  });
                }
                
                // Yeni adresle bağlanmayı dene
                _connectToTcpServer();
              },
              child: const Text('Bağlan'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        if (result.recognizedWords.isNotEmpty) {
          _text = result.recognizedWords;
        }
        
        if (result.hasConfidenceRating && result.confidence > 0) {
          _confidence = result.confidence;
        }
        
        // Konuşma tamamlandıysa geçmişe ekle
        if (result.finalResult && _text.isNotEmpty && 
            _text != 'Mikrofon butonuna dokunarak konuşmaya başlayın...') {
          _addToHistory(_text);
        }
      });
    }
  }
  
  void _addToHistory(String text) {
    if (text.trim().isEmpty) return;
    
    setState(() {
      // Aynı metin zaten geçmişte varsa, ekleme
      if (!_history.contains(text)) {
        _history.insert(0, text);
        // Geçmişi 5 öğe ile sınırlayalım
        if (_history.length > 5) {
          _history.removeLast();
        }
      }
    });
  }
  
  void _resetAll() {
    setState(() {
      _text = 'Mikrofon butonuna dokunarak konuşmaya başlayın...';
      _history.clear();
    });
  }
  
  void _clearCurrentText() {
    setState(() {
      _text = 'Mikrofon butonuna dokunarak konuşmaya başlayın...';
    });
  }
  
  void _pythonSetupInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Python Vosk Kurulumu'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Windows için Python ve Vosk kurulumu:'),
              SizedBox(height: 10),
              Text('1. Python\'u indirin ve kurun: python.org'),
              Text('   - Kurulum sırasında "Add Python to PATH" seçeneğini işaretleyin'),
              SizedBox(height: 10),
              Text('2. Gerekli paketleri yükleyin:'),
              Text('   pip install vosk websockets sounddevice'),
              SizedBox(height: 10),
              Text('3. Vosk modelini indirin:'),
              Text('   - https://alphacephei.com/vosk/models'),
              Text('   - "vosk-model-small-tr-0.3" modelini indirin'),
              Text('   - İndirilen dosyayı "models" klasörüne çıkarın'),
              SizedBox(height: 10),
              Text('4. server.py dosyasını çalıştırın:'),
              Text('   - Komut satırını (cmd) açın'),
              Text('   - Proje klasörüne gidin'),
              Text('   - python server.py komutunu çalıştırın'),
              SizedBox(height: 10),
              Text('Daha fazla bilgi için README.md dosyasına bakın.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showServerSettings();
            },
            child: const Text('Sunucu Ayarları'),
          ),
        ],
      ),
    );
  }
  
  void _selectLanguage() {
    // Desteklenen dilleri göstermek için bu metodu kullan
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dil Seçin'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _supportedLanguages.length,
            itemBuilder: (context, index) {
              final langInfo = _supportedLanguages[index];
              final localeId = langInfo['localeId'];
              final name = langInfo['name'];
              
              // Aktif dili bul
              bool isSelected = _currentLocaleId.startsWith(localeId.split('-')[0]);
              
              return ListTile(
                title: Text(name),
                subtitle: Text(localeId),
                selected: isSelected,
                onTap: () {
                  // Doğrudan desteklenen dil ID'sini kullan
                  setState(() {
                    _currentLocaleId = localeId;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Dil değiştirildi: $name'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🎙️ Ses Tanıma'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.deepPurple[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _currentLocaleId.split('-')[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.deepPurple[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isWindows)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _isConnectedToServer ? Colors.green[100] : Colors.blue[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isConnectedToServer ? 'VOSK' : 'WINDOWS',
                  style: TextStyle(
                    fontSize: 10,
                    color: _isConnectedToServer ? Colors.green[800] : Colors.blue[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isInitializing)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          if (_isWindows)
            IconButton(
              icon: Icon(_isConnectedToServer ? Icons.link : Icons.link_off),
              onPressed: _isConnectedToServer ? _disconnectFromTcpServer : _showServerSettings,
              tooltip: _isConnectedToServer ? 'Bağlantıyı Kes' : 'Sunucuya Bağlan',
            ),
          if (_isWindows)
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _pythonSetupInfo,
              tooltip: 'Python Kurulumu',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isWindows ? _connectToTcpServer : _initSpeech,
            tooltip: 'Yeniden Başlat',
          ),
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: _selectLanguage,
            tooltip: 'Dil Seçin',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _resetAll,
            tooltip: 'Tümünü Temizle',
          ),
        ],
      ),
      body: Column(
        children: [
          // Ana metin alanı
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              margin: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Tanınan Metin',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isSpeechAvailable ? Colors.green[100] : Colors.red[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _isSpeechAvailable ? 'HAZIR' : 'HAZIR DEĞİL',
                              style: TextStyle(
                                fontSize: 10,
                                color: _isSpeechAvailable ? Colors.green[800] : Colors.red[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (_text.isNotEmpty && _text != 'Mikrofon butonuna dokunarak konuşmaya başlayın...')
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: _clearCurrentText,
                              tooltip: 'Metni Temizle',
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _text,
                        style: const TextStyle(
                          fontSize: 22.0,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  if (_isListening && _confidence > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Text(
                        'Doğruluk: ${(_confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Geçmiş bölümü
          if (_history.isNotEmpty)
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                margin: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Geçmiş',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _history.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[300]),
                        itemBuilder: (context, index) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                            title: Text(
                              _history[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 20),
                                  onPressed: () => setState(() => _text = _history[index]),
                                  tooltip: 'Metni Geri Yükle',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: () => setState(() => _history.removeAt(index)),
                                  tooltip: 'Geçmişten Kaldır',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
          // Windows uyarısı
          if (_isWindows && !_isConnectedToServer)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Python Vosk Sunucusu Çalışmıyor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Windows\'ta konuşma tanıma için Python Vosk sunucusunun çalışması gerekiyor:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black.withOpacity(0.05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('1. Python yüklü değilse python.org\'dan indirin', style: TextStyle(fontSize: 13)),
                        const Text('2. Komut satırını (CMD) yönetici olarak açın', style: TextStyle(fontSize: 13)),
                        const Text('3. Aşağıdaki komutları çalıştırın:', style: TextStyle(fontSize: 13)),
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(6),
                          color: Colors.black,
                          child: const Text(
                            'pip install vosk websockets sounddevice',
                            style: TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace'),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(6),
                          color: Colors.black,
                          child: const Text(
                            'python server.py',
                            style: TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _pythonSetupInfo,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue[800],
                        ),
                        child: const Text('Detaylı Kurulum'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _connectToTcpServer,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.orange[700],
                        ),
                        child: const Text('Sunucuya Bağlan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_soundLevel / 100) + (_animationController.value * 0.1),
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: _isListening
                        ? Colors.red.withOpacity(0.3 + (_soundLevel / 150))
                        : _isSpeechAvailable ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                    spreadRadius: 4,
                    blurRadius: 10,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _isInitializing ? null : _listen,
                tooltip: _isListening ? 'Durdur' : 'Dinle',
                backgroundColor: _isListening
                    ? Colors.red.withOpacity(0.7 + (_soundLevel / 150))
                    : _isSpeechAvailable ? Colors.green : Colors.grey,
                elevation: 6.0,
                child: _isInitializing 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 32,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}