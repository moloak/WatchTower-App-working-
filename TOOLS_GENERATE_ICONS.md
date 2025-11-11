Generate Android & iOS launcher icons

Prerequisites
- Ensure you have copied your source image to:

  assets/images/watchtower.png

  (See `assets/images/README_COPY_IMAGE.md` for a PowerShell one-liner.)

Steps (PowerShell)

```powershell
# From the project root (C:\Users\HELLO\Desktop\project_1)
flutter pub get
flutter pub run flutter_launcher_icons:main
```

Notes
- The generator will replace Android and iOS launcher icons. Keep a backup of your original icons if you need them.
- If the image has a background you may want to use an image with transparent background for adaptive icons or generate separate foreground/background images.
- If you prefer, I can run the generation for you here, but the generator will fail if `assets/images/watchtower.png` is not present. Tell me if you want me to run it now and whether the image is ready in the project path.
