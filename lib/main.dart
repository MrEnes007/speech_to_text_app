import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

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
  bool _isWindows = false;
  List<stt.LocaleName> _localeNames = [];
  String _currentLocaleId = '';
  bool _isSpeechAvailable = false;
  bool _isInitializing = false;
  
  // Supported languages
  final List<Map<String, dynamic>> _supportedLanguages = [
    {'name': 'Turkish', 'localeId': 'tr_TR'},
    {'name': 'English', 'localeId': 'en_US'},
    {'name': 'German', 'localeId': 'de_DE'},
    {'name': 'French', 'localeId': 'fr_FR'},
  ];
  
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    // Web platformunda platform kontrolünü devre dışı bırak
    _isWindows = false;
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Başlangıçta yalnızca bir kez çağırılır
    _initSpeech();
  }

  @override
  void dispose() {
    _animationController.dispose();
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
                  locale.localeId.startsWith(lang['localeId'].split('_')[0]));
              }).toList();
              
              // Türkçe veya varsayılan dil seçimi
              var defaultLocale = _localeNames.firstWhere(
                (locale) => locale.localeId.startsWith('tr_'),
                orElse: () => _localeNames.firstWhere(
                  (locale) => locale.localeId.startsWith('en_'),
                  orElse: () => _localeNames.first,
                ),
              );
              
              _currentLocaleId = defaultLocale.localeId;
            });
          } else {
            // Dil listesi boş ise manuel olarak desteklenen dilleri ekle
            if (mounted) {
              setState(() {
                _currentLocaleId = 'en_US'; // Varsayılan olarak İngilizce
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
              _currentLocaleId = 'en_US'; // Hata durumunda İngilizce
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
            content: Text('Beklenmeyen hata: $e'),
            backgroundColor: Colors.red,
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

  Future<void> _listen() async {
    // Eğer konuşma tanıma özelliği başlatılmamışsa, tekrar başlat
    if (!_isSpeechAvailable) {
      await _initSpeech();
      if (!_isSpeechAvailable) return; // Başlatma başarısız olduysa çık
    }
    
    if (!_isListening) {
      setState(() => _isListening = true);
      _animationController.forward();
      
      try {
        // Web'de konuşma tanıma için ek kontrol
        if (kIsWeb) {
          await _speech.stop(); // Önce herhangi bir aktif oturum varsa durdur
        }
        
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
        ).then((available) {
          if (available != null && !available && mounted) {
            setState(() => _isListening = false);
            _animationController.reverse();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mikrofon erişimi sağlanamadı. İzinleri kontrol edin.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
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
              bool isSelected = false;
              if (_currentLocaleId.isNotEmpty) {
                isSelected = _currentLocaleId.startsWith(localeId.split('_')[0]);
              }
              
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
            if (_isWindows) 
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Chip(
                  label: Text(
                    'Windows',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: Colors.deepPurple,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initSpeech,
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
                          if (_currentLocaleId.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _currentLocaleId.split('_')[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_text.isNotEmpty && _text != 'Mikrofon butonuna dokunarak konuşmaya başlayın...')
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: _clearCurrentText,
                          tooltip: 'Metni Temizle',
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
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        height: 80 + (_soundLevel * 2),
        width: 80 + (_soundLevel * 2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: _isListening
                  ? Colors.red.withOpacity(0.3 + (_soundLevel / 150))
                  : _isSpeechAvailable ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
              spreadRadius: 4 + (_soundLevel / 10),
              blurRadius: 10 + (_soundLevel / 5),
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_soundLevel / 100) + (_animationController.value * 0.1),
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
            );
          },
        ),
      ),
    );
  }
}