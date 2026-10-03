# Changelog

Todas as mudanças notáveis por versão.

As versões seguem as fases de desenvolvimento do projeto (Fase 0-6) e suas
melhorias (ex.: Fase 6.1, Fase 6.2).

## Não publicado

### Adicionado

- Auto-mount do topo BTRFS (subvolid=5): quando o host usa `subvol=/@` e não tem
  o topo montado — caso em que os snapshots do Timeshift, guardados como
  irmãos de `@`/`@home`, ficam invisíveis — o role `snapshot` monta o topo
  read-only em `/run/arch-timeshift-vm/btrfs-top`, resolve
  `<topo>/timeshift-btrfs/snapshots` e libera o mount no fim da execução
  (bloco `always` de `preflight.yml`/`restore.yml` e role `e2e_cleanup`). O
  `/etc/fstab` do host continua intocado. Desligável com
  `timeshift_autodetect_mount_top=false`; ponto e opções configuráveis via
  `snapshot_top_mount_point`/`snapshot_top_mount_opts`.
- `ro=true` no `@`/`@home` do snapshot deixou de ser pré-requisito manual: o
  `btrfs send` recusa subvolume read-write e um mount read-only não basta
  (btrfs-send(8)), enquanto o Timeshift cria snapshots read-write. Com
  `-e snapshot_protect_source_read_only=true` a execução monta cada subvolume num
  scratch em `/run`, aplica `ro=true` e desmonta — sem remontar o topo
  compartilhado, que expõe o `@`/`@home` vivos do host. Continua opt-in por
  escrever no BTRFS do usuário; sem a flag o preflight falha mostrando os
  comandos exatos. O `restore` já devolve `ro=false` no que recebe.
- O flag `snapshot_top_mount_temporary` passa a ser publicado antes de o mount
  ser tentado: um mount que falha pela metade não pode escapar do `always` do
  play e deixar o topo montado.
- Falha de `mount` do topo temporário agora sai como `assert` com `rc` e `stderr`
  do `mount`, em vez do erro cru do módulo.
- Auditoria de boot state no `preflight`: compara o `@`/`@home` do snapshot com
  o subvolume que o host bootou (`/sys/fs/btrfs/rootid`), com o subvolume default
  do filesystem (`btrfs subvolume get-default`), com a linha de comando do kernel
  (`/proc/cmdline`) e com o `FSROOT` do host. Um snapshot do qual o host está
  rodando não representa um boot passado, e restaurá-lo devolveria o estado
  atual. Achados são warning por padrão e viram gate rígido com
  `snapshot_refuse_live_boot_state=true`; comparações por subvolume ID só são
  feitas entre snapshots do mesmo filesystem.
- Relatório de tamanho do snapshot no `preflight` via
  `btrfs filesystem du --summarize --raw`: `total`, `exclusive` e `shared` por
  subvolume — `exclusive` é o dado que define o custo no disco da VM.
- Diagnóstico do auto-detect: mensagem de falha passa a listar os mounts
  BTRFS observados, o estado `btrfs_mode`/`backup_device_uuid` do Timeshift e a
linha de `fstab` pronta; novo guard recusa snapshots de dispositivo errado quando
o `backup_device_uuid` do Timeshift não corresponde ao dispositivo derivado de
`/`.
- Cobertura de teste do caso real: sandbox Tier 2 com subvolid default ≠ 5
  exercita o auto-mount e o teardown; Tier 1 cobre o fallback desligado, o
  fallback com dispositivo não montável e o teardown no-op.

### Corrigido

- Os quatro playbooks em `playbooks/` rodavam sem nenhuma configuração do
  projeto. O Ansible só carrega `group_vars/` automaticamente quando ele fica
  ao lado do inventário ou ao lado do playbook; com `group_vars/` na raiz e os
  playbooks em `playbooks/`, `vm_name`, `vm_images_dir`, `vm_disk`,
  `vm_disk_size`, `work_dir` e `timeshift_root` ficavam indefinidos, e o
  `preflight` morria em `Validate vm_name`. Cada playbook agora declara
  `vars_files: ../group_vars/all.yml`, e `-e` continua tendo precedência.
  Reproduzível sem privilégio: o mesmo playbook resolvia `vm_name` na raiz e
  `UNDEFINED` dentro de `playbooks/`.

