# Adana Otobus Takip

Bu proje, Adana toplu tasima kullanicilarina hat, durak, saat, aktarma ve canli takip odakli bir mobil deneyim sunmak icin gelistirilmektedir.

## Urun Vizyonu

- Kullaniciya en hizli ve en dogru sekilde uygun hat/yolculuk onerisi vermek.
- Favori durak ve hatlar uzerinden tek ekranda kritik bilgi gostermek.
- Konum tabanli karar destegi ile gidis/gelis yonunu otomatik tavsiye etmek.

## Yol Haritasi

### Faz 1 - Stabil Veri ve Temel Akis (Tamamlandi / Suruyor)

- Hat listesi, arama, hat detay sayfasi.
- Hat detaya gidis-donus secimi.
- Duraklarin haritada gosterimi.
- Saat ve durak bilgisinin gercek API ile alinmasi.

### Faz 2 - Favoriler Altyapisi (Tamamlandi)

- Favoriler sekmesi (UI iskeleti).
- Favori hat ekleme/silme.
- Favori durak ekleme/silme.
- Yerel kayit (offline saklama).

### Faz 3 - Konum ve Akilli Oneriler (Basladi)

- Kullanici konumunu canli alma.
- En yakin durak/hat hesaplama.
- Gidis/Donus yon onerisi.
- En uygun secenek puani: yuru + bekleme + toplam sure.

### Faz 4 - Tum Duraklar ve Aktarma Motoru

- Tum duraklari guncel listeleme.
- Direkt hat yoksa en iyi tek aktarma onerisi.
- Iki hattin birlestigi uygun duraklarin hesaplanmasi.

### Faz 5 - Yolculuk Asistani

- Kullanici otobuste mi tespiti (konum + hiz + rota yakinligi).
- Bir sonraki durak ve inis duragi tahmini.
- Aktarma aninda sonraki hatta gecis yardimi.

## Sprint Plani

### Sprint 1 (Mevcut)

- App shell kurulumu: Hatlar + Favoriler sekmesi.
- Favoriler sayfasi iskeleti.
- Hat detay ekraninda harita, durak, saat stabilizasyonu.

### Sprint 2

- Favori hat/durak veri modeli.
- Yerel depolama (kaydet/yukle).
- Favori listesinde canli saat gostergesi.

### Sprint 3

- Konum izinleri ve konum servisi. (Tamamlandi)
- En yakin durak hesaplama.
- Gidis/Donus otomatik tavsiye.

### Sprint 4

- Tum durak endpoint akisi ve UI.
- Baslangic-varis arasi direkt hat kontrolu.
- Aktarma onerisi (tek aktarma).

## Teknik Notlar

- Harita: OpenStreetMap + flutter_map.
- Saat verisi: stopBusTimeBusId.
- Durak/rota verisi: Kentkart pathInfo.
- Parserlar alan adi degisikliklerine toleransli tutulur.

## Sonraki Adim

1. Açık durak ve hat rotalarını yolculuk sayfalarında gerçek-zaman güncellemeleriyle göster.
2. Istatistik takip: sürüşleri ve tercih edilen rotaları kaydet.
3. Favoriler menüsüne sık kullanılan rotaları ekle.
