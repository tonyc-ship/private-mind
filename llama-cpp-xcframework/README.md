# llama.cpp XCFramework Integration

This local Swift Package wraps the llama.cpp XCFramework for use in the PrivateMind project.

## Building the XCFramework

To build the latest llama.cpp XCFramework:

1. Clone the llama.cpp repository:
   ```bash
   git clone https://github.com/ggml-org/llama.cpp.git
   cd llama.cpp
   ```

2. Run the build script:
   ```bash
   ./build-xcframework.sh
   ```

3. Copy the generated XCFramework:
   ```bash
   cp -R build/llama.xcframework ../private-mind/llama-cpp-xcframework/LlamaFramework.xcframework
   ```

   Or if the output is in a different location, adjust the path accordingly.

## Updating to a New Version

When you want to update to a newer version of llama.cpp:

1. Pull the latest changes:
   ```bash
   cd llama.cpp
   git pull
   ```

2. Rebuild the XCFramework:
   ```bash
   ./build-xcframework.sh
   ```

3. Copy the new XCFramework to this directory (as shown above).

## Note

The XCFramework must be present in this directory for the project to build. Make sure to add it to your repository or provide build instructions for your team.

