# Roteiro de melhorias

Próximos passos para tornar a ferramenta mais **segura**, **production-ready** e
de **uso standalone**. Itens marcados com prioridade são a ordem sugerida de
execução (impacto × esforço). Cada item deve manter lint, syntax e os Tiers
verdes ao ser concluído.

## Status (2026-09-23)

Implementado (hardenização Fase 6.2):

- S1 · sudo escopado ao wrapper (`sudoers/arch-timeshift-vm`, instalável via
  `arch-timeshift-vm install`). Limitação documentada: permissões por binário
  não casam com o `/bin/sh -c` do `become` do Ansible.
- S2 · proveniência obrigatória (`created`/`hostname`) e manifest sha256 dos
  payloads de boot.
- S3 · rede isolada por padrão (`vm_network_mode: isolated`).
- S4 · log de auditoria (`ANSIBLE_LOG_PATH` por execução no wrapper) + resumo
  de auditoria no playbook.
- S5 · `e2e_snapshot_manifest` (sha256 de `info.json`) verificado no staging.
- P1 · CI no repositório (`ci.yml`, `release.yml`).
- P2 · coleções pinadas exatas (`ansible.posix==2.2.2`).
- P3 · crash recovery (recusa estado sujo) + `flock` no wrapper.
- P4 · `arch-timeshift-vm plan` (dry-run `--check --diff`).
- P5 · `pip-audit` + `trivy` no CI.
- S11 · CLI único `arch-timeshift-vm`.
- S12 · instalador: `arch-timeshift-vm install`/`init`, PKGBUILD.

Pendente (exige host real / runner dedicado):

- P1 (Tier 3 em runner self-hosted) — workflow cego preparado.
- S13 · runner em container — scaffolding (`container/Containerfile`) sem
  validação em host real.

## Segurança

### S1 · Sudo escopado (prioridade 2)

Hoje o pipeline roda com `sudo` irrestrito sobre `localhost`. Reduzir a área de
explosão concedendo ao usuário de execução **somente** os binários exatos de que
o pipeline precisa.

- `sudoers.d/` com permissões por comando: `qemu-img`, `qemu-nbd`, `virsh`,
  `mount`/`umount`, `mkfs.fat`, `mkfs.btrfs`, `sgdisk`, `btrfs`,
  `systemctl --root`, `arch-chroot` e o `ansible-playbook` do wrapper.
- Alternativa: conta de serviço dedicada + polkit para libvirt
  (`qemu:///system`).
- O playbook passa a detectar e **falhar com mensagem clara** se as permissões
  escopadas ausentes.

Critérios: rodar as fases 1-6 sem `sudo` irrestrito; Tier 1/2 verdes; docs de
instalação atualizadas.

### S2 · Hardening de snapshot hostil (prioridade 3)

O conteúdo do clone é **executável**: kernel/initramfs semeados na ESP, units
systemd processadas via `systemctl --root`, GRUB instalado. Um snapshot
comprometido é superfície de injeção.

- Ancorar provenance: snapshot deve estar em subvolume confiável e o
  `info.json` deve ser consistente (data/hostname).
- Manifest sha256 do par `vmlinuz`/`initramfs` escolhido, conferido antes de
  semear a ESP; recusar conteúdo inesperado nas units habilitadas.
- Garantir regeneração de `/etc/machine-id` e hostname do clone (evita
  identidade duplicada e vazamento de fingerprint do host).

### S3 · Isolar a rede da VM por default (prioridade media)

O default atual é a rede NAT `default` do libvirt, com saída livre para a
internet. Para um sandbox descartável:

- Rede **isolada** (`virbr_isolated`) ou **sem NIC** como default.
- `network_name` continua configurável via `group_vars`/`-e`.
- Documentado que mudar para rede externa é decisão explícita.

### S4 · Audit log estruturado (prioridade media)

Registrar cada execução de forma auditável, não só no stdout:

- Log JSON em journald + arquivo: snapshot resolvido, paths canonicalizados,
  UUID do domínio, comandos `virsh`, início/fim e exit code.
