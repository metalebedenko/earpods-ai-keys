# Build and package

On macOS with Swift 6 / Command Line Tools:

```sh
/bin/sh app/build-app.sh release
```

The script creates a new bundle under `app/dist/`, strips debug symbol records from both release executables, and signs the helper followed by the app using an ad-hoc identity. Debug builds keep their symbols. It does not install or launch the result.

Package the printed bundle path with a new output filename:

```sh
python3 app/package-dmg.py '/path/EarPods AI Keys.app' '/path/EarPods-AI-Keys.dmg'
```

Packaging uses Python 3's standard library, macOS disk-image tools and a small build-time CoreServices helper. The app has no Python dependency. The packager refuses an existing output or a path inside an app bundle. It validates checksum, read-only mounting, bundle bytes and signature, the Applications link and native background alias, then detaches its own images. Its detailed report stays in ignored `app/.build/` because it contains local paths.

Before distributing a new build, inspect its own executables/resources for private build paths and secrets, verify `codesign --verify --strict --deep`, record the final DMG hash and visually check the mounted layout. Debug-symbol stripping does not provide Developer ID signing or Apple notarization. Follow the [first-launch instructions](../README.md#install-and-use).

Run software checks from the repository root:

```sh
/bin/sh app/test.sh
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s app/Tests -p 'test_package_dmg.py' -v
```

The shell tests use local doubles; the native tests cover core, management and bounded command behavior. Physical button, login and uninstall acceptance remains separate. See [verification](verification.md).

The initial public preview was prepared from the physically tested build 3 by stripping only symbol records, re-signing helper → app and repackaging it. A section-level comparison confirms identical runtime content; see [public release manifest](../app/validation/public-release.json). Earlier private ZIP/DMG files are not the public release assets.
