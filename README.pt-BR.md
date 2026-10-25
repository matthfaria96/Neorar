# Neorar Mac

[English](README.md) · **Português**

Gerenciador de arquivos compactados para macOS 26+, em Swift e SwiftUI, no estilo do WinRAR: uma janela só, que navega pelas pastas (começa em Downloads), entra em arquivos compactados e age sobre a seleção. É um app independente (não faz parte do Sirena), escrito do zero; nada do RAR Extractor Max foi aproveitado.

## Funções

| Área | O que faz |
|---|---|
| **Navegação** | Pastas e arquivos compactados em lista ou ícones (miniaturas Quick Look), ordenação por coluna, filtro, local com menu (caminho, Downloads, Mesa, Documentos, recentes), voltar/subir, atualização automática quando algo muda no disco |
| **Extrair** | Aqui / Para… / para "Nome/", RAR 1.5–7 (RAR5, sólido, senha, nomes criptografados, volumes `.partN.rar`/`.rNN`), ZIP (AES, codificação de nomes), 7Z, TAR.*, ISO, DMG, CAB, MSI, ARJ, LZH… |
| **Dentro do arquivo** | Árvore ou ícones, busca, Espiar (Quick Look), abrir, extrair só a seleção |
| **Comprimir** | 7Z (padrão), ZIP (AES-256), TAR.GZ/XZ/BZ2; RAR só com o `rar` licenciado da RARLAB. "Avançados": senha, nomes ocultos, partes, sólido, recuperação, ignorar lixo do macOS, originais para o Lixo |
| **Editar arquivo existente** | Adicionar (botão, arrastar para a janela, dentro da pasta atual do arquivo) e excluir itens; 7Z/ZIP/TAR via 7-Zip, RAR com o `rar` licenciado |
| **Comentários** | Faixa de comentário ao abrir (RAR/ZIP), comentário na janela Info, criação em Comprimir › Avançados |
| **Testar / Reparar / Info** | Integridade com resultado em modal; reparo de RAR (`rar r`, registro de recuperação) e ZIP (`zip -FF`) em cópia "(reparado)"; propriedades |
| **Feedback** | Pergunta de conflito (Substituir / Manter ambos / Cancelar), painel de progresso, avisos com Mostrar/Desfazer, itens novos selecionados com marcador, Excluir com Desfazer |
| **Ajustes** | Geral (tema Sistema/Claro/Escuro, estilo dos ícones, idioma, ação “Comprimir” do Finder), Extração, Compressão, RAR e Sobre com as licenças completas |
| **Idiomas** | Português, inglês, espanhol, francês e alemão (`scripts/translations.py` → `make-localizations.py`) |
| **Integração** | Menu do Finder (extensão Finder Sync): Extrair Aqui, Extrair para “Nome/”, Extrair Para…, Comprimir; Abrir com, Serviços, copiar caminho (⌥⌘C) |

## Arquitetura

```
Sources/
  CUnrar/        UnRAR 7.30 oficial (RARLAB) + shim C: RAR em processo
  CLibArchive/   Declarações da libarchive do sistema: família tar em processo
  NeorarCore/    Motores, extração com área temporária, conflitos, teste, compressão
  Neorar/        App SwiftUI (janela única, barra de ações, folhas de Comprimir/Info/Senha)
Extensions/
  FinderSync/    Extensão do Finder; envia ações ao app por neorar://
```

A extensão é ativada em Ajustes › Geral › Menu do Finder (ou Ajustes do Sistema › Extensões).

- RAR → UnRAR em processo (~1,8 GB/s); tar.* → libarchive do macOS; demais formatos e criação de 7Z/ZIP → `7zz` oficial embutido.
- Senhas vão por stdin (exceto no fallback opcional `unar`, que só aceita senha por argumento).
- A extração acontece numa pasta oculta no destino; o resultado é movido com um `rename`, e cancelar não deixa lixo.

## Instalação

Requer macOS 26 ou mais recente.

Baixe o `Neorar-<versão>.dmg` em [Releases](https://github.com/matthfaria96/Neorar/releases) ou no [witchmymac.com](https://witchmymac.com), abra e arraste o **Neorar** para a pasta Aplicativos.

O app não é notarizado, então o macOS bloqueia a primeira abertura. Para liberar, cole no Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Neorar.app"
```

Isso só remove a marca de "baixado da internet" desse app. Sem usar o Terminal: abra o app, clique em OK no aviso e vá em Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim.

## Build

Requer Xcode 27 (os plugins de macro do SwiftUI não vêm nas Command Line Tools).

```sh
./build-app.sh            # build/Neorar.app (universal, assinatura ad hoc)
./build-app.sh --install  # e copia para /Applications
```

O ícone é gerado por `scripts/make-icon.swift` → `Resources/icon_1024.png`.

## Testes

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
NEORAR_RAR=/caminho/para/rar swift test                    # inclui criação de RAR
NEORAR_BENCH=/caminho/arquivo.rar swift test -c release --filter Benchmark
```

## Licenças

O NeoRAR é software livre, distribuído sob a [GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Matheus Faria.

Os componentes de terceiros que ele inclui ou usa (UnRAR, 7-Zip, libarchive) mantêm as próprias licenças; veja [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
