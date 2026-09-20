# Changelog

Todas as mudanças notáveis por fase.

O formato segue as fases do [`docs/PLAN.md`](docs/PLAN.md).

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
- Cobertura Tier 1 para os contratos de `snapshot_source` e `e2e_preflight`.
- Documentação final: `docs/{USAGE,SAFETY,TROUBLESHOOTING,IMPLEMENTATION}.md`,
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