- Guard de proveniência do role `snapshot` cobrava `info.json` com `hostname`,
  chave que o Timeshift nunca escreveu: toda snapshot real era rejeitada como
  "de origem desconhecida", inclusive no `preflight`. O Timeshift 26.09.0
  registra `created`, `sys-uuid` e `sys-distro`, então o guard agora exige
  `created` + `sys-uuid` e o `fail_msg` lista as chaves presentes no arquivo.
  O hostname passou a ser lido de `<snapshot>/@/etc/hostname`, como
  informação, e `created` é exibido formatado em vez do epoch cru. Os fixtures de teste (`molecule
  default/integration`) foram alinhados ao schema real do Timeshift e um caso
  negativo novo prova que uma snapshot sem `sys-uuid` continua sendo recusada.

- Um guard que abortava o play deixava o host com o topo BTRFS do próprio snapshot
  montado em `/run/arch-timeshift-vm/btrfs-top`, e a liberação só existia em
  `post_tasks` — que o Ansible não executa quando a task falha. O
  `preflight.yml`/`restore.yml` passaram a usar `include_role` dentro de `block`
  com a desmontagem em `always`, de modo que snapshot inexistente, snapshot não
  sendable ou proveniência incompleta não deixam mount para trás.
- O guard de `@`/`@home` read-only engolia o `rc` da leitura de
  `btrfs property get -t subvol <path> ro`: uma leitura falha era reportada como
  "não é read-only" em vez de "não pôde ser lido", escondendo a causa. A
  asserção agora checa o `rc` e inclui `rc`/`stdout`/`stderr` na mensagem.

## Fase 6.2 - Endurecimento de produção (2026-09-23)

Endurece a ferramenta para uso standalone e produção: CLI, segurança por
default, crash recovery, proveniência e CI.

### Adicionado

- CLI `scripts/arch-timeshift-vm`: subcomandos `install`, `init`, `restore`,
  `plan`, `preflight`, `cleanup`, `e2e`, `version`. Resolve venv/collections/
  PATH/sudo, aplica `flock` contra concorrência, grava log de auditoria em
  `.logs/` e exige `-e confirm_restore=true` explícito para comandos que
  mutam. Config com precedência `/etc/arch-timeshift-vm/config.yml` →
  `~/.config/arch-timeshift-vm/config.yml` → `group_vars/all.yml`.
- Playbooks `preflight.yml` (validação read-only da fase 1) e `cleanup.yml`
  (remove VM restaurada, disco e estado órfão sem tocar parentes de
  `work_dir`).
- Rede da VM **isolada por padrão** (`vm_network_mode: isolated`): sem NAT,
  sem saída externa; `default` e `none` explícitos. Rede isolada definida e
  autostartada pelo role `libvirt` quando ausente.
- Crash recovery: o preflight recusa rodar sobre mounts sob `work_dir`, NBD
  servindo o disco ou `qcow2.new` órfão (recuperável com `cleanup` ou
  `-e force_cleanup=true`).
- Proveniência: `info.json` deve declarar `created`/`hostname`; manifest
  sha256 dos payloads de boot semeados em `work_dir/manifest-boot.sha256`.
- Manifest sha256 da fonte E2E (`e2e_snapshot_manifest`) verificado pelo
  `snapshot_stage`.
- sudoers escopado ao wrapper (`sudoers/arch-timeshift-vm`), instalável via
  `arch-timeshift-vm install`; PKGBUILD + hook de instalação.
- CI no repositório (`.github/workflows/`): lint + syntax + Tier 1 +
  `pip-audit` + `trivy`; Tier 3 discreto em runner próprio; release draft em
  tags `v*`.
- Collecções pinadas exatas (`ansible.posix==2.2.2`) e runner em container
  experimental (`container/Containerfile`, S13).
- `docs/ROADMAP.md` documenta os itens implementados e pendentes.

### Alterado

- Group vars e documentação (README, USAGE, SAFETY) refletem o novo default
  de rede isolada, o CLI e os gatilhos de segurança.
- Fixtures de teste (`molecule/*/converge.yml`) incluem proveniência em
  `info.json` e preservam NAT explícito no Tier 2/3.

## Fase 6.1 - Evidência de saúde do guest via QEMU guest agent (2026-09-21)

Melhoria da Fase 6: adiciona evidência de saúde do guest **durante a execução**,
além do marcador persistente validado após o desligamento controlado.

### Adicionado

- `roles/boot/tasks/guest_agent.yml`: detecta o QEMU guest agent no clone
  (`/usr/bin/qemu-ga` + unit `qemu-guest-agent.service`), publica
  `boot_guest_agent_available` e habilita o serviço no clone descartável com
  `systemctl enable --root` (resolve `[Install]`/socket activation sem exigir
  systemd rodando no guest).
