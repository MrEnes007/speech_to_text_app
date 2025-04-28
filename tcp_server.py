"""
TCP Socket Tabanlı Ses Tanıma Sunucusu
WebSocket yerine basit bir TCP soket kullanır
Bu Windows'taki bazı bağlantı sorunlarını çözebilir
"""

import socket
import threading
import time
import json
import sys
import os
import queue
import sounddevice as sd
from vosk import Model, KaldiRecognizer

# Ses tanıma kuyruğu
q = queue.Queue()

# Host ve port ayarları
HOST = '127.0.0.1'
PORT = 8765

# Model yolu kontrolü
model_path = "models/vosk-model-small-tr-0.3"
if not os.path.exists(model_path):
    print(f"❌ Hata: Model bulunamadı: {model_path}")
    print("📂 Lütfen modeli şu adresten indirin: https://alphacephei.com/vosk/models")
    print("📥 vosk-model-small-tr-0.3 modelini 'models' klasörüne çıkarın")
    sys.exit(1)

try:
    model = Model(model_path)
    rec = KaldiRecognizer(model, 16000)
    print(f"✅ Model başarıyla yüklendi: {model_path}")
except Exception as e:
    print(f"❌ Model yüklenirken hata oluştu: {e}")
    sys.exit(1)

def callback(indata, frames, time, status):
    """Mikrofon callback fonksiyonu"""
    if status:
        print(f"⚠️ Mikrofon durumu: {status}")
    q.put(bytes(indata))

def client_handler(client_socket, addr):
    """Yeni bir istemciden gelen bağlantıyı işler"""
    print(f"🔗 Yeni bağlantı: {addr}")
    
    # İstemciye hoş geldin mesajı gönder
    message = "Bağlantı başarılı. 'START_LISTENING' komutu göndererek başlayın."
    client_socket.send(message.encode('utf-8'))
    
    # Mikrofon stream
    stream = None
    is_listening = False
    buffer = ""
    
    try:
        while True:
            # İstemciden komut bekle
            try:
                # Veri alındı
                received_data = client_socket.recv(1024).decode('utf-8', errors='replace')
                if not received_data:
                    print("📤 İstemciden veri alınamadı, bağlantı kesilmiş olabilir.")
                    break
                
                # Alınan veriyi buffer'a ekle
                buffer += received_data
                
                # Satır sonları kontrolü
                commands = []
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if line.strip():  # Boş satırları atla
                        commands.append(line.strip())
                
                # Komutları işle
                for data in commands:
                    print(f"📥 İstemciden: {data}")
                    
                    if data == "START_LISTENING":
                        if is_listening:
                            print("🎙️ Dinleme zaten aktif")
                            continue
                        
                        print("🎙️ Dinleme başlatılıyor...")
                        is_listening = True
                        
                        # Mikrofon stream başlat
                        try:
                            # Varolan stream'i kapat
                            if stream:
                                stream.stop()
                                stream.close()
                            
                            # Yeni stream oluştur
                            stream = sd.RawInputStream(
                                samplerate=16000, 
                                blocksize=8000, 
                                dtype='int16',
                                channels=1, 
                                callback=callback
                            )
                            stream.start()
                            
                            # İstemciye bildirim gönder
                            client_socket.send("Dinleme başladı...".encode('utf-8'))
                            
                            # Ses tanıma döngüsü - paralel thread olarak başlat
                            recognition_thread = threading.Thread(
                                target=recognition_loop,
                                args=(client_socket, lambda: not is_listening)
                            )
                            recognition_thread.daemon = True
                            recognition_thread.start()
                            
                            print("✅ Mikrofon ve ses tanıma başarıyla başlatıldı!")
                        except Exception as e:
                            print(f"❌ Mikrofon başlatma hatası: {e}")
                            client_socket.send(f"Hata: Mikrofon başlatılamadı - {e}".encode('utf-8'))
                            is_listening = False
                        
                    elif data == "STOP_LISTENING":
                        print("🛑 Dinleme durduruluyor...")
                        is_listening = False
                        
                        if stream:
                            stream.stop()
                            stream.close()
                            stream = None
                        
                        # İstemciye bildirim gönder
                        client_socket.send("Dinleme durduruldu.".encode('utf-8'))
                        
                    elif data == "PING":
                        client_socket.send("PONG".encode('utf-8'))
                        
                    elif data == "CHECK_MIC":
                        # Mikrofon durumunu kontrol et ve bildir
                        try:
                            devices = sd.query_devices()
                            input_devices = [d for d in devices if d['max_input_channels'] > 0]
                            if input_devices:
                                client_socket.send(f"Mikrofon hazır: {len(input_devices)} aygıt bulundu.".encode('utf-8'))
                            else:
                                client_socket.send("Hata: Mikrofon bulunamadı!".encode('utf-8'))
                        except Exception as e:
                            client_socket.send(f"Mikrofon kontrol hatası: {e}".encode('utf-8'))
                    
                    else:
                        client_socket.send(f"Bilinmeyen komut: {data}".encode('utf-8'))
                
            except socket.timeout:
                # Timeout - bağlantı hâlâ aktif
                continue
    except Exception as e:
        print(f"❌ İstemci bağlantı hatası: {e}")
    finally:
        # Temizlik
        if stream:
            try:
                stream.stop()
                stream.close()
            except:
                pass
        
        try:
            client_socket.close()
        except:
            pass
        
        print(f"🔌 Bağlantı kapatıldı: {addr}")

def recognition_loop(client_socket, should_stop):
    """Ses tanıma döngüsü"""
    print("🎤 Mikrofon başlatıldı...")
    
    while not should_stop():
        if q.empty():
            time.sleep(0.1)  # CPU kullanımını azaltmak için kısa bekle
            continue
            
        data = q.get()
        if rec.AcceptWaveform(data):
            result = json.loads(rec.Result())
            text = result.get("text", "")
            if text:
                print(f"🗣️ Tanınan: {text}")
                try:
                    client_socket.send(text.encode('utf-8'))
                except:
                    print("❌ Metin gönderilemedi, bağlantı kopmuş olabilir")
                    break
        else:
            partial = json.loads(rec.PartialResult())
            partial_text = partial.get("partial", "")
            if partial_text:
                try:
                    client_socket.send(partial_text.encode('utf-8'))
                except:
                    print("❌ Kısmi metin gönderilemedi, bağlantı kopmuş olabilir")
                    break

def main():
    """Ana sunucu fonksiyonu"""
    try:
        # TCP soketi oluştur
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        # Server bağla
        server.bind((HOST, PORT))
        server.listen(5)
        
        print(f"✅ TCP sunucu başlatıldı - {HOST}:{PORT}")
        print("📱 Flutter uygulaması için bu adresi kullanın")
        print("🔄 CTRL+C ile çıkış yapabilirsiniz")
        
        # İstemci bağlantılarını bekle
        while True:
            client_socket, addr = server.accept()
            client_socket.settimeout(1.0)  # Soket timeout ayarı
            
            # Yeni bağlantı için thread başlat
            client_thread = threading.Thread(
                target=client_handler,
                args=(client_socket, addr)
            )
            client_thread.daemon = True
            client_thread.start()
            
    except KeyboardInterrupt:
        print("\n👋 Sunucu kapatılıyor...")
    except Exception as e:
        print(f"❌ Sunucu hatası: {e}")
    finally:
        if 'server' in locals():
            server.close()

if __name__ == "__main__":
    main() 