# Plano de implementação da Fase 6

Este documento transforma os cinco requisitos restantes em módulos verificáveis
do projeto. A ordem foi escolhida para permitir falhas antecipadas antes de
criar uma VM ou modificar uma imagem de disco.

## Princípios

- Validação é somente leitura por padrão.
- Criar um snapshot Timeshift é uma operação explícita e separada da validação.
- Nenhum módulo deve selecionar ou remover snapshots automaticamente.
- O E2E nunca deve descobrir um snapshot válido por heurística silenciosa:
  o snapshot usado deve ser registrado nos artefatos do teste.
- Os módulos devem publicar fatos Ansible reutilizáveis e mensagens de erro
  acionáveis.

## Módulos planejados

| Módulo | Responsabilidade | Mutação padrão | Saída principal |
| --- | --- | --- | --- |
| `snapshot_source` | localizar, criar opcionalmente e validar o snapshot Timeshift | somente leitura | `e2e_snapshot_dir`, `e2e_snapshot_name`, `e2e_snapshot_capabilities` |
| `snapshot_stage` | criar cópia BTRFS read-only sendable para o E2E | staging descartável | `e2e_snapshot_stage_dir` |
| `e2e_preflight` | validar KVM, libvirt, OVMF, ferramentas, espaço e permissões | somente leitura | `e2e_host_capabilities` |
| `e2e_boot` | executar o pipeline completo e verificar o boot | cria recursos temporários | estado do domínio e evidências |
| `e2e_cleanup` | remover domínio, NVRAM, XML, imagem, mounts e NBD | destrutiva, limitada ao sandbox | `e2e_cleanup_report` |
| `e2e_docs` | manter instruções, segurança, troubleshooting e changelog | nenhuma | documentação versionada |

O módulo `e2e_boot` foi materializado como o cenário Molecule
[`molecule/e2e`](../molecule/e2e/), que reutiliza os roles do pipeline
(`snapshot`, `disk`, `restore`, `boot`, `libvirt`) com `libvirt_uri:
qemu:///system`. O módulo `e2e_docs` foi materializado como os arquivos
`README.md`, `docs/{USAGE,SAFETY,TROUBLESHOOTING,ARCHITECTURE}.md`,
`CHANGELOG.md` e `CONTRIBUTING.md`.

Os módulos devem ser roles Ansible ou includes de tarefas, seguindo o padrão
dos roles existentes. O primeiro módulo é pré-requisito dos demais.

## 1. Snapshot Timeshift bootável

### Objetivo

Obter um snapshot Timeshift real que possa ser restaurado pelo pipeline e
validar, antes do E2E, que ele contém os artefatos necessários para boot UEFI.

### Separação obrigatória

O módulo `snapshot_source` terá dois modos independentes:

1. **Validar snapshot existente** — modo padrão, somente leitura.
2. **Criar snapshot** — opt-in explícito, usando a ferramenta Timeshift, sem
   apagar snapshots existentes.

A criação não deve acontecer implicitamente quando a validação falhar. Um
snapshot inválido deve produzir uma mensagem clara, não disparar uma nova
operação de backup.

### Interface proposta

Variáveis:

```yaml
e2e_snapshot_root: /mnt/btrfs-top/timeshift-btrfs/snapshots
e2e_snapshot: latest
e2e_snapshot_create: false
e2e_snapshot_create_comment: arch-timeshift-vm-e2e
e2e_snapshot_tags: O
e2e_snapshot_require_boot_artifacts: true
```

Quando `e2e_snapshot_create: true`, o usuário deve executar com privilégio e
confirmar explicitamente a operação:

```bash
sudo ansible-playbook playbooks/prepare-e2e.yml \
  -e e2e_snapshot_create=true \
  -e e2e_snapshot_create_confirm=true
```

O módulo deve recusar a criação se a confirmação não for verdadeira. O
comando exato de criação deve ser encapsulado no role, validado com
`command -v timeshift` e registrado no resultado; não deve ser executado pelo
E2E diretamente.

### Resolução do snapshot

Para `e2e_snapshot: latest`, o role deve:

1. localizar o diretório de snapshots configurado;
2. considerar somente diretórios de snapshot;
3. ordenar por nome de forma determinística;
4. selecionar o último;
5. publicar o caminho absoluto e o nome escolhido;
6. validar o snapshot selecionado antes de continuar.

Para um nome explícito, o role deve validar exatamente esse diretório e nunca
fazer fallback para `latest`.

### Validações

O módulo deve validar:

- diretório do snapshot e caminho canonicalizado;
- `@`, `@home` e `info.json`;
- `info.json` com tipo BTRFS e os subvolumes esperados;
- `@` como subvolume somente leitura (`ro=true`); mount BTRFS `ro` sozinho
  não é suficiente para `btrfs send`;
