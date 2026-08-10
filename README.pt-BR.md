# sora

**Digite um comando que só existe dentro de um container distrobox, e ele
simplesmente roda — com os binários do host sempre vencendo.**

[Read in English](README.md)

Em distros imutáveis/atômicas (Fedora Silverblue, Bluefin, Bazzite, Aurora,
openSUSE MicroOS, Vanilla OS) suas ferramentas vivem em containers distrobox —
e você paga por isso a cada invocação: `distrobox enter archbox -- neofetch`,
de novo e de novo. O ecossistema resolveu a direção **container → host**
(`distrobox-host-exec`, `host-spawn`); o sora resolve a direção oposta,
**host → container**:

```console
$ sora box create archbox --image arch
$ sora hook install
$ neofetch            # não existe no host — roda da archbox, transparente
$ sora anxious --sudo pacman --box archbox
$ pacman -S steam     # funciona de scripts, .desktop, cron, qualquer lugar
```

Sem daemon, sem poluir o PATH, e um typo nunca acorda um container.

## Instalação

```sh
# COPR (família Fedora — canal principal)
sudo dnf copr enable <owner>/sora && sudo dnf install sora

# AUR (Arch Linux)
paru -S sora

# Tarball da última release
curl -fsSL https://github.com/REPLACE_ME/sora/releases/latest/download/sora-0.1.0.tar.gz | tar xz
make -C sora-0.1.0 install PREFIX=~/.local

# curl | sh (fallback; instala em ~/.local)
curl -fsSL https://REPLACE_ME/install.sh | sh

# De um checkout
make install PREFIX=~/.local
```

Requisitos: `distrobox` e `podman` (ou docker). Shell puro — nada para
compilar, nenhum runtime. Depois, uma vez:

```console
$ sora hook install        # bash, zsh e fish
```

## Duas estratégias complementares

O sora implementa **os dois** modelos de propósito, porque nenhum cobre o
território do outro:

1. **Resolução tardia** (o diferencial). Nada é exportado. A busca no PATH
   falha, e o gancho de "comando não encontrado" do shell resolve a falha
   consultando um índice `comando → box` em cache. Consequência importante:
   **a precedência do host é estrutural** — o gancho só roda *depois* que o
   PATH do host já falhou, então nada jamais sombreia um binário do host.

2. **Exportação ansiosa sob demanda** (`sora anxious`). Um wrapper real é
   colocado no PATH para um comando específico, via `distrobox-export` por
   baixo. Cobre todos os contextos que o gancho tardio não alcança.

| | Resolução tardia | Exportação ansiosa |
|---|---|---|
| Contextos que funcionam | só shells interativos com o gancho instalado | qualquer um: scripts, `.desktop`, cron, outro shell |
| Tab completion | não | sim (é arquivo no PATH) |
| Cobertura | todos os binários da box, automático | um comando por vez, explícito |
| Poluição do PATH | nenhuma | um arquivo por comando exportado |
| Precedência do host | estrutural (gancho só dispara após o PATH falhar) | depende da ordem do PATH |

**Por que não simplesmente exportar tudo?** Uma box tem milhares de binários.
Exportar todos inunda o PATH e o tab completion, inverte a precedência em
qualquer colisão de nome, e deixa wrappers órfãos a cada pacote removido.
**Por que o índice em cache?** Os handlers ingênuos que circulam mandam
*toda* palavra desconhecida para o container — um typo como `gti status`
acorda um container parado só para falhar de forma confusa. No sora, o erro
custa microssegundos, nunca toca no container, e a existência do container é
verificada antes de despachar.

## Uso

### Boxes

```console
$ sora images                                  # catálogo de aliases (qualquer imagem OCI serve)
$ sora box create archbox --image arch
$ sora box list
$ sora box enter archbox
$ sora box rm archbox [--delete-home]
```

O `sora box create` aplica dois defaults opinativos, ambos desligáveis:

- **Home própria** por box (`~/.local/share/sora/homes/<box>`, desligue com
  `--no-own-home`). Isso é *organização*, não isolamento: evita que pacotes
  instalados na box espalhem dotfiles na home do host. A home do host continua
  bind-montada no mesmo caminho absoluto de qualquer jeito — `--home` troca o
  `$HOME`, não esconde nada. Para esconder subcaminhos sensíveis de verdade,
  use `--hide` (tmpfs por cima): `--hide .ssh --hide .gnupg`.
- **Symlinks das pastas XDG** da home da box para as pastas reais do host
  (desligue com `--no-xdg-links`), resolvidas com `xdg-user-dir` porque as
  pastas são localizadas ("Documentos", "Imagens"…).

