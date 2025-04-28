"""
Mikrofon Testi - ses algılama için basit bir test aracı

Bu script, bilgisayarınızdaki mikrofonu test etmenize yardımcı olur.
Varsayılan mikrofon girişinden ses kaydeder ve ses seviyesini gerçek zamanlı olarak gösterir.
"""

import sys
import time
import sounddevice as sd
import numpy as np

# Varsayılan ayarlar
SAMPLE_RATE = 16000  # Hz
CHANNELS = 1
DURATION = 10  # saniye
BLOCK_SIZE = 2048

def print_devices():
    """Kullanılabilir ses cihazlarını listeler"""
    print("\n--- Kullanılabilir Ses Cihazları ---")
    devices = sd.query_devices()
    
    # Ses giriş cihazlarını listele
    input_devices = []
    for i, device in enumerate(devices):
        if device['max_input_channels'] > 0:
            print(f"ID: {i}, Giriş: {device['name']}")
            input_devices.append(i)
    
    if not input_devices:
        print("❌ Mikrofon bulunamadı!")
        sys.exit(1)
    else:
        print(f"✅ Toplam {len(input_devices)} mikrofon bulundu.")
    
    return input_devices[0]  # İlk cihazı varsayılan olarak döndür

def audio_callback(indata, frames, time_info, status):
    """Ses verisi geldiğinde çağrılan fonksiyon"""
    if status:
        print(f"⚠️ Durum: {status}")
    
    # Ses seviyesini hesapla (RMS)
    volume_norm = np.linalg.norm(indata) * 10
    
    # Ses seviyesini çubuk grafiği olarak göster
    bar_length = int(volume_norm)
    bar = "█" * min(bar_length, 50) 
    
    # Terminal genişliğini hesapla
    try:
        from shutil import get_terminal_size
        terminal_width = get_terminal_size().columns
    except:
        terminal_width = 80
    
    # Çubuğu ekrana yazdır
    sys.stdout.write("\r" + " " * terminal_width)
    sys.stdout.write(f"\rSes Seviyesi: {volume_norm:.2f} | {bar}")
    sys.stdout.flush()

def test_microphone(device_id=None, duration=DURATION):
    """Mikrofondan ses alır ve seviyesini gösterir"""
    try:
        # Eğer cihaz ID verilmemişse, ilk mikrofonu kullan
        if device_id is None:
            device_id = print_devices()
        
        print(f"\n🎤 Mikrofon testi başlıyor... (Cihaz ID: {device_id})")
        print("🔊 Lütfen konuşun ve ses seviyesini gözlemleyin...")
        print("❓ Çıkmak için Ctrl+C tuşlarına basın.\n")
        
        # Kaydı başlat
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            device=device_id,
            blocksize=BLOCK_SIZE,
            callback=audio_callback
        ):
            # Belirtilen süre kadar bekle
            time.sleep(duration)
    
    except KeyboardInterrupt:
        print("\n\n👋 Mikrofon testi sonlandırıldı.")
    except Exception as e:
        print(f"\n❌ Hata: {e}")
        print("\nSorun Giderme:")
        print("1. Mikrofonunuzun bağlı olduğundan emin olun")
        print("2. Sisteminizde mikrofonun erişim izinlerini kontrol edin")
        print("3. Başka uygulamaların mikrofonu kullanmadığından emin olun")
        print("4. 'sounddevice' kütüphanesinin düzgün kurulduğundan emin olun:")
        print("   pip install sounddevice numpy")
        return False
    
    return True

if __name__ == "__main__":
    print("\n=== Mikrofon Testi ===")
    
    # Komut satırından parametre kontrolü
    if len(sys.argv) > 1:
        try:
            device_id = int(sys.argv[1])
            test_microphone(device_id)
        except ValueError:
            print(f"❌ Geçersiz cihaz ID: {sys.argv[1]}")
            print_devices()
    else:
        # Cihazları listele ve ilk mikrofonu test et
        result = test_microphone()
        
        if result:
            print("\n✅ Mikrofon testi tamamlandı. Ses algılandı.")
            print("\nBu test başarılıysa, 'server.py' dosyasını çalıştırarak")
            print("Flutter uygulamanızla konuşma tanımayı kullanabilirsiniz.")
            print("\nKomut: python server.py")
        else:
            print("\n❌ Mikrofon testi başarısız oldu.") 