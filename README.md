# arch-timeshift-vm

Restaura um snapshot do Timeshift/BTRFS do host em uma VM libvirt/KVM
bootável e descartável, inteiramente no host - sem VirtioFS e sem ISO de
instalação.

> Status: reestruturação production-ready em andamento. Veja
> [`docs/PLAN.md`](docs/PLAN.md) para o plano por fases e o andamento.

## Como funciona

```
snapshot Timeshift -> qcow2 -> qemu-nbd -> GPT (EFI+BTRFS) -> btrfs receive
                   -> fstab da VM -> GRUB UEFI -> OVMF/NVRAM -> libvirt -> VM
```

## Requisitos

No host Arch Linux:

- `ansible-core` (via `.venv`, veja abaixo)
- Ferramentas de sistema: `qemu-img`, `qemu-nbd`, `libvirt`/`virsh`,
  `btrfs-progs`, `dosfstools` (`mkfs.fat`), `gptfdisk` (`sgdisk`),
  `grub`, `arch-install-scripts` (`arch-chroot`), `edk2-ovmf`.

```bash
sudo pacman -S --needed qemu-img qemu-nbd libvirt btrfs-progs \
  dosfstools gptfdisk grub arch-install-scripts edk2-ovmf
```

Não instale o Ansible globalmente. Use o virtualenv do projeto.

## Instalação (desenvolvimento)

```bash
make venv    # cria .venv e instala as dependências pinadas
make deps    # instala as collections do requirements.yml
make lint    # yamllint + ansible-lint
make syntax  # syntax-check dos playbooks
make test    # Molecule Tier 1 (Docker, sem privilégio)
make test-integration   # Molecule Tier 2 (BTRFS sintético; pede sudo)
```

## Uso

Revise `group_vars/all.yml`. O playbook é destrutivo para o disco da VM
nomeada e recusa executar até ser confirmado explicitamente:

```bash
sudo ansible-playbook playbooks/restore.yml -e confirm_restore=true
```

Snapshot específico:

```bash
sudo ansible-playbook playbooks/restore.yml \
  -e confirm_restore=true -e snapshot=2026-09-16_13-00-00
```

Outra VM:

```bash
sudo ansible-playbook playbooks/restore.yml \
  -e confirm_restore=true -e vm_name=archlinux-timeshift-test
```

## Testes

- `make test` - Molecule Tier 1: lógica, templates e contratos de variáveis
  em container Docker.
- `make test-integration` - Molecule Tier 2: detecção BTRFS e validação de
  snapshot em sandbox com BTRFS sintético (loopback); **requer root** (o
  alvo chama `sudo -E`).
- `make e2e` - Tier 3 (na Fase 6): boot real da VM com KVM aninhado.

Nenhum teste toca snapshots reais nem imagens reais. Veja
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Segurança

- `confirm_restore: false` por padrão.
- `timeshift_root: auto` detecta o subvolume topo do BTRFS e o diretório real
  de snapshots; dispensa caminhos fixos.
- `vm_disk` é canonicalizado e validado contra `vm_images_dir` antes de
  qualquer remoção, com checagem de espaço livre.
- O `/etc/fstab` do host nunca é modificado (mounts efêmeros).
- Cleanup automático em caso de falha.

## Estrutura

```
ansible.cfg
requirements.yml / requirements-dev.txt
Makefile
docs/{PLAN,ARCHITECTURE}.md
group_vars/all.yml
inventory/localhost.yml
playbooks/restore.yml
roles/{snapshot,disk,restore,boot,libvirt}/
molecule/{default,integration}/
scripts/
```

## Licença

MIT (a definir na Fase 6).
