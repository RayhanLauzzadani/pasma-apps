# Setup Google Maps API Key

## Cara Setup:

### 1. Dapatkan Google Maps API Key:
   - Buka [Google Cloud Console](https://console.cloud.google.com/)
   - Pilih project `pasma-apps-8d37e`
   - Enable "Maps SDK for Android"
   - Buat API Key di **APIs & Services → Credentials**
   - **Restrict API Key:**
     - Application restrictions: Android apps
     - Package name: `com.example.pasma_apps`
     - API restrictions: Maps SDK for Android

### 2. Setup di Local Development:
   ```bash
   # Copy template .env
   cp .env.example .env
   
   # Edit .env dan isi dengan API key Anda
   GOOGLE_MAPS_API_KEY=AIzaSy...
   ```

### 3. Build & Run:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## Cara Kerja:

1. **File `.env`** menyimpan API key (tidak di-commit ke Git)
2. **`build.gradle.kts`** membaca `.env` dan inject ke manifest
3. **`AndroidManifest.xml`** menggunakan placeholder `${GOOGLE_MAPS_API_KEY}`
4. Saat build, placeholder diganti dengan nilai dari `.env`

## Untuk Tim Developer:

1. Clone repository
2. Copy `.env.example` ke `.env`
3. Minta API key ke project owner atau buat sendiri
4. Isi ke file `.env`
5. Build project

## Important Notes:

- ✅ File `.env` sudah di-gitignore
- ✅ `AndroidManifest.xml` menggunakan placeholder, aman di-commit
- ❌ **JANGAN commit file `.env`** ke GitHub
- ✅ Commit `.env.example` sebagai template
