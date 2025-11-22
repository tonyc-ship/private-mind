# Configuration Guide

This project requires several configuration values to be set before building. These values should **never** be committed to version control.

## Required Configuration

Add the following keys to `PrivateMind/Info.plist` with your actual values:

### API Endpoints
- `TranscriptionAWSEndpoint`: AWS transcription service endpoint (e.g., `https://aws.example.com`)
- `TranscriptionTencentEndpoint`: Tencent transcription service endpoint (e.g., `https://tencent.example.com`)
- `SummaryEndpoint`: Summary generation service endpoint (e.g., `https://summary.example.com`)

## Setting Up Configuration

### Option 1: Direct Edit (Development)
1. Copy `PrivateMind/Info.plist.example` to `PrivateMind/Info.plist` (if not already present)
2. Open `PrivateMind/Info.plist` in Xcode
3. Replace the placeholder values with your actual configuration

### Option 2: Build Settings (Recommended for Production)
1. Create a `Config.xcconfig` file (add to `.gitignore`)
2. Define your configuration values there
3. Reference them in Info.plist using `$(CONFIG_KEY)` syntax

### Option 3: Environment Variables
For CI/CD pipelines, you can set these as environment variables and use a build script to inject them into Info.plist.

## Security Notes

- **Never commit** actual credentials or API keys to version control
- Use different keys for development, staging, and production
- Rotate keys regularly
- Consider using a secrets management service for production deployments

## Example Info.plist Entry

```xml
<key>TranscriptionAWSEndpoint</key>
<string>https://your-aws-endpoint.example.com</string>
<key>TranscriptionTencentEndpoint</key>
<string>https://your-tencent-endpoint.example.com</string>
<key>SummaryEndpoint</key>
<string>https://your-summary-endpoint.example.com</string>
```