Os metadados ficam em `~/.config/sora/boxes/<box>.toml`: imagem de origem,
família do gerenciador de pacotes (detectada pela **presença do binário**
dentro da box, nunca adivinhada pelo nome da imagem; sobrescrevível com
`--pkg-manager`), home da box, prioridade no índice, data da última indexação.

### O índice

```console
$ sora reindex [box...]        # reconstrói (create/rm/pin já fazem isso)
$ sora conflicts               # comandos em >1 box, e quem vence
$ sora pin python archbox      # fixação manual, vence a prioridade
$ sora which python            # como um comando resolveria (host vs box)
$ sora box set-priority archbox 50
```

Ordem de resolução para um comando presente em várias boxes: **pin → maior
prioridade → nome alfabético da box** (determinístico). O índice se atualiza
sozinho: o `sora box create` instala um hook *dentro* da box usando o
mecanismo nativo do gerenciador (plugin de actions do dnf5, `DPkg::Post-Invoke`
do apt, hook ALPM do pacman), então toda transação reescreve o índice do
host. Outros gerenciadores (zypper, apk, …) exigem `sora reindex <box>`
manual — o sora avisa na criação.

### `sora anxious` — exportação ansiosa

```console
$ sora anxious --sudo pacman --box archbox
$ sora anxious htop --box fedora
$ sora anxious --list
$ sora anxious --remove pacman
```

Os wrappers vão para `~/.local/bin`, gerados pelo `distrobox-export` por
baixo.

**Semântica do `--sudo` — leia, todo mundo erra isso.** O wrapper roda o
comando com `sudo` **dentro** do container (o distrobox já configurou
`NOPASSWD` lá). É isso que permite digitar `pacman -S steam` direto no
terminal do host, **sem** `sudo` na frente. Colocar `sudo` do host antes
quebraria tudo: miraria o storage *rootful* do podman em vez dos seus
containers rootless.

Gerenciadores de pacotes são o caso de uso principal do modo ansioso
justamente porque são invocados de scripts e de contextos onde a resolução
tardia não vale.

### Ganchos de shell

```console
$ sora hook install [bash zsh fish]
$ sora hook status
$ sora doctor                  # checagem geral do setup
```

**Encadeamento é inegociável.** O gancho de comando-não-encontrado costuma já
estar ocupado (`mise`, `pkgfile`, `command-not-found` do Debian, PackageKit
no Fedora). O sora nunca o sobrescreve — salva o handler anterior e delega a
ele sempre que não resolver sozinho. Carregue o gancho do sora **depois**
dessas ferramentas (o instalador anexa ao final do rc). Quando o sora não
resolve, a mensagem distingue "nenhuma box indexada" de "o comando não existe
em nenhuma box". Argumentos (espaços, aspas, strings vazias) chegam intactos;
o código de saída é propagado.

## Limitações, honestamente

- Resolução tardia exige shell interativo com o gancho instalado — é
  exatamente por isso que o `sora anxious` existe.
- O fish força o status *reportado* de um comando desconhecido para 127 mesmo
  quando o handler o executou com sucesso; o comando roda e imprime
  normalmente, só o `$status` mente. bash e zsh propagam corretamente.
- A fidelidade de argumentos através do `distrobox enter` é a da sua versão
  do distrobox; o sora passa `"$@"` intocado.
- No fish, o sora instala em `conf.d`, que carrega *antes* do `config.fish`;
  se outra ferramenta define o handler no `config.fish`, carregue o sora no
  final do `config.fish` para que ele possa encadear.

## Para contribuidores

Detalhe de implementação fica deliberadamente fora deste README (em inglês):

- [docs/architecture.md](docs/architecture.md) — fluxo de dados, formatos em
  disco, scripts gerados, e as seis armadilhas que o código encapsula
  (permissões keep-id/subuid, sudo resetando `$HOME`, quoting de heredoc…).
- [docs/decisions.md](docs/decisions.md) — por que bash, por que não um
  usuário de sistema dedicado, por que não um shim de PATH, por que não
  exportar tudo, prior art.
- [docs/releasing.md](docs/releasing.md) — releases por tag, `bin/release`.
- [CONTRIBUTING.md](CONTRIBUTING.md) — o que o CI impõe.

```console
$ make test           # suíte em sandbox, stubs de distrobox/podman
$ make lint           # shellcheck, estrito
$ make integration    # opt-in: cria uma box real descartável
```

## Licença

[MIT](LICENSE)
