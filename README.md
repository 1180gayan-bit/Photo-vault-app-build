# Hideout: a private photo & video vault for iPhone

Hideout keeps your private photos and videos in a locked space, separate from the built-in Photos app. Everything is encrypted and stays on your iPhone. Nothing is uploaded anywhere.

## What works in this first version

- **Lock with Face ID or Touch ID**, with a 6-digit passcode as backup. The passcode is separate from your iPhone passcode.
- **Too-many-tries protection**: after 5 wrong passcodes the keypad pauses, and the wait grows with each wrong try.
- **Auto-lock** when you leave the app (immediately, after 1 minute, or after 5 minutes), plus a cover screen so the vault doesn't show in the app switcher.
- **Import from Photos**: pick photos and videos, they're encrypted into the vault, then Hideout offers to delete the originals from Photos.
- **Albums**: create, rename, delete, rearrange, and choose a cover photo.
- **Viewer**: swipe through photos and videos, pinch or double-tap to zoom, play videos.
- **Move** items between albums, **delete** them, **share** them, or **save** them back to Photos.

## Coming in later versions

- Decoy vault (a second passcode that opens a harmless fake vault)
- Break-in alerts (a log of wrong passcode attempts, with an optional front-camera photo)
- In-app camera that saves straight into the vault
- Private web browser that downloads straight into the vault
- Optional encrypted backup and restore

## How to put the app on your iPhone

You need a **Mac** (Apple doesn't let you build iPhone apps on Windows) and a free Apple ID. A paid Apple Developer account ($99/year) is optional; without it the app works for 7 days at a time, and you just repeat step 6 to refresh it.

1. **Install Xcode.** Open the App Store on your Mac, search for **Xcode**, and install it (it's free but large, so it can take a while). You need Xcode 16 or newer.
2. **Download the code.** On this GitHub page, click the green **Code** button, then **Download ZIP**. Double-click the downloaded file to unzip it.
3. **Open the project.** In the unzipped folder, double-click **Hideout.xcodeproj**. Xcode opens.
4. **Sign in and pick your team.**
   - In Xcode's menu bar choose **Xcode > Settings > Accounts**, click **+**, and sign in with your Apple ID.
   - In the left sidebar click the blue **Hideout** project icon, then under **TARGETS** click **Hideout**, then the **Signing & Capabilities** tab.
   - Make sure **Automatically manage signing** is ticked, and choose your name in the **Team** menu.
   - If Xcode says the bundle identifier isn't available, change `com.gayan.hideout` to something unique, such as `com.yourname.hideout2`.
5. **Connect your iPhone.** Plug it into the Mac with a cable and unlock it. If the iPhone asks "Trust This Computer?", tap **Trust**. On iOS 16 and later, also turn on **Settings > Privacy & Security > Developer Mode** on the iPhone and restart it when asked.
6. **Run it.** At the top of the Xcode window, click the device menu and choose your iPhone, then press the **▶ (Run)** button. The first time, Xcode may take a few minutes.
7. **Trust the app on the iPhone** (first time only, free Apple ID). If the iPhone says "Untrusted Developer", go to **Settings > General > VPN & Device Management**, tap your Apple ID, then tap **Trust**. Open Hideout again.

Hideout then asks you to create a 6-digit passcode. **Don't forget it**: there's no way to recover it, and the vault can't be opened without it or your Face ID / Touch ID.

## Important to know

- **Deleting the app deletes the vault.** Because nothing goes to the cloud or into backups, the only copy of what you hide is inside Hideout on this iPhone. Save anything you want to keep back to Photos before deleting the app or changing phones.
- **When you delete originals from Photos**, iOS moves them to the **Recently Deleted** album in Photos. Empty that album too if you want them gone from Photos completely.
- To delete originals, Hideout needs access to your Photos library. If iOS asks, choose **Allow Full Access**.

## How it's built

- Swift and SwiftUI, for iOS 17 and later
- **LocalAuthentication** for Face ID / Touch ID
- **CryptoKit** (AES-256-GCM) to encrypt every photo, video, thumbnail and the album list. The encryption key and the passcode hash live in the iPhone's Keychain, marked "this device only", so they never sync to iCloud.
- Vault files use iOS Data Protection ("complete"), and are excluded from iCloud and computer backups.
- **PhotosUI / PhotoKit** for importing, deleting originals, and saving back to Photos
- **AVKit** for video playback

### Project layout

```
Hideout.xcodeproj         Xcode project (open this)
Hideout/App               App entry point and lock/unlock switching
Hideout/Security          Passcode, Face ID / Touch ID, Keychain, encryption key
Hideout/Storage           Encrypted file storage, albums and items, Photos library access
Hideout/Views             Screens: lock screen, albums, album grid, viewer, settings
```

A GitHub Action builds the app on every pull request to check that it compiles.
