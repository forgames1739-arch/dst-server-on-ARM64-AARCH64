FROM sonroyaalmerol/steamcmd-arm64:root-bookworm

# Переименовываем встроенного пользователя steam в ubuntu.
# -m переносит домашнюю папку, UID/GID остаются теми же,
# поэтому все права на уже установленный SteamCMD сохраняются.
RUN usermod -l ubuntu -d /home/ubuntu -m steam \
    && groupmod -n ubuntu steam

USER ubuntu
WORKDIR /home/ubuntu

ENV DST_APPID=343050 \
    HOME=/home/ubuntu

RUN mkdir -p /home/ubuntu/dst/save

COPY --chown=ubuntu:ubuntu entrypoint.sh /home/ubuntu/entrypoint.sh
RUN chmod +x /home/ubuntu/entrypoint.sh

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
