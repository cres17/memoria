# Memoria

Memoria is a Flutter-based photo editing application focused on high-quality LUT-driven color transforms, real-time GPU previews, and an extensible editing pipeline for filters, crops, retouching and ML-powered features.

Key points:
- Cross-platform Flutter app (Android, iOS, Windows, Web)
- Real-time GPU preview for spatial transforms and editing tools
- LUT-based creative filters and a trainable ML pipeline (optional)

Quick start
1. Install Flutter (see https://flutter.dev) and required platform SDKs.
2. Get the repo:

```bash
git clone https://github.com/cres17/memoria.git
cd memoria
```

3. Restore any required assets or models (if you rely on ML tests).
4. Run the app (example for Android):

```bash
flutter pub get
flutter run -d emulator-5554
```

Running tests

```bash
flutter test
```

Notes
- Large optional assets (models, LUTs) may be archived outside the repo. See `removed_assets/` for recent archives.
- Some ML tests require native TFLite binaries on Windows and are skipped by default when missing.

Contributing
- Create a branch for your change, open a PR against `main`, and include tests for behavioral changes.

License
- Check the project root for licensing information.

Contact
- Maintainer: https://github.com/cres17