- kernel em `@/usr/lib/modules/*/vmlinuz`;
- `grub-install` em `@/usr/bin/grub-install`;
- `mkinitcpio` em `@/usr/bin/mkinitcpio`;
- `/etc/fstab` existente ou uma justificativa explícita para ausência;
- espaço disponível para a imagem temporária;
- nenhum caminho resolvido fora da raiz de snapshots permitida.

As validações de kernel, GRUB e `mkinitcpio` devem ser fatos de capacidade, por
exemplo:

```yaml
e2e_snapshot_capabilities:
  has_kernel: true
  has_grub_install: true
  has_mkinitcpio: true
  bootable_candidate: true
```

### Fixture de validação

Antes de usar um snapshot real, o módulo deve ter testes Tier 1 para:

- recusar confirmação ausente na criação;
- resolver `latest`;
- recusar nome inexistente;
- aceitar um snapshot válido;
- recusar `info.json` inválido;
- recusar snapshot sem kernel quando boot é obrigatório.

O Tier 2 pode montar um BTRFS sintético e validar a estrutura, mas não deve
simular artefatos de boot como se tivesse provado boot real. O boot só é
comprovado pelo Tier 3.

## 2. Preflight do host E2E

O role `e2e_preflight` deve verificar sem alterar o host:

- `/dev/kvm` acessível;
- `virsh`, `qemu-system-x86_64`, `qemu-img`, `qemu-nbd`;
- `btrfs`, `sgdisk`, `mkfs.fat`, `arch-chroot`;
- `grub-install`, `grub-mkconfig`, `mkinitcpio`;
- OVMF code e vars;
- rede libvirt configurada e ativa;
- conexão explicitamente em `qemu:///system`, sem confundir com
  `qemu:///session`;
- espaço livre para o sandbox;
- permissões para executar libvirt e dispositivos necessários.

Os comandos ausentes devem ser reportados em uma única falha.

## 3. Execução e verificação do E2E

O cenário `molecule/e2e` deve consumir somente os fatos publicados por
`snapshot_source` e `e2e_preflight`. Deve:

1. criar uma imagem temporária;
2. restaurar o snapshot;
3. instalar kernel/initramfs/GRUB;
4. definir e iniciar o domínio UEFI;
5. verificar `virsh domstate`;
6. coletar XML, domínio, disco e logs seriais;
7. distinguir VM iniciada de sistema operacional efetivamente pronto.

O estado `running` prova que o processo QEMU iniciou, mas não prova que o
guest terminou o boot. A verificação final deve usar um sinal do guest, como
console serial, QEMU guest agent ou SSH, conforme a capacidade do snapshot.

## 4. Cleanup e evidências

O cleanup deve rodar em sucesso e falha, sem remover nada fora do sandbox
resolvido. Deve tentar, nesta ordem:

1. desligar a VM;
2. `undefine --nvram`;
3. remover XML e NVRAM;
4. desmontar mounts;
5. desconectar NBD;
6. remover a imagem temporária;
7. verificar ausência de domínio, processos, mounts e arquivos residuais.

O cleanup deve preservar snapshots Timeshift e `/etc/fstab` do host.

## 5. Documentação e release

Os documentos finais devem cobrir:

- `README.md`: fluxo curto e comandos;
- `docs/USAGE.md`: execução normal e E2E;
- `docs/SAFETY.md`: operações destrutivas e confirmações;
- `docs/TROUBLESHOOTING.md`: falhas de snapshot, BTRFS, libvirt e boot;
- `docs/ARCHITECTURE.md`: módulos e fatos compartilhados;
- `CHANGELOG.md`: mudanças por versão/fase;
- `CONTRIBUTING.md`: lint, syntax, Tiers e commits;
- `LICENSE`: licença do projeto.

## Ordem de execução

1. Implementar `snapshot_source` e seu playbook `prepare-e2e.yml`. ✅
2. Criar `snapshot_stage` e usar somente a cópia read-only no E2E. ✅
3. Validar fixture sintética e um snapshot real em modo somente leitura. ✅
4. Implementar `e2e_preflight`. ✅
5. Integrar os fatos aos cenários Molecule. ✅
6. Executar `make e2e` com criação de snapshot desligada. ✅ (2026-09-20)
7. Aperfeiçoar a verificação de boot do guest. ⏳ aberto (não bloqueia o gate)
8. Fechar documentação, changelog e gate da Fase 6. ✅

## Critério de conclusão

A Fase 6 está concluída; os itens abaixo foram atendidos ou permanecem abertos
de forma explícita:

- um snapshot bootável tenha sido validado; ✅
- `make e2e` tiver iniciado e verificado a VM; ✅
- a verificação do guest tiver evidência além do processo QEMU, quando
  disponível; ⏳ hoje confia em `virsh domstate` + disco anexado; sinal do
  guest (serial/agente/SSH) é melhoria aberta;
- cleanup tiver deixado zero resíduo; ✅
- `make lint`, `make syntax`, `make test` e o Tier 2 continuarem verdes; ✅
- a documentação final estiver completa. ✅
