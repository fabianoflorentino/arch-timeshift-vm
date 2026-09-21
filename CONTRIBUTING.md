# Contribuindo

O projeto é um playbook/roles Ansible com validação em três Tiers Molecule.
Toda mudança deve manter lint, syntax e os Tiers verdes.

## Setup

```bash
make venv          # .venv com dependências pinadas
make deps          # collections do requirements.yml
```

## Verificações local

```bash
make lint          # yamllint + ansible-lint (profile production)
make syntax        # syntax-check do playbooks/restore.yml
make test          # Molecule Tier 1 (Docker, sem privilégio)
make test-integration  # Molecule Tier 2 (BTRFS sintético; requer sudo)
```

O Tier 3 é opt-in e exige um snapshot real bootável mais KVM aninhado:

```bash
E2E_TIMESHIFT_ROOT=/mnt/btrfs-top/timeshift-btrfs/snapshots make e2e
```

Sem o `E2E_TIMESHIFT_ROOT`, o alvo falha de propósito
(`make prepare-e2e` para validar apenas a fonte).

## Critérios antes de abrir um PR

- `make lint` limpo para o escopo alterado (role fora de `exclude_paths`).
- Testes novos cobrem positivos, negativos e resíduo/cleanup.
- A documentação afetada foi atualizada para o usuário final; não deixe
  referências quebradas entre arquivos de `docs/` e o `README.md`.
- Nenhum teste toca snapshots reais nem imagens reais.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/pt-br/) com
escopo por área, como no histórico:

```
feat(snapshot): harden preflight with auto-detection and safety guards
fix(snapshot): repair Tier 2 detection and guard the selector
feat(e2e): ...
docs: ...
test(molecule): ...
chore: ...
```

Escopos usados: `snapshot`, `disk`, `restore`, `boot`, `libvirt`, `e2e`,
`roles`, `molecule`, `readme`. Commits temáticos (um tema por commit) são
preferidos; mensagens em português são aceitas junto ao convencional.

## Segurança e foco

- Revisar `docs/SAFETY.md`: qualquer caminho destrutivo é canonicalizado e
  validado antes de remover; nunca remova a validação.
- O E2E nunca deve selecionar snapshots por heurística: preserve a resolução
  determinística e o registro em `e2e-vars.yml`.