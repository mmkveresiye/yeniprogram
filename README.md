# MMK Bulut Veresiye Takip (Multi-Tenant SaaS)

Bu proje, tek bir web sitesi üzerinden birden fazla dükkan/esnaf müşterinizin kendi kullanıcı adı ve şifresiyle giriş yaparak **yalnızca kendi dükkanına ait verileri yönetebildiği**, sizin de **Yönetici (Admin)** olarak müşteri hesapları tanımlayabildiğiniz bulut tabanlı bir SaaS sistemidir.

---

## 📁 Proje Dosyaları

- `supabase_schema.sql` : Supabase veritabanında çalıştırılacak tüm SQL tabloları, RLS güvenlik kuralları ve Admin fonksiyonları.
- `index.html` : Web uygulamasının arayüzü (Giriş Ekranı, Yönetici Paneli, Cari, Ürün, Toptancı, Satış/Sepet vb.).
- `sw.js` : Çevrimdışı ve PWA desteği sağlayan Service Worker.

---

## 🚀 1. Adım: Supabase Kurulumu (2 Dakika)

1. [Supabase](https://supabase.com) hesabınıza giriş yapın ve projenizi açın.
2. Sol menüden **SQL Editor** simgesine (veya `>_` simgesi) tıklayın.
3. **`+ New Query`** butonuna basın.
4. Bu projedeki [`supabase_schema.sql`](supabase_schema.sql) dosyasının **tüm içeriğini** kopyalayıp SQL Editor'e yapıştırın.
5. Sağ alttaki yeşil **`Run`** butonuna basın.
6. *"Success. No rows returned"* mesajını gördüğünüzde tüm veritabanı, güvenlik politikaları ve yönetici fonksiyonları hazır demektir!

---

## 🔑 2. Adım: İlk Yönetici (Admin) Girişi

Veritabanı kurulduğunda otomatik olarak bir yönetici hesabı oluşturulur:
* **Kullanıcı Adı / E-posta:** `admin` (veya `admin@veresiye.local`)
* **Giriş Şifresi:** `Admin1234!*`

1. `index.html` sayfasını tarayıcınızda açın.
2. Kullanıcı Adı: `admin`, Şifre: `Admin1234!*` yazıp giriş yapın.
3. Sağ üstte turuncu **`👑 YÖNETİCİ PANELİ`** butonu görünecektir.
4. Bu butona tıklayarak:
   - Satış yapacağınız yeni müşteriler (dükkanlar) oluşturabilir,
   - Onlara kullanıcı adı ve şifre belirleyebilir,
   - Gerektiğinde dükkan hesaplarını dondurabilir veya şifrelerini güncelleyebilirsiniz.

---

## 👤 3. Adım: Müşteri (Esnaf) Nasıl Giriş Yapar?

Yönetici panelinden oluşturduğunuz bir müşteri (örneğin: kullanıcı adı: `yildizmarket`, şifre: `Yildiz123`):
1. Web sitenizi açar.
2. Kullanıcı Adı: `yildizmarket` ve şifresini yazar.
3. Giriş yaptığında:
   - Başlıkta kendi dükkan adı (`YILDIZ MARKET`) yazar.
   - Sadece kendi carilerini, ürünlerini ve toptancılarını görür.
   - Başka hiçbir dükkanın verisine erişemez (Supabase Row Level Security tarafından %100 izole edilmiştir).

---

## 🌐 4. Adım: GitHub'a Yükleme ve Yayına Alma

### GitHub'a Yükleme:
1. GitHub hesabınızda yeni bir repo (örneğin: `veresiye-takip`) oluşturun.
2. Proje klasörünüzde terminali açın:
```bash
git init
git add .
git commit -m "İlk SaaS Veresiye Sürümü"
git branch -M main
git remote add origin https://github.com/KULLANICI_ADINIZ/veresiye-takip.git
git push -u origin main
```

### Ücretsiz Canlıya Alma (Vercel):
1. [Vercel](https://vercel.com) sitesine GitHub hesabınızla giriş yapın.
2. **"Add New Project"** butonuna basın ve `veresiye-takip` reponuzu seçin.
3. **"Deploy"** butonuna basın.
4. 30 saniye içinde `https://veresiye-takip.vercel.app` gibi canlı ve SSL sertifikalı adresiniz hazır olacaktır!
