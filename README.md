# Voxora

Aplicativo Android de transcrição por voz usando a OpenRouter e o modelo
`microsoft/mai-transcribe-1.5`.

## O que o app faz

- Grava áudio em WAV mono a 16 kHz (com fallback para M4A quando necessário).
- Transcreve gravações e arquivos de áudio pela API dedicada de Speech-to-Text da OpenRouter.
- Copia a transcrição automaticamente para a área de transferência por padrão.
- Mantém as últimas 100 transcrições localmente, com busca, cópia e exclusão.
- Guarda a chave da OpenRouter no Android Keystore por meio de armazenamento seguro.
- Aceita WAV, MP3, M4A, AAC, FLAC, OGG e WebM.

## Privacidade

A chave não é salva no histórico nem em preferências comuns. O áudio só é enviado
quando uma transcrição é iniciada. Ele segue para a OpenRouter e para o provedor do
modelo selecionado. O histórico de texto fica no aparelho.

## Desenvolvimento

Requisitos: Flutter 3.41 ou mais recente, JDK 17 e Android SDK 36.

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

O APK resultante fica em `build/app/outputs/flutter-apk/app-release.apk`.
