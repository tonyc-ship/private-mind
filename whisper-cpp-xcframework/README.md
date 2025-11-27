# whisper.cpp XCFramework Integration

This local Swift Package wraps the whisper.cpp XCFramework for use in the PrivateMind project.

## Building the XCFramework

To build the latest whisper.cpp XCFramework:

1. Navigate to the whisper.cpp repository:
   ```bash
   cd /path/to/whisper.cpp
   ```

2. Run the build script:
   ```bash
   ./build-xcframework.sh
   ```

3. Copy the generated XCFramework:
   ```bash
   cp -R build-apple/whisper.xcframework ../private-mind/whisper-cpp-xcframework/WhisperFramework.xcframework
   ```

## Updating to a New Version

When you want to update to a newer version of whisper.cpp:

1. Pull the latest changes:
   ```bash
   cd whisper.cpp
   git pull
   ```

2. Rebuild the XCFramework:
   ```bash
   ./build-xcframework.sh
   ```

3. Copy the new XCFramework to this directory (as shown above).

## Note

The XCFramework must be present in this directory for the project to build. Make sure to add it to your repository or provide build instructions for your team.

The XCFramework's module name is `whisper`, so import it as: `import whisper`

