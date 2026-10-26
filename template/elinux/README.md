# Sailfish tree for a Flutter app

```bash
cp -a template/elinux your_app/elinux
cp -a template/.sfosbuild your_app/.sfosbuild
cp -a template/rpm your_app/rpm
```

Rename `elinux/app.desktop.in` and `rpm/app.yaml.in` to the app's name. Set
`BINARY_NAME` in `elinux/CMakeLists.txt` (the same name) and
`FLUTTER_VERSION` in `elinux/flutter-sfos.env`. Then `./elinux/build.sh`.

`sfosbuild` packages the **app root** (Dart + `elinux/` + `rpm/`). ExtraInstall
runs `flutter-elinux build elinux` (engine/embedder `.so` swapped for ours).

The RPM installs the runner as `/usr/bin/$BINARY_NAME` and the bundle in
`/usr/share/$BINARY_NAME`, as Sailjail expects (see `docs/PORTING.md`,
"Sandboxing"). Engine `.so` files stay in `flutter-sfos-<ver>`; they are
removed from the app RPM.
