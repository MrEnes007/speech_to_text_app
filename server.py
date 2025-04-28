import asyncio
import websockets
import sounddevice as sd
import queue
import json
import sys
import os
from vosk import Model, KaldiRecognizer

q = queue.Queue()

# Model yolu kontrolü
model_path = "models/vosk-model-small-tr-0.3"
if not os.path.exists(model_path):
    print(f"❌ Hata: Model bulunamadı: {model_path}")
    print("📂 Lütfen modeli şu adresten indirin: https://alphacephei.com/vosk/models")
    print("📥 vosk-model-small-tr-0.3 modelini 'models' klasörüne çıkarın")
    sys.exit(1)

try:
    model = Model(model_path)  # Türkçe modelin güncel versiyonu kullanılıyor
    rec = KaldiRecognizer(model, 16000)
    print(f"✅ Model başarıyla yüklendi: {model_path}")
except Exception as e:
    print(f"❌ Model yüklenirken hata oluştu: {e}")
    sys.exit(1)

def callback(indata, frames, time, status):
    if status:
        print(f"⚠️ Mikrofon durumu: {status}")
    q.put(bytes(indata))

async def recognize(websocket):
    print(f"🔗 Yeni bağlantı: {websocket.remote_address}")
    
    # Mikrofon stream başlatma değişkeni
    stream = None
    is_listening = False
    
    try:
        # İlk bağlantıda bir karşılama mesajı gönder
        await websocket.send("Bağlantı başarılı. Mikrofon butonuna basarak konuşmaya başlayabilirsiniz.")
        
        # Client mesajlarını dinle
        async for message in websocket:
            if message == "START_LISTENING":
                print("🎙️ Dinleme başlatılıyor...")
                
                # Eğer dinleme zaten aktifse, tekrar başlatma
                if is_listening and stream:
                    print("🎙️ Dinleme zaten aktif")
                    continue
                    
                # Dinleme başlat
                is_listening = True
                
                # Mikrofon stream'i başlat
                stream = sd.RawInputStream(samplerate=16000, blocksize=8000, dtype='int16',
                                         channels=1, callback=callback)
                stream.start()
                
                print("🎤 Mikrofon başlatıldı...")
                
                # Ses tanıma işlemini başlat
                await websocket.send("Dinleme başladı...")
                
                # Ses dinleme döngüsünü başlat
                while is_listening:
                    if q.empty():
                        await asyncio.sleep(0.1)
                        continue
                        
                    data = q.get()
                    if rec.AcceptWaveform(data):
                        result = json.loads(rec.Result())
                        text = result.get("text", "")
                        if text:
                            print(f"🗣️ Tanınan: {text}")
                            await websocket.send(text)
                    else:
                        partial = json.loads(rec.PartialResult())
                        partial_text = partial.get("partial", "")
                        if partial_text:
                            await websocket.send(partial_text)
                
            elif message == "STOP_LISTENING":
                print("🛑 Dinleme durduruluyor...")
                is_listening = False
                
                if stream:
                    stream.stop()
                    stream.close()
                    stream = None
                    print("🎤 Mikrofon kapatıldı")
                    
                # Ses tanıma işlemini durdur
                await websocket.send("Dinleme durduruldu.")
                
            else:
                print(f"📥 İstemciden mesaj: {message}")
                
    except websockets.exceptions.ConnectionClosed:
        print(f"❌ Bağlantı kapandı: {websocket.remote_address}")
    except Exception as e:
        print(f"❌ Bağlantı hatası: {e}")
    finally:
        print(f"🔌 Bağlantı kapatıldı: {websocket.remote_address}")
        # Mikrofon stream'ini kapat
        if stream:
            stream.stop()
            stream.close()

async def main():
    host = "0.0.0.0"  # Localhost yerine tüm ağ arabirimleri dinleniyor
    port = 8765
    
    print(f"🔌 WebSocket sunucusu başlatılıyor... ws://{host}:{port}")
    print(f"📱 Flutter uygulaması için bağlantı adresi: ws://localhost:{port}")
    print(f"🔧 Sorun giderme için: ws://127.0.0.1:{port}")
    
    try:
        async with websockets.serve(recognize, host, port, ping_interval=None):
            print(f"✅ Sunucu hazır! Bağlantı için: ws://localhost:{port}")
            await asyncio.Future()  # Sonsuz bekle
    except Exception as e:
        print(f"❌ Sunucu başlatma hatası: {e}")
        
        # Port kullanımda mı kontrol et
        if "address already in use" in str(e).lower() or "in use" in str(e).lower():
            print("\n🔄 Port zaten kullanılıyor olabilir. Başka bir portu deneyeceğim...")
            
            # Alternatif port dene
            alt_port = 8766
            try:
                print(f"🔌 Alternatif port deneniyor: ws://{host}:{alt_port}")
                async with websockets.serve(recognize, host, alt_port, ping_interval=None):
                    print(f"✅ Sunucu alternatif portta hazır! Bağlantı için: ws://localhost:{alt_port}")
                    print(f"⚠️ Flutter uygulamasındaki adresi 'ws://localhost:{alt_port}' olarak değiştirmeyi unutmayın!")
                    await asyncio.Future()  # Sonsuz bekle
            except Exception as alt_e:
                print(f"❌ Alternatif port başlatma hatası: {alt_e}")
                print("\n🛠️ Manuel Çözüm:")
                print("1. server.py dosyasında port numarasını değiştirin")
                print("2. lib/main.dart dosyasında _serverAddress değişkenini güncelleyin")
        
        # Sorun giderme ipuçları
        print("\n🔍 Sorun Giderme İpuçları:")
        print("1. Güvenlik duvarı ayarlarınızı kontrol edin")
        print("2. Antivirüs programını geçici olarak devre dışı bırakın")
        print("3. Başka bir port deneyebilirsiniz (8765 yerine 8766, 8767 vb.)")
        print("4. Komut istemini (CMD) yönetici olarak çalıştırın")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n👋 Sunucu kapatılıyor...")
    except Exception as e:
        print(f"❌ Sunucu hatası: {e}") 