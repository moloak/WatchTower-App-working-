Watchtower app logo - copy instructions

This repository expects the app logo to be present at:

  assets/images/watchtower.png

Please copy the PNG you provided (original location on your machine):

  C:\Users\HELLO\Downloads\Watchtower.png

into the project path above. You can run this PowerShell command from the project root to copy the file:

```powershell
# Run from: C:\Users\HELLO\Desktop\project_1
Copy-Item -Path "C:\Users\HELLO\Downloads\Watchtower.png" -Destination "assets\images\watchtower.png" -Force
```

After copying, run:

```powershell
flutter pub get
flutter clean; flutter pub get
```

Then rebuild the app. If you want me to also update Android and iOS launcher icons to use this image (multiple sizes needed), I can add instructions or generate icons, but I'll need confirmation before proceeding.
