# Whisper Integration Guide

This project now supports on-device transcription using OpenAI's Whisper model via the `llamaforked` package.

## Setup Instructions

### 1. Add llamaforked Package Dependency

1. Open `PrivateMind.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter the repository URL: `https://github.com/yyyoungman/llamaforked`
4. Select the latest version and click **Add Package**
5. Make sure the `llamaforked` product is added to your PrivateMind target

### 2. Add Whisper Model File

You need to add a Whisper model file to your app bundle:

1. Download a Whisper model (recommended: `ggml-base.en-q5_0.bin` for English)
   - You can find models at: https://huggingface.co/ggerganov/whisper.cpp
   - For other languages, download the appropriate model (e.g., `ggml-base.zh-q5_0.bin` for Chinese)

2. In Xcode:
   - Create a folder group called `whisper` in your project
   - Add the model file to this folder
   - Make sure the file is added to the PrivateMind target
   - The file should be accessible at: `Bundle.main.url(forResource: "ggml-base.en-q5_0", withExtension: "bin", subdirectory: "whisper")`

### 3. Using Whisper Transcription

The app now supports two transcription methods:

- **WebSocket (Online)**: Uses your configured API endpoints (default)
- **Whisper (On-device)**: Runs entirely on the device, no internet required

To switch between methods:
1. Start recording a new note
2. Tap the language selector menu
3. Choose "Whisper (On-device)" or "WebSocket (Online)"
4. Your preference will be saved for future recordings

## Model Size Considerations

- **Base model (ggml-base)**: ~150MB - Good balance of accuracy and size
- **Small model (ggml-small)**: ~500MB - Better accuracy, larger file
- **Tiny model (ggml-tiny)**: ~75MB - Faster, less accurate

The current implementation uses the base model. You can change the model by:
1. Updating the `modelUrl` property in `WhisperTranscribeService.swift`
2. Adding the new model file to your bundle

## Language Support

Whisper supports many languages. The current implementation maps language codes like "en-US" to "en", "zh-CN" to "zh", etc.

Supported languages include: en, zh, de, es, ru, ko, ja, pt, and many more. See the Whisper documentation for the full list.

## Memory Management

The Whisper model uses approximately 300MB of memory when loaded. The implementation automatically:
- Loads the model when recording starts
- Releases the model after transcription completes
- Uses VAD (Voice Activity Detection) to optimize transcription timing

## Troubleshooting

### Model Not Found Error
- Ensure the model file is in the `whisper` folder in your bundle
- Check that the file is added to the PrivateMind target
- Verify the filename matches what's expected in `WhisperTranscribeService.swift`

### Transcription Not Working
- Check that the `llamaforked` package is properly linked
- Ensure microphone permissions are granted
- Verify the model file is not corrupted

### Performance Issues
- Use a smaller model (tiny) for faster transcription
- Reduce the transcription interval in `WhisperTranscribeService.swift`
- Consider using WebSocket transcription for real-time streaming

