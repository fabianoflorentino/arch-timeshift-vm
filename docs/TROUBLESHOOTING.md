# Troubleshooting

Diagnóstico das falhas mais comuns, por área.

## Snapshot

### "Could not find a mounted BTRFS top-level (subvolid=5) subvolume for ..."

O layout `subvol=/@` monta `@` em `/`, e não o topo (subvolid=5). O Timeshift
guarda os snapshots no topo, como irmãos de `@`/`@home`, então eles ficam
invisíveis para o `/` enquanto o topo não estiver montado. A mensagem lista os
mounts BTRFS observados — normalmente só `/@` e `/@home`.

Confirme o estado real:

```bash
findmnt --raw --noheadings --output SOURCE,TARGET,FSROOT --types btrfs
# esperado para o auto-detect: uma linha com FSROOT "/"
```

Os snapshots existem mesmo sem o mount; o próprio Timeshift monta o device
temporariamente para criá-los:

```bash
grep -h "loading snapshots from" /var/log/timeshift/*_backup.log | tail -1
```

Soluções, da mais permanente para a mais alinhada ao uso pontual:

```bash
# 1. Montar o topo permanentemente (recomendado)
echo "UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) /mnt/btrfs-top btrfs subvolid=5,ro,x-systemd.automount,nofail 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload

# 2. Auto-mount temporário, montado e desmontado pelo próprio preflight
arch-timeshift-vm preflight -e confirm_restore=true

# 3. Sem mount algum: aponte direto para o diretório de snapshots
arch-timeshift-vm preflight -e confirm_restore=true \
  -e timeshift_root=/mnt/btrfs-top/timeshift-btrfs/snapshots
```

Para desligar o fallback e falhar cedo quando o topo não estiver montado:

```bash
arch-timeshift-vm preflight -e confirm_restore=true -e timeshift_autodetect_mount_top=false
```

### "Timeshift backs up device UUID X but auto-detection resolved Y ..."

O UUID em `backup_device_uuid` (`/etc/timeshift/timeshift.json`) não é o do
dispositivo derivado de `/` — o snapshot viria do filesystem errado. Aponte
`-e timeshift_device=/dev/<dispositivo-correto>` ou corrija a config do
Timeshift.

### "Timeshift snapshot root ... does not exist"

Com `timeshift_root: auto`, o topo já foi montado (temporário ou não), mas o
diretório `timeshift-btrfs/snapshots` não existe nele. Confirme se os
snapshots estão onde o papel diz:

```bash
findmnt --types btrfs --output SOURCE,TARGET,FSROOT
ls -la /mnt/btrfs-top/timeshift-btrfs/snapshots
```

Se os snapshots estiverem em outro BTRFS, aponte `timeshift_device` para a
fonte daquele filesystem; para um caminho não padrão, aponte `timeshift_root`
direto para o diretório `snapshots`. O mount manual acima serve só para
diagnóstico: substitua o placeholder pelo device real.

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

### "Assert the copy will be on the same BTRFS filesystem as the snapshot"

O `snapshot_stage_root` aponta para um filesystem diferente do que guarda os
snapshots. A cópia read-only é um `btrfs subvolume snapshot -r`, que só existe
dentro do mesmo filesystem BTRFS. Aponte para um diretório gravável no BTRFS dos
snapshots:

```bash
findmnt -no SOURCE,FSTYPE,TARGET --target /
findmnt -no SOURCE,FSTYPE,TARGET --target /var/tmp
```

Um disco ext4 separado (por exemplo `/data` ext4) não pode receber a cópia, por
mais espaço que tenha: `btrfs subvolume snapshot` não cruza filesystems.

### "Not enough free space on the staging filesystem"

O filesystem de `snapshot_stage_root` está abaixo de
`snapshot_stage_min_free_bytes` (padrão `1G`). A cópia compartilha todos os
extents com a origem, então a exigência é só uma margem para metadados: libere
espaço ou aponte `snapshot_stage_root` para outro diretório no mesmo BTRFS.

### "the host boot state overlaps snapshot ..."

O `@` ou o `@home` do snapshot é o subvolume de onde o host está rodando — o
snapshot não representa um boot passado, e restaurá-lo devolveria o estado atual.
A mensagem lista qual verificação casou (`rootid`, `get-default`, `subvol=` do
kernel, `FSROOT` do host). Para inspecionar:

```bash
cat /sys/fs/btrfs/rootid            # subvolume ID do @ do host
cat /proc/cmdline                    # subvol=/... bootado
findmnt --noheadings --output SOURCE,FSROOT /
btrfs subvolume get-default /mnt/btrfs-top
```

Escolha outro snapshot ou aceite explicitamente com
`-e snapshot_refuse_live_boot_state=false`.

### "not audited" no relatório de boot state

O snapshot está em outro filesystem que o `@` do host. IDs de subvolume só são
comparáveis dentro do mesmo BTRFS, então o `preflight` não emite achados em vez
de comparar números que colidiriam por acaso. Isso não é um erro.

### O host ficou com o topo BTRFS montado em `/run`

Não deveria mais acontecer: `preflight.yml`/`restore.yml` liberam o mount em
`always`. Se um run foi interrompido com `SIGKILL`, limpe com:

```bash
arch-timeshift-vm cleanup -e confirm_restore=true
```

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