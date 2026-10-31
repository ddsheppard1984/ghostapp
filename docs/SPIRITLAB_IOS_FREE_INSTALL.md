# SpiritLab — free iPhone native app build

This separate GitHub branch adds an unsigned iOS companion app. It connects to the existing private Lenovo URL https://sqeak--worker.tail7517d1.ts.net:8443/ when the phone's Tailscale is connected. The production database, recordings and Docker deployment are not changed.

## Build and install (no paid Apple developer membership)
1. Open the repo's Actions tab, then **SpiritLab iPhone IPA (unsigned)**. Open the successful run.
2. Download its \`SpiritLab-unsigned-iPhone-IPA\` artifact. Unzip it in Files to get \`SpiritLab-unsigned.ipa\`.
3. Follow the [SideStore installation guide](https://docs.sidestore.io/docs/installation/install). First-time setup uses Linux \`usbmuxd\` and \`iloader\`, a USB cable, trusting the computer on the iPhone, an Apple Account, and iPhone Developer Mode. These account actions must be done by the device owner, not ChatGPT.
4. Install the unsigned IPA through SideStore. SideStore signs it with your free Apple Account. Keep SideStore's LocalDevVPN enabled for installing and refreshing.
5. Start Tailscale on your phone, launch SpiritLab, and permit requested camera/motion/microphone access.

Apple free-device provisioning expires after 7 days, so refresh in SideStore. The CI build itself is unsigned and is **not directly installable**. No Apple ID or signing keys are uploaded to GitHub or the Lenovo.

## Sensors and limitations
- LiDAR depth only on LiDAR-capable iPhones and in the native app. ARKit depth is real optical depth; it does not detect ghosts or thermal emissions.
- Magnetic readings are from CoreMotion (µT), motion from CoreMotion, barometer from CMAltimeter. These are not physical RF radio frequencies.
- The worker remains private via Tailscale. Camera/depth buffers stay local to iOS; only numeric summaries are passed into the displayed SpiritLab webpage.
- The matching LiDAR controls in the Field Kit website may require a separately reviewed web update on the Lenovo. Existing Safari mode remains available.
- Actual iPhone installation and hardware behavior must be verified on the phone.

Source is public in the existing user-owned GitHub repo; keep credentials, pairing files and private evidence out of commits.