- Exit codes documentados (0 ok, 1 falha, 2 invariante de segurança).
- `stdout_callback = json` para runs programáticos e redirecionáveis.

### S5 · Fonte E2E à prova de adulteração

Entre o preflight e o staging, a fonte pode mudar. Conferir a integridade da
fonte selecionada:

- sha256 do snapshot (ou dos arquivos-chave) gerado no `snapshot_source` e
  verificado no `snapshot_stage`.
- Mismatch ⇒ aborte antes de tocar qualquer disco.

## Production-ready

### P1 · CI no repositório (prioridade 5)

Hoje a validação vive só no `Makefile` local:

- GitHub Actions: `make lint` + Tier 1 em push/PR.
- E2E (Tier 3) noturno em runner com snapshot real; opt-in por label/secret.
- Tag `v*` → release draft com o texto do `CHANGELOG.md`.

### P2 · Pin exato de coleções (prioridade baixa)

- `requirements.yml` com versão exata (hoje `>=2.2.0,<3.0.0`).
- `requirements.lock` gerado pelo galaxy para reprodução determinística.

### P3 · Crash recovery + lock (prioridade 4)

Execuções interrompidas podem deixar estado sujo (mounts vivos, NBD
conectado, qcow2 órfão):

- Detectar no preflight: mounts em `work_dir`, `/dev/nbd*` ativos, qcow2 do
  `vm_name` existente.
- Recusar iniciar sobre estado sujo (`--force-cleanup` explícito para limpar).
- Lockfile para impedir duas execuções concorrentes.

### P4 · Modo plan / dry-run

- `--check`/`--plan`: imprimir as operações (caminhos, tamanhos, fases) sem
  mutar disco nem libvirt.
- Complementa `confirm_restore: false` (que hoje cobre só o preflight).

### P5 · Scanners de segurança no CI

- `pip-audit` nas dependências de dev (requirements-dev.txt).
- `trivy` na imagem do Tier 1 (`molecule/default`).

## Uso standalone

### S11 · CLI único `arch-timeshift-vm` (prioridade 1)

Um entrypoint que elimina o pitfall documentado do `sudo ansible-playbook`:

- Subcomandos: `restore`, `e2e`, `preflight`, `validate`, `cleanup`.
- Resolve venv, coleções, `PATH` e sudo por conta própria.
- Precedência de config: `/etc/arch-timeshift-vm/config.yml` →
  `~/.config/arch-timeshift-vm/config.yml` → `group_vars/all.yml`.

### S12 · Instalador (prioridade media)

- `make install` provisiona venv, coleções, sudoers escopado e symlink em
  `/usr/local/bin`.
- `arch-timeshift-vm init` gera config validada e `validate` confere as
  capacidades do host antes de rodar.
- PKGBUILD (Arch) + `setup.sh` genérico para demais distros.

### S13 · Runner em container

Portabilidade para hosts sem `qemu-nbd`/`mkfs.btrfs` locais (Debian/Ubuntu):

- Podman `--privileged`, montando `/dev`, socket libvirt e o topo BTRFS.
- Imagem OCI versionada e assinada, com o ansible + coleções embutidos.
- Mais forte para "roda de qualquer lugar", porém o mais invasivo — tratar
  como fase própria com E2E dedicado.

## Priorização sugerida

| Ordem | Item | Frente | Impacto |
| --- | --- | --- | --- |
| 1 | S11 · CLI único | standalone | alto |
| 2 | S1 · sudo escopado | segurança | alto |
| 3 | S2 · hardening de snapshot hostil | segurança | alto |
| 4 | P3 · crash recovery + lock | produção | médio |
| 5 | P1 · CI no repositório | produção | médio |
| 6 | S12 · instalador | standalone | médio |
| 7 | S3 · rede isolada | segurança | médio |
| 8 | S4 · audit log | segurança | médio |
| 9 | P4 · modo plan/dry-run | produção | médio |
| 10 | S5 · checksum da fonte E2E | segurança | baixo |
| 11 | P2 · pin de coleções | produção | baixo |
| 12 | P5 · scanners no CI | produção | baixo |
| 13 | S13 · runner em container | standalone | alto (esforço) |