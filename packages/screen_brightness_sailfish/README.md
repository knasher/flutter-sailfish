# screen_brightness_sailfish

Sailfish OS implementation of
[screen_brightness](https://pub.dev/packages/screen_brightness).
Not published on pub.dev yet.

screen_brightness has no Linux version, so without this its calls fail on
Sailfish OS.

Add it next to `screen_brightness`; it registers itself:

```yaml
dependencies:
  screen_brightness: ^2.1.9
  screen_brightness_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/screen_brightness_sailfish
```

No Sailjail permission is needed: every app may talk to MCE, Sailfish OS's
display service.

## Application brightness

Sailfish OS has no brightness of an app's own, as Android has. So application
brightness works as on iOS, by changing the phone's brightness setting:

- `setApplicationScreenBrightness` saves the phone's brightness and automatic
  brightness, turns automatic brightness off and sets the brightness. While
  it's set, Settings > Display shows it.
- The phone's settings come back on `resetApplicationScreenBrightness`, while
  the app is in the background (auto reset, on by default; the app's
  brightness returns when it comes back), and, if the app was killed with
  them changed, the next time it starts.
- A setting the user changes meanwhile is left as they set it.

The saved settings are kept in `screen_brightness_sailfish.json` in the app's
data folder. `setAnimate` has no effect: MCE fades brightness changes itself.

## System brightness

`system`, `setSystemScreenBrightness` and `onSystemScreenBrightnessChanged`
use MCE's brightness setting directly (1–100 there, 0.0–1.0 here).
