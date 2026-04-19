# AdanaBus

AdanaBus, Adana toplu taşıma kullanıcıları için canlı otobüs takibi, durak odaklı analiz ve anlık yolculuk planlama sunan Flutter tabanlı bir mobil uygulamadır.

Bu doküman, uygulamanın neler yapabildiğini, hangi teknik fonksiyonları kullandığını ve veriyi nereden/nasıl çektiğini tek yerde açıklar.

## Eğitim Amacı Bildirimi

Bu proje yalnızca eğitim amacıyla geliştirilmiştir. Herhangi bir ticari amaç gütmemektedir.

## Uygulama Özeti

- Canlı otobüs verisini çekip harita üzerinde gösterir.
- Hat bazlı detay sayfasında güzergah, duraklar ve yaklaşan araç durumlarını sunar.
- Durak detayında, seçili durağa yakın durakları birleştirerek (300 m) daha doğru hat görünümü sağlar.
- Başlangıç-hedef seçimine göre anlık en hızlı yolculuk önerileri üretir.
- Favori hat, favori durak ve iki duraklı rota kayıtlarını cihazda saklar.

## Ekranlar ve Yapabildikleri

### 1) Ana Sayfa

- Favorileri üstte, en yakın durak bilgisini kart olarak gösterir.
- GPS ile konum alır ve en yakın durağı hesaplar.
- Durak kartından detay harita ekranına geçiş sağlar.

### 2) Hatlar

- Hat arama ve listeleme.
- Hat detayında gidiş-dönüş yönüne göre rota izleme.
- Canlı araç işaretleri ve seçili durağa yaklaşma bilgisi.

### 3) Durak Detay

- Durakta canlı yaklaşan hatları altta yatay kaydırma kartlarıyla gösterir.
- Haritada seçili hatta göre yaklaşma ve devam rotasını çizer.
- Birbirine yakın durakları tek grup olarak ele alır (300 m yarıçap).
- Gruptaki durakları üstte toplu bilgi kartında listeler.

### 4) Yolculuk Planlama

- Başlangıç ve hedef konumunu GPS veya harita seçimiyle alır.
- Canlı ve zaman bilgisini birleştirerek en hızlı seçenekleri sıralar.
- Sonuçları rota önizleme haritası ile destekler.

### 5) Favoriler

- Favori hat / favori durak / favori rota yönetimi.
- Yerel depolama ile uygulama yeniden açıldığında veriyi korur.

## Teknik Fonksiyonlar

Uygulamada öne çıkan teknik fonksiyon grupları:

- Canlı veri yenileme: belirli aralıklarla veri çekip arayüzü güncelleme.
- GPS tabanlı yakınlık hesapları: iki koordinat arası mesafe ölçümü ve en yakın durak bulma.
- Durak kümeleme: seçili durak merkez alınarak 300 m içindeki durakları birleştirme.
- Rota eşleme: Kentkart path noktalarında seçili durağa en yakın segmenti bulma.
- Yaklaşan araç filtreleme: seçili durağa henüz gelmemiş araçları ayıklama.
- ETA tahmini: araç-durak mesafesinden dakika tahmini üretme.
- Akıllı yolculuk puanlama: yürüme + bekleme + toplam süre metriklerini birlikte değerlendirme.
- Dayanıklı parser yaklaşımı: API alan adı farklılıklarına toleranslı çözümleme.

## Veri Kaynakları ve Veri Akışı

Uygulama veriyi iki ana kaynaktan alır:

### 1) Akıllı Kent API

- Token alma: https://akillikentapi.adana.bel.tr/api/token
- Canlı otobüsler: https://akillikentapi.adana.bel.tr/api/buses
- Yakın duraklar: https://akillikentapi.adana.bel.tr/api/nearByStops
- Durak saatleri (BusId): https://akillikentapi.adana.bel.tr/api/stopBusTimeBusId

### 2) Kentkart Path API

- Hat-güzergah bilgisi: https://service.kentkart.com/rl1/api/sep/pathInfo

### Veri Akışı Özeti

1. Uygulama token alır.
2. Canlı otobüs listesini çeker.
3. Gerekli ekranda hat ve yön bazlı path verisini çeker.
4. Durak/hat/otobüs verisini birleştirip arayüz katmanında işler.
5. Duruma göre fallback uygular veya önceki geçerli veriyi korur.

## Kullanılan Temel Teknolojiler

- Flutter (Dart)
- flutter_map + OpenStreetMap
- latlong2
- geolocator
- http
- shared_preferences
- sqflite

## Kurulum ve Çalıştırma

1. Flutter ortamını kurun.
2. Projeyi klonlayın.
3. Bağımlılıkları yükleyin:

```bash
flutter pub get
```

4. Uygulamayı çalıştırın:

```bash
flutter run
```

İsteğe bağlı olarak API bilgilerini `dart-define` ile gönderebilirsiniz:

```bash
flutter run --dart-define=ADANA_EMAIL=mail --dart-define=ADANA_PASSWORD=sifre --dart-define=KENTKART_TOKEN=token
```

## Ekran Görüntüleri

Bu bölüm güncelleniyor. Eklenecek görüntüler:

- Ana sayfa
- Hat detay
- Durak detay
- Yolculuk planlama sonucu
- Rota önizleme

Not: İlgili ekran görüntüleri bir sonraki dokümantasyon güncellemesinde eklenecektir.

## Uyarılar ve Bilinen Sınırlar

- API servislerindeki geçici yavaşlama veya kesinti, canlı veri tarafında gecikme oluşturabilir.
- Konum izni olmadan yakın durak ve GPS tabanlı planlama özellikleri sınırlı çalışır.
- ETA değerleri tahminidir; trafik yoğunluğu ve operasyonel değişiklikler fark yaratabilir.
- Harita verisi OpenStreetMap katmanına bağlıdır; anlık görüntü farklılıkları olabilir.

## Güvenlik Notu

- Üretim dağıtımında sabit kimlik bilgisi kullanılmamalı, güvenli yapılandırma tercih edilmelidir.
- Kimlik bilgileri sürüm kontrolüne açık şekilde eklenmemelidir.

## Yol Haritası ve Eklenecekler

- Ekran görüntüleri ve kullanım GIF'leri eklenecek.
- Daha detaylı teknik mimari diyagramı eklenecek.
- Test kapsamı ve CI notları eklenecek.
- Bildirimler, daha gelişmiş rota karşılaştırması ve performans optimizasyonları eklenecek.

## Lisans

Lisans bilgisi eklenecek.