- `molecule/e2e/verify.yml`: exigência de `guest-ping` pelo canal virtio-serial
  `org.qemu.guest_agent.0` quando o snapshot oferece o agente; retry ~150 s.
- `molecule/e2e/converge.yml`: registra `e2e_guest_agent_available` no
  contrato `e2e-vars.yml` consumido pelo verifier.
- Cobertura Tier 1 para a detecção/habilitação do guest agent (positivo com
  clone sintético e negativo sem agente).
- Documentação atualizada: `PLAN`, `IMPLEMENTATION`, `USAGE`, `ARCHITECTURE` e
  `TROUBLESHOOTING`.

### Comportamento

- Snapshot **com** guest agent: o E2E passa a exigir a resposta do agente além
  do marcador.
- Snapshot **sem** guest agent (como `2026-09-20_14-00-00`): a asserção é
  pulada e a evidência continua sendo o marcador — mantém verde sem modificação
  da fonte.

## Fase 6 - End-to-end e documentação final (2026-09-20)

Validação real do Tier 3: o snapshot real `2026-09-20_14-00-00` foi restaurado
em disco descartável e o domínio UEFI iniciado e verificado com KVM aninhado.

### Adicionado

- Cenário Molecule `e2e` (Tier 3 opt-in) com staging BTRFS read-only,
  boot real e cleanup sempre.
- Roles opt-in para o E2E:
  - `snapshot_source`: resolve, valida e, com duas confirmações, cria snapshot.
  - `snapshot_stage`: cópia BTRFS read-only sendable da fonte real.
  - `e2e_preflight`: valida KVM, OVMF, ferramentas, rede `qemu:///system`,
    espaço e permissões.
  - `e2e_cleanup`: remove domínio, NVRAM, XML, imagem, mounts, NBD e staging.
- `playbooks/prepare-e2e.yml` e alvos `make e2e`, `make prepare-e2e`,
  `make clean-e2e`.
- Fatos compartilhados `e2e_snapshot_dir`, `e2e_snapshot_name`,
  `e2e_snapshot_capabilities`, `e2e_snapshot_stage_dir`,
  `e2e_host_capabilities`.
- `libvirt_uri` explicitamente `qemu:///system` em todas as chamadas `virsh`.
- Suporte a unified kernel image (`EFI/Linux/<host>.efi`) no role `boot`, com
  verificação flexível de payload (initramfs ou UKI).
- Evidência de saúde do guest no Tier 3: serviço systemd temporário no clone,
  marcador persistente e inspeção read-only do subvolume restaurado após o
  desligamento controlado da VM.
- Cobertura Tier 1 para os contratos de `snapshot_source` e `e2e_preflight`.
- Documentação final: `docs/{USAGE,SAFETY,TROUBLESHOOTING,ARCHITECTURE}.md`,
  `CHANGELOG.md`, `CONTRIBUTING.md` e `LICENSE` (MIT).

## Fase 5 - libvirt + cleanup

- `roles/libvirt` com XML condicional (ISO/graphics/rendernode opcionais),
  `virt-xml-validate`, garantia da rede `default` e teardown idempotente.
- Changelog anterior correspondente ao commit `f4b8b3d`.

## Fase 4 - Boot

- Kernel semeado de `/usr/lib/modules/<ver>/vmlinuz` para a ESP vfat.
- `grub-install --removable` + `grub-mkconfig`; verificação de artefatos.
- Commit correspondente: `877231b`/`f4b8b3d`.

## Fase 3 - Restore confiável

- `btrfs send|receive` com `pipefail` e verificação pós-receive.
- fstab da VM com UUIDs novos + backup do original.
- Identidade do clone: `machine-id`, hostname e SSH host keys.
- Commit correspondente: `877231b`.

## Fase 2 - Disco atômico e sem resíduo

- qcow2 `.new` + troca atômica; NBD com retry; GPT alinhado; mounts efêmeros.
- Commit correspondente: `877231b`.

## Fase 1 - Preflight

- Detecção `timeshift_root: auto` via `findmnt`; validação do snapshot e de
  `vm_disk`/espaço; checagem de comandos do host.
- Commits correspondentes: `81a4d59`, `5f4c323`.

## Fase 0 - Fundação

- Harness do projeto, lint, Molecule Tier 1/2 e documentação inicial.
- Commit correspondente: `d4533f8`.