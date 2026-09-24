-- =====================================================================
--  Düzeltme: hareketler / toptanci_hareketleri tablosundaki "tarih"
--  kolonu "date" tipinde oluşturulmuştu, ama uygulama tarihi
--  "24.09.2026 13:39" gibi noktalı ve saatli bir METİN olarak
--  gönderiyor. Postgres bunu date'e çeviremeyince INSERT hata
--  veriyor, uygulama bunu "çevrimdışı" sanıp sessizce yutuyordu.
--  Bu da "işlem eklendi ama hareket görünmüyor" sorununa yol açıyordu.
--
--  Çözüm: kolonu text yap (uygulama zaten tarihi kendi formatında
--  metin olarak tutuyor, date'e hiç ihtiyaç yok).
-- =====================================================================

alter table public.hareketler
  alter column tarih type text using tarih::text;

alter table public.toptanci_hareketleri
  alter column tarih type text using tarih::text;
