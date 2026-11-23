# Lumi Camera — projeto preparado para build remoto

Este ZIP contém o código Swift original reorganizado e os arquivos que faltavam para formar uma estrutura XcodeGen.

## Estado e limitações

- O código ainda **não foi compilado nem executado**: este ambiente não possui Xcode/macOS.
- Implementado no código: câmera AVFoundation, preview com filtro leve, captura, perfis, pipeline Core Image, armazenamento, galeria e reprocessamento.
- O app exige iOS 17 ou superior e um iPhone real para validar captura.
- O build de arquivo/IPA distribuível exige assinatura Apple. O workflow de exemplo arquiva sem assinatura e não promete IPA instalável.
- Alguns recursos do README original continuam fora do escopo (editor avançado, importação, RAW, controles manuais de ISO/obturador, receitas e presets criados pelo usuário).

## Gerar projeto Xcode
Em um Mac com Xcode e XcodeGen:

```bash
brew install xcodegen
xcodegen generate
open LumiCamera.xcodeproj
```

No Xcode, selecione um Team em Signing & Capabilities, altere o Bundle Identifier se necessário, conecte um iPhone e compile.

## Build remoto (exemplo Codemagic)
1. Faça upload do projeto para um repositório Git.
2. Conecte o repositório ao Codemagic.
3. Use `codemagic.yaml` como workflow inicial e ajuste o fluxo de assinatura de acordo com a conta Apple.
4. O workflow incluído gera um archive sem assinatura. Para IPA instalável/TestFlight, configure certificados, provisioning profile e App Store Connect.

Não forneça credenciais Apple a terceiros ou a chats.
