# Photo Vault (iOS)

A private photo and video vault for iPhone. It keeps your sensitive photos and videos in a separate, locked space that's apart from the built-in Photos app.

## Planned features

- **Biometric lock**: Face ID / Touch ID, with a PIN or passcode fallback
- **Import from Photos**: move photos and videos into the vault, with an option to delete the originals from the Photos library
- **Albums**: create, rename, reorder, and set album covers
- **Built-in camera**: capture straight into the vault without touching the camera roll
- **Encrypted storage**: files encrypted at rest with keys held in the Secure Enclave / Keychain
- **Decoy vault**: a second PIN opens a harmless decoy vault
- **Break-in alerts**: record failed unlock attempts (time, and optionally a front-camera photo)
- **Auto-lock**: lock when the app goes to the background or after a timeout
- **Private browser**: download images from the web directly into the vault
- **Export and share**: send items back to Photos or share them via the share sheet
- **Backup and sync**: optional encrypted backup and restore across devices

## Tech stack

- Swift, SwiftUI
- LocalAuthentication (Face ID / Touch ID)
- CryptoKit and Keychain for encryption
- PhotoKit for import and export
- AVFoundation for the in-app camera and video playback

## Status

Early planning. No code yet.
