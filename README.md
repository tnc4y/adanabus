# AdanaBus

AdanaBus, Adana toplu tasima kullanicilari icin canli otobus takibi, durak odakli analiz ve anlik yolculuk planlama sunan Flutter tabanli bir mobil uygulamadir.

Bu dokuman, uygulamanin neler yapabildigini, hangi teknik fonksiyonlari kullandigini ve veriyi nereden nasil cektigini tek yerde aciklar.

## Uygulama Ozeti

- Canli otobus verisini cekip harita uzerinde gosterir.
- Hat bazli detay sayfasinda guzergah, duraklar ve yaklasan arac durumlarini sunar.
- Durak detayinda secili duraga yakin duraklari birlestirerek (300m) daha dogru hat gorunumu verir.
- Baslangic-hedef secimine gore anlik en hizli yolculuk onerileri olusturur.
- Favori hat, favori durak ve iki durakli rota kayitlarini cihazda saklar.

## Ekranlar ve Neler Yapabildigi

### 1) Ana Sayfa

- Favorileri ustte, en yakin durak bilgisini kart olarak gosterir.
- GPS ile konum alir ve en yakin durak hesaplar.
- Durak kartindan detay harita ekranina gecis saglar.

### 2) Hatlar

- Hat arama ve listeleme.
- Hat detayinda gidis-donus yonune gore rota izleme.
- Canli arac markerlari ve secili duraga yaklasma bilgisi.

### 3) Durak Detay

- Durakta canli yaklasan hatlari altta yatay kaydirma kartlari ile gosterir.
- Haritada secili hatta gore yaklasma ve devam rotasini cizer.
- Birbirine yakin duraklari tek grup olarak ele alir (300m yaricap).
- Gruptaki duraklari ustte toplu bilgi kartinda listeler.

### 4) Yolculuk Planlama

- Baslangic ve hedef konumunu GPS veya harita secimiyle alir.
- Canli ve zaman bilgilerini birlestirip en hizli secenekleri siralar.
- Sonuclari rota onizleme haritasi ile destekler.

### 5) Favoriler

- Favori hat / favori durak / favori rota yonetimi.
- Yerel depolama ile uygulama yeniden acildiginda veriyi korur.

## Teknik Fonksiyonlar

Uygulamada on plana cikan teknik fonksiyon gruplari:

- Canli veri yenileme: belirli araliklarla veri cekip UI guncelleme.
- GPS tabanli yakinlik hesaplari: iki koordinat arasi mesafe olcumu ve en yakin durak bulma.
- Durak kumeleme: secili durak merkez alinarak 300m icindeki duraklari birlestirme.
- Rota esleme: Kentkart path noktalarinda secili duraga en yakin segmenti bulma.
- Yaklasan arac filtreleme: secili duraga henuz gelmemis araclari ayiklama.
- ETA tahmini: arac-durak mesafesinden dakika tahmini uretme.
- Akilli yolculuk puanlama: yuru + bekleme + toplam sure metriklerini birlikte degerlendirme.
- Dayanikli parser yaklasimi: API alan adlari farkliliklarina toleransli map parse.

## Veri Kaynaklari ve Veri Akisi

Uygulama veriyi iki ana kaynaktan alir:

### 1) Akilli Kent API

- Token alma: https://akillikentapi.adana.bel.tr/api/token
- Canli otobusler: https://akillikentapi.adana.bel.tr/api/buses
- Yakin duraklar: https://akillikentapi.adana.bel.tr/api/nearByStops
- Durak saatleri (bus id): https://akillikentapi.adana.bel.tr/api/stopBusTimeBusId

### 2) Kentkart Path API

- Hat-guzergah bilgisi: https://service.kentkart.com/rl1/api/sep/pathInfo

### Veri Akisi Ozet

1. Uygulama token alir.
2. Canli otobus listesini ceker.
3. Gerekli ekranda hat ve direction bazli path verisini ceker.
4. Durak/hat/otobus verisini birlestirip UI katmanina isler.
5. Duruma gore fallback veya onceki gecerli veriyi korur.

## Kullanimda Olan Temel Teknolojiler

- Flutter (Dart)
- flutter_map + OpenStreetMap
- latlong2
- geolocator
- http
- shared_preferences
- sqflite

## Kurulum ve Calistirma

1. Flutter ortamini kurun.
2. Projeyi klonlayin.
3. Bagimliliklari yukleyin:

	flutter pub get

4. Uygulamayi calistirin:

	flutter run

Istege bagli olarak API bilgilerini dart-define ile gonderebilirsiniz:

flutter run --dart-define=ADANA_EMAIL=mail --dart-define=ADANA_PASSWORD=sifre --dart-define=KENTKART_TOKEN=token

## Ekran Goruntuleri

Bu bolum guncelleniyor. Eklenecek goruntuler:

- Ana sayfa
- Hat detay
- Durak detay
- Yolculuk planlama sonucu
- Rota onizleme

Not: Ilgili ekran goruntuleri bir sonraki dokumantasyon guncellemesinde eklenecektir.

## Uyarilar ve Bilinen Sinirlar

- API servislerinin gecici yavaslamasi veya kesintisi, canli veri tarafinda gecikme olusturabilir.
- Konum izni olmadan yakin durak ve GPS tabanli planlama ozellikleri sinirli calisir.
- ETA degerleri tahminidir; trafik yogunlugu ve operasyonel degisiklikler fark yaratabilir.
- Harita verisi OpenStreetMap katmanina baglidir; anlik goruntu farklari olabilir.

## Guvenlik Notu

- Uretim dagitiminda sabit kimlik bilgisi kullanilmamali, guvenli konfigurasyon tercih edilmelidir.
- Kimlik bilgileri surum kontrolune acik sekilde eklenmemelidir.

## Yol Haritasi ve Eklenecekler

- Ekran goruntuleri ve kullanim gifleri eklenecek.
- Daha detayli teknik mimari diyagrami eklenecek.
- Test kapsami ve CI notlari eklenecek.
- Bildirimler, daha gelismis rota karsilastirmasi ve performans optimizasyonlari eklenecek.

## Lisans

Lisans bilgisi eklenecek.
