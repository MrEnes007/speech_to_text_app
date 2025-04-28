# Windows ve Flutter ile Vosk Konuşma Tanıma Uygulaması

Bu uygulama, tamamen çevrimdışı çalışabilen bir konuşma tanıma sistemi sunar. Python tarafında Vosk kütüphanesi kullanarak mikrofon girişini dinler ve WebSocket üzerinden Flutter uygulamasına gönderir.

## Kurulum

### 1. Python Tarafı (WebSocket Sunucusu)

**Gerekli Python Paketleri:**

```bash
pip install vosk websockets sounddevice
```

**Modeller:**
- Türkçe: https://alphacephei.com/vosk/models adresinden "vosk-model-small-tr-0.3" modelini indirin
- İngilizce ve diğer diller için de ilgili modelleri indirebilirsiniz

Model dosyasını indirdikten sonra, `models` klasörüne çıkartın. Klasör yapısı şöyle olmalıdır:

```
models/
└── vosk-model-small-tr-0.3/
    ├── README
    ├── final.mdl
    ├── ... (diğer model dosyaları)
```

### 2. Flutter Tarafı

Flutter uygulaması için gerekli bağımlılıkları yükleyin:

```bash
flutter pub get
```

## Kullanım

### 1. Sunucuyu Başlatın:

```bash
python server.py
```

Sunucu başlatıldığında şu mesajları görmelisiniz:
```
✅ Model başarıyla yüklendi: models/vosk-model-small-tr-0.3
🔌 WebSocket sunucusu başlatılıyor... ws://localhost:8765
✅ Sunucu hazır! Bağlantı için: ws://localhost:8765
🎤 Mikrofon başlatıldı...
```

### 2. Flutter Uygulamasını Çalıştırın:

```bash
flutter run -d windows
```

### 3. Uygulama Özellikleri:

- **Mikrofon Butonu**: Ses tanımayı başlatır/durdurur
- **Bağlantı Düğmesi**: Websocket bağlantısını açar/kapatır
- **Ayarlar**: Sunucu adresini değiştirmek için kullanılır
- **Dil Seçimi**: Desteklenen dilleri değiştirin (Not: Python tarafında da ilgili dil modelinin yüklü olması gerekir)
- **Geçmiş**: Tanınan metinler kayıt altına alınır

## Windows Entegrasyonu

Uygulama otomatik olarak Windows platformunu algılar ve şu özellikleri sunar:

1. WebSocket sunucusuna otomatik bağlanma denemesi
2. Bağlantı durumunu gösterme
3. Bağlantı ayarlarını değiştirme

## Sorun Giderme

1. WebSocket bağlantı hatası alıyorsanız:
   - Python sunucusunun çalıştığından emin olun
   - Bağlantı adresinin doğru olduğunu kontrol edin (`Bağlantı` butonuna tıklayarak)
   - Güvenlik duvarı ayarlarını kontrol edin

2. Model bulunamadı hatası:
   - Doğru modelin indirildiğini kontrol edin
   - Model dosyalarının doğru klasörde olduğunu kontrol edin
   - Model adının `server.py` dosyasındaki ayarla uyuştuğunu kontrol edin

3. Mikrofon hatası:
   - Mikrofonunuzun açık ve çalışır durumda olduğundan emin olun
   - Gerekli izinlerin verildiğini kontrol edin

## Lisans

Bu uygulama açık kaynaklıdır.

- Vosk Kütüphanesi: Apache 2.0 lisansı altında
- Flutter Uygulaması: MIT lisansı altında

## Notlar

- Windows'ta tamamen çevrimdışı çalışan bir sistem kurabilmek için Python ve Vosk kullanılmıştır
- Flutter uygulaması WebSocket üzerinden Python sunucusuyla iletişim kurar
- Sistem kurulumu tamamlandıktan sonra internet bağlantısı gerektirmez
