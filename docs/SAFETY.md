# Segurança

Este documento descreve o modelo de segurança das operações destrutivas, as
confirmações exigidas e os limites de mutação de cada comando.

## Princípios

- `confirm_restore: false` por padrão: `playbooks/restore.yml` recusa executar
  sem `-e confirm_restore=true`. O CLI `arch-timeshift-vm` exige o flag
  explícito para `restore`, `plan`, `preflight` e `cleanup`, mesmo quando o
  valor está em um arquivo de config.
- O modo somente leitura (`confirm_restore=false`) e o `--check` nunca mutam o
  host.
- Todo caminho destrutivo é canonicalizado e validado **antes** de qualquer
  remoção.
- Nada é apagado antes de o novo artefato estar pronto (troca atômica do
  qcow2).
- Mounts BTRFS e da ESP são efêmeros: o `/etc/fstab` do host nunca é alterado.
- Os snapshots Timeshift reais nunca são modificados pelo pipeline. O E2E usa
  cópias de staging read-only.
- `cleanup`/teardown roda sempre, inclusive em falha
  (`block/rescue/always`).
- O mount BTRFS temporário do topo é liberado num bloco `always` de
  `preflight.yml`/`restore.yml`: um guard que aborta o play não deixa o host
  segurando mount do próprio snapshot.
- Rede da VM isolada por padrão: `vm_network_mode: isolated` (sem NAT, sem
  saída externa); `default` e `none` são escolhas explícitas.
- Recusa rodar sobre estado sujo deixado por uma execução interrompida:
  mounts sob `work_dir`, NBD servindo o disco, ou `qcow2.new` órfão.
- Proveniência do snapshot exigida: `info.json` precisa trazer `created` e
  `sys-uuid` (o UUID do filesystem raiz que o Timeshift grava; ele não escreve
  `hostname`). O hostname exibido na auditoria vem do `/etc/hostname` de dentro
  do snapshot, e é informativo. Manifest sha256 dos payloads de boot semeados
  na ESP.
- Auditoria de boot state: o `preflight` avisa (ou aborta com
  `snapshot_refuse_live_boot_state=true`) quando o snapshot avaliado é o
  subvolume do qual o host está rodando — nesse caso ele não representa um boot
  passado. A comparação por subvolume ID é feita apenas dentro do mesmo
  filesystem.
- Execuções concorrentes são bloqueadas por `flock` no wrapper.
- Sudo escalonado opcional restrito ao wrapper (`sudoers/arch-timeshift-vm`):
  o playbook escalona via `/bin/sh` do Ansible, então permissões por binário
  não casam; o contorno seguro é autorizar sem senha somente o wrapper.

## Operações destrutivas e confirmações

| Operação | Comando / playbook | Confirmação exigida | Limite de mutação |
| --- | --- | --- | --- |
| Recriar `vm_disk` a partir de um snapshot | `playbooks/restore.yml` | `confirm_restore=true` | somente o disco sob `vm_images_dir`; domínio `vm_name` |
| Remover o disco da VM | `restore` / teardown | via `confirm_restore` | arquivo `vm_disk` canonicalizado, sob `vm_images_dir` |
| Criar um snapshot Timeshift novo | `playbooks/prepare-e2e.yml` | `snapshot_source_create=true` **e** `snapshot_source_create_confirm=true` | instala o snapshot usando o `timeshift`; nunca apaga snapshots existentes |
| Criar a cópia read-only do snapshot | role `snapshot` (preflight/restore/E2E) | implícito em `confirm_restore=true` | `btrfs subvolume snapshot -r` em `snapshot_stage_root` (mesmo BTRFS); o snapshot real só é lido; a cópia é removida no `always` |
| Preparar a rede libvirt padrão | `prepare-e2e.yml` | `e2e_preflight_prepare_network=true` | define/habilita/inicia a rede em `/etc/libvirt/qemu/networks/<name>.xml` |
| Remover artefatos E2E | `make clean-e2e` / `e2e_cleanup` | opcional (comando explícito) | somente `/var/tmp/arch-timeshift-vm-e2e`, `/var/tmp/arch-timeshift-vm-stage` e o domínio `e2e_vm_name` |
| Remover VM restaurada e estado | `arch-timeshift-vm cleanup` / `playbooks/cleanup.yml` | `confirm_restore=true` | domínio `vm_name`, NVRAM/XML sob `work_dir`, disco `vm_disk` e mounts/NBD órfãos sob `work_dir` |

## Garantias do E2E

- O snapshot usado é resolvido de forma determinística (`latest` ou nome
  exato) e registrado em `e2e-vars.yml`; não há seleção heurística silenciosa.
- O `@`/`@home` reais nunca são ajustados: o role `snapshot` tira uma cópia
  copy-on-write read-only (`btrfs subvolume snapshot -r`) e o `restore` envia a
  cópia. Um snapshot read-write do Timeshift funciona sem nenhuma mutação.
- Nenhum fluxo grava na árvore de snapshots: a cópia vive em
  `snapshot_stage_root` (mesmo filesystem BTRFS) e é removida ao fim do run.
- O cleanup remove apenas o sandbox resolvido e o domínio nomeado; caminhos
  fora do sandbox são rejeitados.

## Limites atualizados em `group_vars/all.yml`

Revise antes de executar:

- `confirm_restore`, `vm_name`, `vm_disk`, `vm_images_dir`, `vm_disk_size`.
- `libvirt_start`, `libvirt_attach_iso`, `libvirt_graphics`.

Veja também [`docs/USAGE.md`](USAGE.md) e [`docs/ARCHITECTURE.md`](ARCHITECTURE.md).