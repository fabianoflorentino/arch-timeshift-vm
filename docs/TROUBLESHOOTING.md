# Troubleshooting

Diagnóstico das falhas mais comuns, por área.

## Snapshot

### "Snapshot 'X' was not found under ..."

`snapshot_source_name` não corresponde a nenhum diretório sob
`snapshot_source_root`. Liste os diretórios disponíveis:

```bash
ls -d /mnt/btrfs-top/timeshift-btrfs/snapshots/*/
```

Ou use `latest`:

```bash
E2E_SNAPSHOT=latest make e2e
```

### "is not a sendable BTRFS snapshot: @ and @home must be subvolumes and @ must have ro=true"

O `@` do snapshot não é um subvolume read-only. Um mount `ro` não é suficiente
para `btrfs send`. Verifique:

```bash
btrfs property get -t subvol /mnt/btrfs-top/timeshift-btrfs/snapshots/2026-09-20_14-00-00/@
# esperado: ro=true
```

Se `ro=false`, selecione outro snapshot ou crie um novo com o Timeshift
(`O` snapshot). Para um fixture de teste, é possível relaxar a validação com
`snapshot_source_validate_btrfs=false`.

### "Snapshot ... is not a bootable candidate"

Falta um dos artefatos: `@/usr/lib/modules/*/vmlinuz`, `@/usr/bin/grub-install`
ou `@/usr/bin/mkinitcpio`. Confira:

```bash
ls /mnt/btrfs-top/timeshift-btrfs/snapshots/2026-09-20_14-00-00/@/usr/lib/modules/*/vmlinuz
ls /mnt/btrfs-top/timeshift-btrfs/snapshots/2026-09-20_14-00-00/@/usr/bin/{grub-install,mkinitcpio}
```

Snapshot do tipo BTRFS com kernel e GRUB instalados são pré-requisitos do Tier 3.

## Disco e espaço

### "E2E VM disk is too small for the staged snapshot"

Os subvolumes staged excedem `vm_disk_size`. Aumente a capacidade virtual:

```bash
E2E_VM_DISK_SIZE=120G make e2e
```

### "Assert there is enough free space for the VM disk"

O diretório de imagens não tem espaço para o qcow2. Libere espaço ou aponte
`E2E_IMAGES_DIR` para outro filesystem.

## Host (preflight)

### KVM indisponível

Mensagem: *"KVM device /dev/kvm is missing or inaccessible"*. Habilite a
virtualização aninhada e garanta acesso:

```bash
sudo modprobe kvm_intel nested=1   # Intel; kvm_amd para AMD
ls -l /dev/kvm
```

### OVMF não encontrado

Instale `edk2-ovmf` (Arch):

```bash
sudo pacman -S --needed edk2-ovmf
```

### Rede libvirt ausente ou inativa

Mensagem: *"Libvirt network <name> is unavailable or inactive"*. Consulte o
estado na URI do sistema:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-info default
```

Se a rede não existir em `/etc/libvirt/qemu/networks/<name>.xml`, recrie-a.
Para que o playbook prepare a rede automaticamente:

```bash
sudo "$(pwd)/.venv/bin/ansible-playbook" playbooks/prepare-e2e.yml \
  -e snapshot_source_root=/mnt/btrfs-top/timeshift-btrfs/snapshots \
  -e e2e_preflight_prepare_network=true
```

### "Connection refused" ao falar com o libvirt

O E2E usa `qemu:///system` explicitamente. Se o daemon do sistema não estiver
rodando:

```bash
sudo systemctl start libvirtd
sudo virsh -c qemu:///system net-list
```

### Comandos ausentes

`make e2e` (via `e2e_preflight`) falha listando os comandos em falta. Instale
no Arch:

```bash
sudo pacman -S --needed qemu-img qemu-nbd libvirt btrfs-progs \
  dosfstools gptfdisk grub arch-install-scripts edk2-ovmf
```

## Boot da VM

### A VM não chega a `running`

O `verify` aguarda `virsh domstate` chegar a `running`, desliga a VM de forma
controlada e valida o marcador persistente do guest. Consulte o estado e o
console, se necessário:

```bash
virsh -c qemu:///system domstate arch-timeshift-e2e
virsh -c qemu:///system console arch-timeshift-e2e
```

Causas comuns: firmware OVMF incorreto, GRUB sem o `EFI/Linux` ou
`EFI/BOOT/BOOTX64.EFI`, fstab apontando para UUIDs que não existem no disco
novo. Os artefatos exigidos são verificados pelo role `boot`.

### "Neither a traditional initramfs nor a unified kernel image was generated"

O `mkinitcpio -P` não produziu `initramfs-linux.img` nem `EFI/Linux/arch-linux.efi`
na ESP. Repita o boot com `E2E_WORK_DIR` preservado e inspecione os arquivos
em `/var/tmp/arch-timeshift-vm-e2e/work`.

### "The guest agent did not answer guest-ping"

A verificação é cobrada apenas quando o snapshot de referência oferece o
agente (binário `qemu-ga` + unit `qemu-guest-agent.service` no clone). Se o
snapshot não tiver o agente, o `verify` pula a asserção e usa somente o
marcador persistente. Para diagnosticar quando a mensagem aparece:

```bash
# confirme que o canal virtio-serial existe no domínio
virsh -c qemu:///system dumpxml arch-timeshift-e2e | rg -A2 guest_agent
# interaja com o agente manualmente
virsh -c qemu:///system qemu-agent-command arch-timeshift-e2e \
  --timeout 10 '{"execute":"guest-info"}'
```

Causas comuns: canal `org.qemu.guest_agent.0` ausente do XML, guest ainda
inicializando (a espera padrão do `verify` é de ~150 s) ou o `qemu-ga` presente
mas com o unit de serviço ausente/corrompido no snapshot.

## Limpeza de execução interrompida

Se um `make e2e` for interrompido e deixar mounts/NBD/domínio pendurados:

```bash
make clean-e2e
```

Veja também [`docs/USAGE.md`](USAGE.md) e [`docs/SAFETY.md`](SAFETY.md).