# Flutter Sticker Maker example

The `example` app is mainly used to exercise the plugin in a realistic setting and to
run the device-only integration suite.

## Run the integration tests on a physical device

1. Connect an Android or iOS device (or start an emulator/simulator).
2. Run the test suite from the `example` directory:

```bash
cd example
flutter test integration_test/flutter_sticker_maker_integration_test.dart -d <device-id>
```

Replace `<device-id>` with the ID returned by `flutter devices`. Omitting the `-d` flag
uses the first available device. The command launches the integration test bundle on the
selected device and executes the full sticker generation workflow end-to-end.

To run the native performance benchmarks (executes the real `NativeMaskProcessor`
implementation on-device), invoke:

```bash
cd example
flutter test integration_test/native_mask_performance_integration_test.dart -d <device-id>
```

This prints the measured timings and sanity-checks the native mask pipeline for multiple
image sizes.
