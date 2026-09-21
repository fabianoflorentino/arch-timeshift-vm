# Changelog

Todas as mudanças notáveis por versão.

As versões seguem as fases de desenvolvimento do projeto (Fase 0-6) e suas
melhorias (ex.: Fase 6.1).

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