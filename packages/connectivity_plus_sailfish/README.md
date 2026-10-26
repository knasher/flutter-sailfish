# connectivity_plus_sailfish

Sailfish OS implementation of
[connectivity_plus](https://pub.dev/packages/connectivity_plus).
Not published on pub.dev yet.

Without it, Sailfish apps use connectivity_plus's Linux version, which asks
NetworkManager. Sailfish OS uses ConnMan instead, so it failed.

Add it next to `connectivity_plus`; it registers itself:

```yaml
dependencies:
  connectivity_plus: ^6.1.5
  connectivity_plus_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/connectivity_plus_sailfish
```

It asks ConnMan over D-Bus for its connected services (state `ready` or
`online`) and maps their types:

| ConnMan | `ConnectivityResult` |
| --- | --- |
| `wifi` | `wifi` |
| `cellular` | `mobile` |
| `ethernet` | `ethernet` |
| `bluetooth` | `bluetooth` |
| `vpn` | `vpn` |
| anything else (`gadget`, `p2p`) | `other` |
| nothing connected | `none` |

The connection in use comes first. `onConnectivityChanged` sends the current
results when you start listening, then again whenever they change.

The app needs the `Internet` Sailjail permission, which includes asking
ConnMan:

```ini
[X-Sailjail]
Permissions=Internet
```
