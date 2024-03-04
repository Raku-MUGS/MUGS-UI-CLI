ARG mugs_version=latest
FROM mugs-games:$mugs_version
ARG mugs_version

LABEL org.opencontainers.image.source=https://github.com/Raku-MUGS/MUGS-UI-CLI

USER root:root

RUN apt-get update \
 && apt-get -y --no-install-recommends install build-essential \
 && zef update \
 && zef install Term::termios:ver'<0.2>' \
 && rm -rf /root/.zef \
 && chgrp raku /tmp/.zef \
 && chmod g+w /tmp/.zef \
 && apt-get purge -y --auto-remove build-essential \
 && rm -rf /var/lib/apt/lists/*

USER raku:raku

WORKDIR /home/raku/MUGS/MUGS-UI-CLI
COPY . .

RUN zef install --deps-only . \
 && zef install --/test . \
 && rm -rf /home/raku/.zef $(find /tmp/.zef -maxdepth 1 -user raku)

CMD ["mugs-cli"]
