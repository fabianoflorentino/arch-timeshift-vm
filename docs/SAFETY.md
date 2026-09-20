# Segurança

Este documento descreve o modelo de segurança das operações destrutivas, as
confirmações exigidas e os limites de mutação de cada comando.

## Princípios

- `confirm_restore: false` por padrão: `playbooks/restore.yml` recusa executar
  sem `-e confirm_restore=true`.
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

## Operações destrutivas e confirmações

| Operação | Comando / playbook | Confirmação exigida | Limite de mutação |
| --- | --- | --- | --- |
| Recriar `vm_disk` a partir de um snapshot | `playbooks/restore.yml` | `confirm_restore=true` | somente o disco sob `vm_images_dir`; domínio `vm_name` |
| Remover o disco da VM | `restore` / teardown | via `confirm_restore` | arquivo `vm_disk` canonicalizado, sob `vm_images_dir` |
| Criar um snapshot Timeshift novo | `playbooks/prepare-e2e.yml` | `snapshot_source_create=true` **e** `snapshot_source_create_confirm=true` | instala o snapshot usando o `timeshift`; nunca apaga snapshots existentes |
| Preparar a rede libvirt padrão | `prepare-e2e.yml` | `e2e_preflight_prepare_network=true` | define/habilita/inicia a rede em `/etc/libvirt/qemu/networks/<name>.xml` |
| Remover artefatos E2E | `make clean-e2e` / `e2e_cleanup` | opcional (comando explícito) | somente `/var/tmp/arch-timeshift-vm-e2e`, `/var/tmp/arch-timeshift-vm-stage` e o domínio `e2e_vm_name` |

## Garantias do E2E

- O snapshot usado é resolvido de forma determinística (`latest` ou nome
  exato) e registrado em `e2e-vars.yml`; não há seleção heurística silenciosa.
- A fonte real é validada como subvolume BTRFS `@` com `ro=true` antes de
  qualquer operação; um mount `ro` sozinho não basta para `btrfs send`.
- O E2E nunca grava na árvore de snapshots: `snapshot_stage` cria cópias
  read-only em `/var/tmp`.
- O cleanup remove apenas o sandbox resolvido e o domínio nomeado; caminhos
  fora do sandbox são rejeitados.

## Limites atualizados em `group_vars/all.yml`

Revise antes de executar:

- `confirm_restore`, `vm_name`, `vm_disk`, `vm_images_dir`, `vm_disk_size`.
- `libvirt_start`, `libvirt_attach_iso`, `libvirt_graphics`.

Veja também [`docs/USAGE.md`](USAGE.md) e [`docs/PLAN.md`](PLAN.md).