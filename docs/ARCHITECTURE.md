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
  teardown (always)         desmonta tudo, desconecta NBD, remove residuo
```

Tier 3 (`make e2e`) estende o pipeline com uma fonte preparada:

```
snapshot_source (opcional)        valida a fonte real; criação é opt-in
snapshot_stage                    cópia BTRFS read-only descartável
e2e_preflight                     valida KVM/OVMF/ferramentas/rede/espaço
[ snapshot -> disk -> restore -> boot -> libvirt ]  com libvirt_uri=qemu:///system
verify                            domstate + disco + guest agent + marcador persistente
e2e_cleanup (always)              restaura o host (domínio, NVRAM, mounts, NBD, staging)
```

## Papel de cada role

| Role | Responsabilidade | Muta o host? |
| --- | --- | --- |
| `snapshot` | detectar/resolver e validar o snapshot; travas de segurança; validar `vm_disk`/espaço | não |
| `disk` | criar qcow2, expor via NBD, particionar, formatar, montar | sim |
| `restore` | `btrfs receive`, fstab da VM, identidade do clone | sim (no disco da VM) |
| `boot` | semear kernel/initramfs, instalar GRUB UEFI | sim (no disco da VM) |
| `libvirt` | garantir rede, gerar XML, definir e iniciar o domínio | sim (libvirt) |
| `libvirt` (teardown) | destruir, undefine, remover NVRAM e XML | sim |
| `snapshot_source` | localizar/criar (opt-in) e validar a fonte Timeshift para o E2E | não (criação é opt-in confirmado) |
| `snapshot_stage` | cópia BTRFS read-only sendable da fonte | sim (staging em `/var/tmp`) |
| `e2e_preflight` | validar KVM, OVMF, ferramentas, rede `qemu:///system`, espaço | não |
| `e2e_cleanup` | remover domínio, NVRAM, XML, imagem, mounts, NBD e staging | sim (sandbox, nunca os snapshots reais) |

No Tier 3, o role `boot` instala no clone um serviço systemd temporário que
grava uma evidência em `/etc/arch-timeshift-vm/e2e-boot-ok`. Se o clone também
tiver o QEMU guest agent (`qemu-ga` + `qemu-guest-agent.service`), o role o
habilita via `systemctl enable --root` e publica `boot_guest_agent_available`.
O `verify` cobra, enquanto o domínio roda, uma resposta a `guest-ping` no canal
virtio-serial `org.qemu.guest_agent.0`. Depois de confirmar que a VM iniciou, o
`verify` tenta desligar o domínio de forma controlada e usa `destroy` somente
como fallback,
monta o subvolume `@` do qcow2 em modo somente leitura e valida o marcador.
O serviço é injetado somente no disco descartável da VM; o snapshot fonte
permanece inalterado.

## Fluxo de variáveis

- `group_vars/all.yml` concentra a configuração e o default seguro
  (`confirm_restore`, `vm_*`, `timeshift_root`, ...). O role `snapshot` é o
  consumidor auditável dessas chaves.
- Variáveis específicas de cada execução são passadas com `-e` (ex.:
  `confirm_restore=true`, `snapshot=...`, `vm_name=...`).
- O E2E é dirigido por variáveis de ambiente mapeadas no
  `molecule/e2e/converge.yml` (`E2E_SNAPSHOT`, `E2E_VM_NAME`,
  `E2E_IMAGES_DIR`, `E2E_WORK_DIR`, `E2E_STAGE_ROOT`, `E2E_VM_DISK_SIZE`,
  `E2E_EFI_SIZE_MIB`, `E2E_VM_MEMORY_MIB`, `E2E_VM_VCPUS`, `E2E_NETWORK`) —
  nunca por heurística. O snapshot usado é registrado em `e2e-vars.yml` no
  diretório de trabalho.
- Fatos compartilhados entre roles: `resolved_snapshot`, `snapshot_root`,
  `snapshot_home`, `snapshot_dir` (produzidos pelo `snapshot`), `vm_disk_real`
  e `vm_images_dir_real` (caminhos canonicalizados e validados).
- Fatos do E2E: `e2e_snapshot_dir`, `e2e_snapshot_name`,
  `e2e_snapshot_capabilities` (`snapshot_source`), `e2e_snapshot_stage_dir`
  (`snapshot_stage`), `e2e_host_capabilities` (`e2e_preflight`).
  `boot_guest_agent_available` (role `boot`) informa se o clone oferece o QEMU
  guest agent e é registrado em `e2e-vars.yml` para o `verify`.

## Fatos do host de referência (detectados)

- Arch Linux, BTRFS com `@` (raiz) e `@home`, topo montado em `/mnt/btrfs-top`.
- Snapshots em `/mnt/btrfs-top/timeshift-btrfs/snapshots` (Timeshift 25.12).
- `/boot` é um ESP vfat **separado**, fora do snapshot BTRFS.
- Kernel em `/usr/lib/modules/<ver>/vmlinuz` (esse sim dentro do snapshot).
- QEMU 11.1, libvirt 12.7, rede `default` ativa, KVM aninhado habilitado.
- OVMF code/vars em `/usr/share/edk2/x64/{OVMF_CODE,OVMF_VARS}.4m.fd`.
- `sgdisk`, `mkfs.fat` e `arch-chroot` instalados no host antes do Tier 2.

## Modelo de segurança

- Padrão `confirm_restore: false`.
- `vm_disk` canonicalizado e restrito a `vm_images_dir`.
- Troca atômica do qcow2 (novo arquivo pronto antes de remover o antigo).
- Mounts efêmeros: o `/etc/fstab` do host nunca é alterado.
- Todo caminho mutante passa por `block/rescue/always` + role `cleanup`.
- No E2E, os snapshots reais nunca são mutados: o `snapshot_stage` cria cópias
  read-only; criação de snapshot é opt-in com confirmação dupla
  (`snapshot_source_create` + `snapshot_source_create_confirm`).

## Isolamento de teste

- Tier 1: container Docker descartável (sem privilégio). Cobre os contratos
  de `snapshot_source` e `e2e_preflight` com fixtures sintéticas.
- Tier 2: sandbox local com qcow2 temporário e snapshots sintéticos
  (loopback BTRFS). Nenhum teste toca `/data/libvirt/images` ou os snapshots
  reais.
- Tier 3: VM descartável com KVM aninhado; o snapshot real é usado apenas
  como fonte, via cópia de staging read-only em `/var/tmp`,
  e removida no `e2e_cleanup`.
