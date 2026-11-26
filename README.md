# Bandit Pocket for iPhone

This independent iOS 17+ viewer connects directly to a TomTom Bandit on its Wi-Fi. The camera must report API version 2. It uses the viewfinder protocol and media endpoints documented by TomTom in BanditCameraKit-iOS. Only one device can use the live viewfinder at a time.

## Build with GitHub and install using Windows

1. Extract this archive and put the contents of the BanditPocket folder at the root of a dedicated GitHub repository. Include the hidden .github/workflows/ios.yml file.
2. Open Actions → Build iPhone viewer. A push triggers a build, or select Run workflow. After a successful run, download BanditPocket-unsigned from Artifacts and extract BanditPocket.ipa. A macOS runner is required for this build. Check your account’s Actions minutes before starting.
3. Install AltStore Classic on the iPhone using the official Windows instructions at https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows . With AltServer running and reachable, open AltStore Classic → My Apps → + and select the IPA from Files. Follow the signing and Developer Mode prompts. Free personal signing requires refreshing the installation every seven days.
4. Close the live viewer on other devices, connect the iPhone to the Bandit’s Wi-Fi and open Bandit Pocket. Tap Connect to Bandit and allow Local Network access. Use Recordings to list and play clips. The Live tab stops its stream when you leave it or put the app in the background.

## Build directly on macOS

Open BanditPocket.xcodeproj in Xcode, choose your personal team under Signing & Capabilities, set a unique bundle identifier and select your connected iPhone. Press Run.
