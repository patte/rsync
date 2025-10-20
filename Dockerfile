FROM debian:13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  openssh-server rsync python3-minimal ca-certificates tini \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd
RUN install -d -m 755 -o root -g root /var/rsync
RUN install -d -m 755 -o root -g root /data
RUN mkdir -p /emptyhome

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]
CMD ["/usr/sbin/sshd","-D","-e"]