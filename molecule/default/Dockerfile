FROM docker.io/library/archlinux:base

# Tier 1 only needs a Python interpreter for Ansible on the managed node.
RUN pacman -Sy --noconfirm python \
    && pacman -Scc --noconfirm
