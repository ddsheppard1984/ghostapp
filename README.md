# OVULUS Field Lab

A GitHub Pages-ready, mobile-first paranormal investigation PWA inspired by the style of word/sensor ghost-hunting apps.

## Included

- **1,000,000-entry word bank** (`assets/dictionary.txt`)
- Cryptographically secure browser randomness (`crypto.getRandomValues`)
- Motion/accelerometer input when the browser exposes it
- Magnetometer/EMF-style reading when the device/browser exposes the Magnetometer API
- Anti-repeat session memory
- Paranormal-weighted, rare/unusual, balanced and pure-random modes
- Spoken word mode using the device's speech synthesis
- Investigation log stored in the current session
- Installable PWA / offline cache
- No backend, account, API key, or paid service required

## Important note about the 1,000,000 words

The bank starts from the locally available CMU pronunciation dictionary and expands it with deterministic grammatical/word-form variants and a small paranormal vocabulary. That gives the app exactly one million selectable entries, but it should **not** be described as one million independently validated dictionary headwords.

If you want a professionally licensed 1M+ lexical database later, replace `assets/dictionary.txt` with a properly licensed word list and keep the same one-word-per-line format.

## GitHub Pages

1. Create a new GitHub repository.
2. Upload everything in this folder.
3. Go to **Settings → Pages**.
4. Choose **Deploy from a branch**, select `main`, `/root`, then Save.
5. Open the generated GitHub Pages URL on your phone.
6. Use the browser's **Add to Home Screen** option to install it.

## Sensor limitations

A normal web app cannot reliably access every phone sensor. Magnetometer access is browser/device dependent and often requires HTTPS and permission. This app never claims that sensor fluctuations prove paranormal activity; they are used as additional entropy/input for the experimental word-selection engine.
