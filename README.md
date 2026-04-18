# Smart Patrol Vision - Flutter Project

## Deskripsi
Aplikasi ini merupakan project Flutter yang memiliki fitur kamera dan pengolahan citra (*image processing / PCD*).  
Pengguna dapat mengambil gambar, mengolahnya dengan berbagai filter, serta menyimpan hasilnya ke galeri.

<br>

## Fitur Utama

### 1. Kamera (Vision)
- Preview kamera real-time
- Torch (flash)
- Overlay deteksi

### 2. Image Processing (PCD)
- Grayscale
- Brightness & Contrast
- Blur
- Sharpening
- Noise
- Edge Detection (Sobel)
- Binary Image
- Histogram

### 3. File Handling
- Capture gambar dari kamera
- Upload gambar dari galeri
- Simpan hasil ke galeri

<br>

## Cara Menjalankan Project

### 1. Buka project
Ekstrak file zip, lalu buka di **VS Code / Android Studio**

### 2. Install dependency
```bash
flutter pub get
```

### 3. Jalankan aplikasi
Pastikan emulator atau HP sudah terhubung, lalu jalankan:
```bash
flutter run
```
### 3. Jika terjadi error:
```bash
flutter clean
flutter pub get
flutter run
```

<br>

## Persyaratan

Sebelum menjalankan project ini, pastikan sudah terinstall:
- Flutter SDK
- Emulator Android atau perangkat Android (HP)

<br>

## Struktur Folder

```bash
lib/
├── features/
│   └── vision/
│       ├── vision_view.dart
│       ├── vision_controller.dart
│       ├── processing_view.dart
│       └── image_processor.dart
├── helpers/
├── services/
└── main.dart
```

<br>

## Zahra Aldila - 241511094
## Pengolahan Citra Digital 2026