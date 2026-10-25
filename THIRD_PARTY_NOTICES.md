# Avisos de terceiros

O Neorar inclui ou usa os componentes abaixo. Nenhum código do RAR Extractor Max foi usado.

## UnRAR (RARLAB)
Código-fonte oficial do UnRAR 7.30 (`Sources/CUnrar/unrar`), compilado dentro do app para extrair arquivos RAR.

UnRAR source code may be used in any software to handle RAR archives without limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible archiver and to re-create RAR compression algorithm, which is proprietary. Distribution of modified UnRAR source code in separate form or as a part of other software is permitted, provided that full text of this paragraph, starting from "UnRAR source code" words, is included in license, or in documentation if license is not available, and in source code comments of resulting package.

Licença completa: `Sources/CUnrar/unrar/license.txt`.

## 7-Zip (Igor Pavlov)
Binário oficial `7zz` 26.04 para macOS, distribuído sem modificações dentro do app (`Contents/MacOS/7zz`) e executado como processo separado. Licença GNU LGPL, com cláusulas BSD e a restrição do unRAR para o código de RAR. Texto completo: `Vendor/7-Zip-License.txt`. Código-fonte: https://github.com/ip7z/7zip

## libarchive
Usada a partir da biblioteca do sistema (`/usr/lib/libarchive.2.dylib`). Licença BSD.

## Sparkle
Framework de atualizações dentro do app (Verificar Atualizações…), embutido em `Contents/Frameworks/Sparkle.framework`. Licença MIT, Copyright (c) 2006-2013 Andy Matuschak e colaboradores. https://github.com/sparkle-project/Sparkle

## rar (RARLAB), opcional
Não é distribuído com o Neorar. Quando o usuário pede, o app baixa o `rar` oficial de rarlab.com para `~/Library/Application Support/Neorar/RAR`. É shareware sob a licença da RARLAB: gratuito por 40 dias, depois exige licença paga.

## unar / lsar (The Unarchiver), opcional
Não é distribuído. Se estiver instalado (por exemplo com `brew install unar`), é usado como alternativa para formatos legados. Licença LGPL 2.1.
