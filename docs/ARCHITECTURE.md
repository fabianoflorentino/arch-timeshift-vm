# Arquitetura

## Pipeline

```
Timeshift / BTRFS snapshot
        |
        v
  preflight (snapshot)      resolve + valida snapshot e travas de seguranca
        |
        v
  disk                      qcow2 -> qemu-nbd -> GPT (EFI + BTRFS) -> mkfs/mounts
        |
        v
  restore                   btrfs receive @/@home -> fstab da VM -> identidade
        |
        v
  boot                      kernel/initramfs -> GRUB UEFI
        |
        v
  libvirt                   XML + NVRAM -> virsh define/start
        |
        v
  cleanup (always)          desmonta tudo, desconecta NBD, remove residuo
```

## Papel de cada role

| Role | Responsabilidade | Muta o host? |
| --- | --- | --- |
| `snapshot` | resolver e validar o snapshot; travas de segurança | não |
| `disk` | criar qcow2, expor via NBD, particionar, formatar, montar | sim |
| `restore` | `btrfs receive`, fstab da VM, identidade do clone | sim (no disco da VM) |
| `boot` | semear kernel/initramfs, instalar GRUB UEFI | sim (no disco da VM) |
| `libvirt` | gerar XML, NVRAM, definir e iniciar o domínio | sim (libvirt) |
| `cleanup` | desmontar, desconectar NBD, remover artefatos parciais | sim |

## Fluxo de variáveis

- `group_vars/all.yml` concentra a configuração e o default seguro.
- Variáveis específicas de cada execução são passadas com `-e` (ex.:
  `confirm_restore=true`, `snapshot=...`, `vm_name=...`).
- A namespaceação definitiva (`restorevm_*` para fatos compartilhados entre
  roles e prefixo do role para fatos locais) é aplicada fase a fase.

## Fatos do host de referência (detectados)

- Arch Linux, BTRFS com `@` (raiz) e `@home`, topo montado em `/mnt/btrfs-top`.
- Snapshots em `/mnt/btrfs-top/timeshift-btrfs/snapshots` (Timeshift 25.12).
- `/boot` é um ESP vfat **separado**, fora do snapshot BTRFS.
- Kernel em `/usr/lib/modules/<ver>/vmlinuz` (esse sim dentro do snapshot).
- QEMU 11.1, libvirt 12.7, rede `default` ativa, KVM aninhado habilitado.
- `sgdisk`, `mkfs.fat` e `arch-chroot` ausentes (instalar antes do Tier 2).

## Modelo de segurança

- Padrão `confirm_restore: false`.
- `vm_disk` canonicalizado e restrito a `vm_images_dir`.
- Troca atômica do qcow2 (novo arquivo pronto antes de remover o antigo).
- Mounts efêmeros: o `/etc/fstab` do host nunca é alterado.
- Todo caminho mutante passa por `block/rescue/always` + role `cleanup`.

## Isolamento de teste

- Tier 1: container Docker descartável (sem privilégio).
- Tier 2: sandbox local com qcow2 temporário e snapshots sintéticos
  (loopback BTRFS). Nenhum teste toca `/data/libvirt/images` ou os snapshots
  reais.
- Tier 3: VM descartável com KVM aninhado.
