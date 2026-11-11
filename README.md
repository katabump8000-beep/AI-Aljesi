# Dark GPT 1.0

Dark GPT is a Flutter Android-first AI workspace with:
- Local GGUF model downloads/import and model library.
- On-device inference using `flutter_local_llm` / llama.cpp.
- OpenAI-compatible API providers.
- Chat history, text-file attachments, file generation and ZIP packaging.
- Error center with copyable diagnostic reports.

## Setup
1. Put these files into the root of an existing Flutter project, replacing `pubspec.yaml`, `README.md`, `.gitignore`, `analysis_options.yaml`, and the `lib` directory.
2. Keep the Flutter-generated platform folders (`android`, and optionally `ios`).
3. Run `flutter pub get`.
4. Run `flutter run`.

## Local models
GGUF models are downloaded or imported into the app's private documents directory. Select one in Model Library and load it. Large models need substantial free storage and RAM. A 7B model may not run acceptably on a phone with limited RAM. The app does not claim every model format is supported: this local runtime supports GGUF through llama.cpp.

## API providers
The API screen supports OpenAI-compatible `/chat/completions` providers. Use the provider's base URL, model name, and API key. Keys are stored using platform secure storage. Never commit API keys to Git.

## File tools
The chat can attach readable text-based files and generate downloadable `.txt`, `.md`, `.json`, and `.zip` files. ZIP creation is local. This first complete app release does not execute generated code or run arbitrary shell commands on the phone. Review files before sharing or running them.

## Error reports
Open Diagnostics to copy a JSON report containing app version, platform, timestamp, error area, message, and stack trace. Do not share API keys or private file contents in public issue reports.

## Important limitations
- The model's reasoning quality depends on the selected model and its chat template.
- Vision/image understanding and image generation require a provider/model that supports those capabilities; this build does not pretend that a text-only GGUF model can see images.
- Web search is not automatically available to a model merely because it is connected to an API. Add a search provider/tool integration in a later release if required.
- Android local inference depends on the device ABI, available RAM, Android NDK/toolchain compatibility, and the native assets published by the selected plugin.
