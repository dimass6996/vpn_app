# Arbuz VPN Mobile (Flutter)

Current Flutter MVP scaffold for Arbuz VPN.

## Implemented folders

```text
lib/
  main.dart
  src/
    app.dart
    core/
      config/
      network/
      storage/
    features/
      app_shell/
      auth/
      home/
      subscription/
      configs/
      support/
      settings/
    shared/
```

## Current behavior

- App bootstraps from secure storage and attempts session restore on launch.
- Login screen requests OTP from the BFF.
- Verification screen accepts OTP received from configured delivery provider.
- Authenticated shell shows home, subscription, configs, support and settings tabs.
- Logout revokes the BFF session and clears local secure storage.
- Networking currently uses `dart:io` `HttpClient`.
- Unit/widget tests cover onboarding shell and controller flows:
  - bootstrap without session
  - pending challenge restore
  - authenticated restore
  - access token refresh after `401`
  - logout cleanup

## Checks

- `flutter analyze`
- `flutter test`

## Next implementation step

- Replace dev auth hints with provider-specific UX.
- Add native VPN import and connect flows per platform.
