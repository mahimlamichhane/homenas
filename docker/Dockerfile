FROM nextcloud:35-apache
RUN set -eux; apt-get update; \
    EXTRA="$(apt-cache search --names-only '^libmagickcore-[0-9.]+q16[^ ]*-extra$' | awk '{print $1}' | head -n1)"; \
    apt-get install -y --no-install-recommends ffmpeg imagemagick ghostscript $EXTRA; \
    rm -rf /var/lib/apt/lists/*; \
    for p in /etc/ImageMagick-*/policy.xml; do [ -f "$p" ] && sed -i -E 's#(rights=")none(" pattern="(PDF|PS|EPS|XPS)")#\1read\2#' "$p"; done
