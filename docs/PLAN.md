# Plano de correção e endurecimento

Transformar o scratch inicial em um projeto Ansible **production ready**:
seguro por padrão, idempotente, com resíduo zero, lint limpo, testes
automatizados e documentação.

## Objetivo

Dado um snapshot do Timeshift/BTRFS do host, materializar uma VM libvirt
bootável e descartável, inteiramente no host, sem VirtioFS e sem ISO de
instalação.

## Modelo de segurança

- `confirm_restore: false` por padrão; o playbook recusa executar sem
  confirmação explícita (`-e confirm_restore=true`).
- Todo caminho destrutivo (`vm_disk`) é canonicalizado e validado contra um
  diretório-base permitido (`vm_images_dir`) **antes** de qualquer remoção.
- Nada é apagado antes de o novo artefato estar pronto (troca atômica do
  qcow2).
- O modo `--check` / leitura pura (`confirm_restore=false`) nunca muta o host.
- Testes nunca tocam snapshots reais nem imagens reais: usam sandbox/fixtures.

## Definição de idempotência

Um pipeline de restauração destrutivo não pode ser "0 changed na 2ª execução".
A definição adotada e testável é:

1. Re-executar converge para o **mesmo estado final**.
2. Re-executar **não deixa resíduo** (sem mounts, sem NBD, sem processos, sem
   domínios libvirt, sem workdir pendurado).
3. `confirm_restore=false` é 100% no-op.

## Estratégia de testes (Molecule, híbrida)

| Tier | Driver | Privilégio | Cobre |
| --- | --- | --- | --- |
| 1 - `default` | docker | não | lógica, templates, contratos de variáveis, validações |
| 2 - `integration` | delegated (`default`) | root | qemu-nbd, btrfs, mkfs, mounts, virsh, cleanup |
| 3 - `e2e` | delegated + KVM aninhado | root | boot real da VM descartável |

- **Tier 1** (`make test`): roda em container Arch com Python. Toda a lógica
  que não exige dispositivo/root deve ser testável aqui.
- **Tier 2** (`make test-integration`, requer root): sandbox com qcow2
  temporário, snapshots sintéticos (loopback BTRFS), NBD real, `virsh define`
  sem iniciar. Verifica também que `/etc/fstab` do host permanece intacto.
- **Tier 3** (`make e2e`): sobe a VM produzida (KVM aninhado habilitado),
  valida boot e destrói. Opt-in, fora do default.

## Definition of Done (por fase)

Uma fase só avança quando:

- `make lint` está limpo para os arquivos da fase (o role da fase sai de
  `exclude_paths` e fica com zero findings);
- o cenário Molecule da fase passa positivos, negativos e resíduo/cleanup;
- a documentação afetada foi atualizada.

## Fases

### Fase 0 - Fundação, governança e harness

Status: concluído (commit `d4533f8`).

- `git`, `.gitignore`, `.editorconfig`, `.yamllint`, `.ansible-lint`,
  `.pre-commit-config.yaml`.
- `requirements.yml` pinado; `requirements-dev.txt`; `ansible.cfg` endurecido.
- `Makefile` + `scripts/` (env de teste, syntax-check).
- Cenários Molecule Tier 1 e Tier 2 base.
- `docs/PLAN.md`, `docs/ARCHITECTURE.md`, `README.md`.

Gate: `make lint` limpo no escopo e `molecule test -s default` verde. ✅

### Fase 1 - Preflight (role `snapshot`)

Status: implementado. Tier 1 verde (positivos, negativos e idempotência);
Tier 2 aguardando execução com root (`make test-integration`).

- Detecção automática do topo do BTRFS e do diretório real de snapshots via
  `findmnt`, sem hardcode (`timeshift_root: auto`).
- Validação de `confirm_restore`, `vm_name`, `vm_disk` canonicalizado sob
  `vm_images_dir`, espaço livre com margem percentual.
- Checagem de comandos do host com uma única mensagem listando os ausentes.
- Validação do snapshot (`@`/`@home` subvolumes, `@` read-only via
  `btrfs property`, `info.json`) e resolução de `latest`.
- Role lint-clean (`roles/snapshot` fora de `exclude_paths`).

Gate: positivos/negativos/idempotência no Tier 1 ✅ (+ Tier 2 de detecção
com BTRFS sintético em loopback, pendente de execução).

### Fase 2 - Disco atômico e sem resíduo (role `disk`)

Status: pendente.

- qcow2 em `vm_disk.new` + troca atômica.
- NBD com retry e espera por `size > 0`; teardown idempotente.
- Corrigir alinhamento GPT (`--new=1:0:+...`).
- Mounts efêmeros (fim da poluição do `/etc/fstab` do host).
- `block/rescue/always` + role `cleanup`.

Gate: Tier 2 com NBD/BTRFS reais, fstab do host inalterado, cleanup em falha.

### Fase 3 - Restore confiável (role `restore`)

Status: pendente.

- `btrfs send|receive` com `pipefail` e verificação pós-receive.
- fstab da VM com UUIDs novos + backup do original.
- Identidade do clone: `machine-id`, hostname, host keys.

Gate: Tier 2 com snapshot sintético e marcador.

### Fase 4 - Boot (role `boot`)

Status: pendente.

- Bloqueador: `/boot` é ESP separado e **não está no snapshot** - semear o
  kernel de `/usr/lib/modules/*/vmlinuz` + `mkinitcpio -P`.
- `grub-install --removable` + `efibootmgr`; verificação de artefatos.
- Simplificar binds (o `arch-chroot` já monta os API filesystems).

Gate: 4a (lógica, mock) + 4b (GRUB real no sandbox).

### Fase 5 - libvirt + cleanup (role `libvirt`)

Status: pendente.

- XML condicional (ISO/graphics/rendernode opcionais); sem pin de `machine` e
  sem PCI manual; `virt-xml-validate`.
- Garantir rede `default` ativa; define/undefine limpos.
- Role `cleanup` idempotente e testada com falha induzida.

Gate: XML válido, define/undefine sem resíduo.

### Fase 6 - End-to-end e documentação final

Status: pendente.

- Run completo até VM bootável (KVM aninhado) + verificação após boot.
- `README`, `ARCHITECTURE`, `USAGE`, `SAFETY`, `TROUBLESHOOTING`, `CHANGELOG`,
  `CONTRIBUTING`, `LICENSE`.

Gate: `make e2e` verde.

## Bloqueadores descobertos no host de referência

1. ~~`timeshift_root` aponta para `/timeshift-btrfs/snapshots`, que não
   existe.~~ Resolvido na Fase 1: `timeshift_root: auto` detecta o topo do
   BTRFS (`/mnt/btrfs-top`) via `findmnt`.
2. Kernel/initramfs ficam no ESP vfat separado, fora do snapshot BTRFS.
   O `@/boot` está vazio. (Fase 4)
3. `sgdisk`, `mkfs.fat` e `arch-chroot` não estão instalados no host. A Fase 1
   já reporta os ausentes de forma clara; o Tier 2 usa um subconjunto válido
   até a instalação (necessária nas Fases 2 e 4).
